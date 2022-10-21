// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMain.sol";
import "./IParameters.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "hardhat/console.sol";

/// @title Main logic contract for Bolt Protocol
contract Main is IMain, MainStructs {
    using Counters for Counters.Counter;
    string public constant UNLOCK_MESSAGE_PREFIX =
        "\x19Bolt Signed Unlock Message:\n32";
    string public constant RELAY_MESSAGE_PREFIX =
        "\x19Bolt Signed Relay Message:\n64";
    Networks public immutable CURRENT_NETWORK;
    address public constant NATIVE_TOKEN_ADDRESS =
        0x0000000000000000000000000000000000000000;
    IParameters public immutable params;
    address public immutable PROTOCOL_FEE_RECIPIENT;

    mapping(address => BoltRelayer) public boltRelayers;
    address[] public boltRelayerAddresses;
    Counters.Counter private swapCounter;
    mapping(bytes32 => SwapData) public swaps;
    mapping(bytes32 => FulfillData) public fulfills; // TODO: after they finalize, move swaps & fulfills entries to "completed" mapping to free up storage

    mapping(bytes32 => uint) public lockedFunds;

    constructor(
        Networks _net,
        address _params,
        address _feeRecipient
    ) {
        CURRENT_NETWORK = _net;
        params = IParameters(_params);
        PROTOCOL_FEE_RECIPIENT = _feeRecipient;
    }

    /// @notice Any relayer can add stake to take swap requests & earn fees;
    /// @notice the stake is bound to one route, which consist of source & destination networks (stake amounts must be identical)
    /// @param routes Routes to stake funds to e.g. [(ETH, PLG), (ETH, AVAX)]
    /// @param amounts The amount to stake for each route
    /// @param token The token to stake (zero for native coin)
    function stake(
        Route[] memory routes,
        uint[] memory amounts,
        address token
    ) external payable validRoutes(routes) {
        uint totalAmount = 0;
        BoltRelayer storage r = boltRelayers[msg.sender];
        uint[] memory routeIds = new uint[](routes.length);
        for (uint i = 0; i < routes.length; i++) {
            routeIds[i] = getRouteID(routes[i]);
            StakedFunds storage sf = boltRelayers[msg.sender].stakesByRoute[
                routeIds[i]
            ];
            sf.stakeByToken[token] += amounts[i];
            totalAmount += amounts[i];
        }
        if (token == NATIVE_TOKEN_ADDRESS) {
            require(totalAmount == msg.value, "stake native amount invalid");
        } else {
            TransferHelper.safeTransferFrom(
                token,
                msg.sender,
                address(this),
                totalAmount
            );
        }
        if (r.unstakeEnableBlock == 0) {
            // new relayer
            r.unstakeEnableBlock =
                block.number +
                params.durationToFirstUnstake();
            boltRelayerAddresses.push(msg.sender);
        }

        emit Stake(msg.sender, routeIds, amounts, token);
    }

    function unstake(
        Route memory route,
        uint amount,
        address token
    ) external {
        BoltRelayer storage r = boltRelayers[msg.sender];
        StakedFunds storage sf = r.stakesByRoute[getRouteID(route)];
        uint stakedAmount = sf.stakeByToken[token];
        uint lockedAmount = sf.totalLockedByToken[token];
        require(
            block.number >= r.unstakeEnableBlock,
            "first unstake time not met"
        );
        require(stakedAmount > 0 && stakedAmount > lockedAmount, "unstake zero");
        require(amount <= stakedAmount - lockedAmount, "unstake exceeds amount");

        swapCounter.increment();
        uint unlockTime = _lockStake(
            amount,
            swapCounter.current(),
            getRouteID(route),
            token,
            address(0), // must always wait full unstake duration
            msg.sender,
            bytes32(0),
            LockTypes.UNSTAKE
        );
        emit Unstake(msg.sender, getRouteID(route), amount, token, unlockTime);
    }

    function _getStakedFunds(
        address relayerAddr,
        Route memory route,
        address token
    ) internal view returns (uint) {
        BoltRelayer storage r = boltRelayers[relayerAddr];
        return r.stakesByRoute[getRouteID(route)].stakeByToken[token];
    }

    function getRouteID(Route memory r) public pure returns (uint) {
        return uint(r.src) * 256 + uint(r.dst);
    }

    modifier validRoutes(Route[] memory rs) {
        for (uint i = 0; i < rs.length; i++) {
            require(rs[i].src != rs[i].dst, "ROUTE invalid");
            require(
                rs[i].src == CURRENT_NETWORK || rs[i].dst == CURRENT_NETWORK,
                "route must contain current net"
            );
        }
        _;
    }

    modifier validSrc(Route memory r) {
        require(r.src != r.dst, "ROUTE invalid");
        require(r.src == CURRENT_NETWORK, "SRC invalid");
        _;
    }

    modifier validDst(Route memory r) {
        require(r.src != r.dst, "ROUTE invalid");
        require(r.dst == CURRENT_NETWORK, "DST invalid");
        _;
    }

    function swap(
        uint amount,
        address boltRelayerAddr,
        Route memory route,
        ExecutableMessage calldata srcMsg,
        ExecutableMessage calldata dstMsg
    ) external payable {
        SwapData memory newSwapData;
        uint lockAmount;
        {
            require(route.src == CURRENT_NETWORK, "swap srcNetwork invalid");
            (address returnToken, uint returnAmt) = _executeSrcMsg(
                amount,
                srcMsg
            );
            require(
                returnToken == srcMsg.tokenOut,
                "swap srcMsg tokenOut mismatch"
            );

            uint availableStake = getAvailableStake(
                boltRelayerAddr,
                route,
                srcMsg.tokenOut
            );
            (uint[] memory fees, uint crossAmount) = getSwapFees(returnAmt);
            uint totalFees;
            for (uint i = 0; i < fees.length; i++) {
                totalFees += fees[i];
            }
            lockAmount = getLockAmount(crossAmount);
            require(
                availableStake >= lockAmount,
                "swap: relayer insufficient stake"
            );

            swapCounter.increment();
            // store new swap data
            newSwapData = SwapData(
                swapCounter.current(),
                msg.sender,
                boltRelayerAddr,
                route,
                crossAmount,
                totalFees,
                srcMsg,
                dstMsg,
                Status.WAITING
            );
        }
        bytes32 h = computeSwapID(newSwapData);
        _lockStake(
            lockAmount,
            newSwapData.nonce,
            getRouteID(newSwapData.route),
            srcMsg.tokenOut,
            newSwapData.requester,
            boltRelayerAddr,
            h,
            LockTypes.SWAP_LOCK
        );
        swaps[h] = newSwapData;
        emit Swap(msg.sender, boltRelayerAddr, getRouteID(route), h);
    }

    function computeSwapID(SwapData memory s) public pure returns (bytes32) {
        // require(s.status == Status.WAITING, "swap status invalid for hashing");
        (bytes32 temp1, bytes32 temp2) = (getMsgHash(s.srcMsg), getMsgHash(s.dstMsg));
        temp1 = keccak256(abi.encodePacked(temp1, temp2));
        bytes memory content = abi.encodePacked(s.nonce, s.requester, s.boltRelayerAddr, getRouteID(s.route), s.crossAmount, s.totalFees, temp1); // TODO: non-EVM-specific marshalling
        return keccak256(content);
    }

    function getMsgHash(ExecutableMessage memory m) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(m.tokenIn, m.tokenOut, m.callAddress, m.callData));
    }

    function _lockStake(
        uint amount,
        uint nonce,
        uint routeID,
        address token,
        address depositor,
        address raddr,
        bytes32 h,
        LockTypes ltype
    ) internal returns (uint unlockTime) {
        if (ltype == LockTypes.UNSTAKE) {
            unlockTime = block.number + params.durationToUnstake();
        } else if (ltype == LockTypes.SWAP_LOCK) {
            unlockTime = block.number + params.lockDuration();
            StakedFunds storage stakes = boltRelayers[raddr].stakesByRoute[
                routeID
            ];
            uint newTotalLocked = stakes.totalLockedByToken[token] + amount;
            require(
                newTotalLocked <=
                    boltRelayers[raddr].stakesByRoute[routeID].stakeByToken[
                        token
                    ],
                "lock exceeds stake amount"
            );
            stakes.totalLockedByToken[token] = newTotalLocked;
        } else if (ltype == LockTypes.PENDING_REWARD) {
            unlockTime = block.number + params.lockDuration();
        } else {
            revert("invalid stake lock type");
        }

        bytes32 mapkey = keccak256(
            abi.encodePacked(
                amount,
                nonce,
                routeID,
                token,
                depositor,
                raddr,
                h,
                ltype
            )
        );

        lockedFunds[mapkey] = unlockTime;
        emit Lock(ltype, amount, nonce, routeID,
                token,
                depositor,
                raddr,
                h);
        return unlockTime;
    }

    function unlock(
        uint amount,
        uint nonce,
        uint routeID,
        address token,
        address depositor,
        address receiver,
        bytes32 swapID,
        LockTypes lockType
    ) external {
        _unlock(
            amount,
            nonce,
            routeID,
            token,
            depositor,
            receiver,
            swapID,
            lockType,
            bytes("")
        );
    }

    function depositorUnlock(
        uint amount,
        uint nonce,
        uint routeID,
        address token,
        address depositor,
        address receiver,
        bytes32 swapID,
        LockTypes lockType,
        bytes memory signature
    ) external {
        _unlock(
            amount,
            nonce,
            routeID,
            token,
            depositor,
            receiver,
            swapID,
            lockType,
            signature
        );
    }

    function _unlock(
        uint amount,
        uint nonce,
        uint routeID,
        address token,
        address depositor,
        address receiver,
        bytes32 swapID,
        LockTypes lockType,
        bytes memory signature
    ) internal {
        bytes32 mapkey = keccak256(
            abi.encodePacked(
                amount,
                nonce,
                routeID,
                token,
                depositor,
                receiver,
                swapID,
                lockType
            )
        );
        uint unlockTime = lockedFunds[mapkey];
        require(amount > 0 && unlockTime > 0, "no locked funds");
        if (depositor != address(0) && signature.length > 0) {
            // unlock by depositor signature
            bytes32 signedContent = keccak256(
                abi.encodePacked(UNLOCK_MESSAGE_PREFIX, swapID)
            );
            address recoveredAddress = ECDSA.recover(signedContent, signature);
            require(recoveredAddress == depositor, "relay signature invalid");
        } else {
            require(block.number >= unlockTime, "unlock time not met");
        }

        delete (lockedFunds[mapkey]);
        // transfer
        if (lockType == LockTypes.UNSTAKE || lockType == LockTypes.SWAP_LOCK) {
            if (token == NATIVE_TOKEN_ADDRESS) {
                TransferHelper.safeTransferETH(receiver, amount);
            } else {
                TransferHelper.safeTransfer(token, receiver, amount);
            }
        } else if (lockType == LockTypes.SWAP_LOCK) {
            uint totalLocked = boltRelayers[receiver]
                .stakesByRoute[routeID]
                .totalLockedByToken[token];
            require(totalLocked > amount, "invalid total locked amount");
            boltRelayers[receiver].stakesByRoute[routeID].totalLockedByToken[
                token
            ] = totalLocked - amount;
        }
    }

    function _updateLock(bytes32 _oldKey, bytes32 _newKey) internal {
        uint amount = lockedFunds[_oldKey];
        delete (lockedFunds[_oldKey]);
        lockedFunds[_newKey] = amount;
    }

    function _executeSrcMsg(uint amount, ExecutableMessage memory srcMsg)
        internal
        returns (address, uint)
    {
        if (srcMsg.callData.length == 0) {
            // blank msg
            require(
                srcMsg.tokenIn == srcMsg.tokenOut &&
                    srcMsg.callAddress == address(0),
                "srcMsg (blank) invalid"
            );
            if (srcMsg.tokenIn == NATIVE_TOKEN_ADDRESS) {
                require(amount == msg.value, "swap native amount invalid");
            } else {
                TransferHelper.safeTransferFrom(
                    srcMsg.tokenIn,
                    msg.sender,
                    address(this),
                    amount
                );
            }
            return (srcMsg.tokenIn, amount);
        }
        // TODO
        return (srcMsg.tokenIn, amount);
    }

    function _executeDstMsg(uint crossAmount, ExecutableMessage memory dstMsg)
        internal
        returns (address, uint)
    {
        if (dstMsg.callData.length == 0) {
            // blank msg
            require(
                dstMsg.tokenIn == dstMsg.tokenOut,
                "dstMsg (blank) invalid"
            );
            if (dstMsg.tokenIn == NATIVE_TOKEN_ADDRESS) {
                TransferHelper.safeTransferETH(dstMsg.callAddress, crossAmount);
            } else {
                TransferHelper.safeTransfer(
                    dstMsg.tokenIn,
                    dstMsg.callAddress,
                    crossAmount
                );
            }
            return (dstMsg.tokenIn, crossAmount);
        }
        // TODO
        return (dstMsg.tokenIn, crossAmount);
    }

    // TBD: internal
    function getSwapFees(uint srcAmount)
        public
        view
        returns (uint[] memory, uint)
    {
        require(uint(BoltActors.RELAYER) == 0, "fee params invalid");
        uint bp = params.BASE_PRECISION();
        uint feeActorsLen = uint(BoltActors.OPERATOR) + 1;
        uint[] memory fees = new uint[](feeActorsLen);
        uint crossAmount = srcAmount;
        for (uint i = 0; i < feeActorsLen; i++) {
            uint fee = (srcAmount * params.feePercent(i)) / bp;
            if (fee < params.minFee(i)) fee = params.minFee(i);
            fees[i] = fee;
            crossAmount -= fee;
        }
        return (fees, crossAmount);
    }

    // TBD: internal
    function getLockAmount(uint crossAmount) public view returns (uint) {
        uint x1 = params.overCollateralPercent(uint(SlashRules.RULE2));
        uint bp = params.BASE_PRECISION();
        return (crossAmount * (bp + x1)) / bp;
    }

    function getAvailableStake(
        address relayerAddr,
        Route memory route,
        address token
    ) public view returns (uint) {
        StakedFunds storage sf = boltRelayers[relayerAddr].stakesByRoute[
            getRouteID(route)
        ];
        uint l = sf.totalLockedByToken[token];
        uint s = sf.stakeByToken[token];
        require(l <= s, "invalid stake & locked amounts");
        return s - l;
    }

    function testMarshal() public pure returns (uint) {
        Route memory r;
        return abi.encodePacked(r.src, r.dst).length;
    }

    function getAvailableRelayers(
        Route memory route,
        uint amount,
        address token
    ) public view returns (address[] memory) {
        address[] memory temp = new address[](boltRelayerAddresses.length);
        uint resultLen = 0;
        for (uint i = 0; i < boltRelayerAddresses.length; i++) {
            uint stk = getAvailableStake(boltRelayerAddresses[i], route, token);
            if (stk >= amount) {
                temp[resultLen] = temp[i];
                resultLen++;
            }
        }
        address[] memory result = new address[](resultLen);
        for (uint i = 0; i < resultLen; i++) {
            result[i] = temp[i];
        }

        return result;
    }

    function fulfill(SwapData calldata s, address boltOperator)
        external
        payable
    {
        (bytes32 h, FulfillData memory f) = _fulfill(s, boltOperator);
        FulfillData storage temp = fulfills[h];
        require(
            temp.boltOperator == address(0),
            "fulfill already exists"
        );
        fulfills[h] = f;
        swaps[h] = s;
    }

    function _fulfill(SwapData calldata s, address boltOperator)
        internal
        returns (bytes32, FulfillData memory)
    {
        bytes32 h = computeSwapID(s);
        FulfillData memory fdata = FulfillData(h, block.number, boltOperator);
        require(
            s.route.dst == CURRENT_NETWORK,
            "fulfill dstNetwork invalid"
        );
        uint crossAmount = s.crossAmount;
        address crossToken = s.dstMsg.tokenIn;
        if (crossToken == NATIVE_TOKEN_ADDRESS) {
            require(crossAmount == msg.value, "fulfill native amount invalid");
        } else {
            TransferHelper.safeTransferFrom(
                crossToken,
                msg.sender,
                address(this),
                crossAmount
            );
        }

        emit Fulfill(
            boltOperator,
            s.boltRelayerAddr,
            getRouteID(s.route),
            h
        );
        return (h, fdata);
    }

    function relay(
        bytes32 swapID,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external {
        FulfillData memory f = fulfills[swapID];
        _relay(f, boltOperator, boltRelayerAddr, signature);
    }

    function fulfillAndRelay(
        SwapData calldata s,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external payable {
        (bytes32 h, FulfillData memory f) = _fulfill(s, boltOperator);
        fulfills[h] = f; // unoptimized storage
        swaps[h] = s;
        _relay(f, boltOperator, boltRelayerAddr, signature);
    }

    function _relay(
        FulfillData memory f,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) internal {
        SwapData memory swapData = swaps[f.swapID];
        // check f exists (and is non-zero)
        require(
            swapData.status != Status.INVALID && f.boltOperator != address(0),
            "fulfill non-existent"
        );
        // check operator address matches
        require(f.boltOperator == boltOperator, "relay operatorAddr mismatch");
        // check fulfillData not expired
        require(
            block.number < f.startBlock + params.lockDuration(),
            "fulfill expired"
        );
        // verify signature
        bytes32 signedContent = keccak256(
            abi.encodePacked(RELAY_MESSAGE_PREFIX, f.swapID, boltOperator)
        );
        address recoveredAddress = ECDSA.recover(signedContent, signature);
        require(recoveredAddress == boltRelayerAddr, "relay signature invalid");
        ExecutableMessage memory m = swapData.dstMsg;
        _executeDstMsg(swapData.crossAmount, m);
        _lockStake(
            getLockAmount(swapData.crossAmount),
            swapData.nonce,
            getRouteID(swapData.route),
            swapData.dstMsg.tokenIn,
            f.boltOperator,
            boltRelayerAddr,
            f.swapID,
            LockTypes.SWAP_LOCK
        );
    }

    modifier checkSanitySwap(SwapData memory s) {
        require(s.status != Status.INVALID, "swap status invalid");
        require(
            s.requester != address(0) && s.boltRelayerAddr != address(0),
            "swap u/r address invalid"
        );
        _;
    }

    function relayReturn(
        bytes32 swapID,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external {
        SwapData storage s = swaps[swapID];

        {
            // check s exists (and is non-zero)
            require(
                s.status != Status.INVALID &&
                    s.boltRelayerAddr != address(0) &&
                    s.requester != address(0),
                "swap non-existent"
            );

            // if (boltRelayerAddr != msg.sender) { // TBD: relayer might also sign blocknum
            // }
            // verify signature
            bytes32 signedContent = keccak256(
                abi.encodePacked(RELAY_MESSAGE_PREFIX, swapID, boltOperator)
            );
            address recoveredAddress = ECDSA.recover(signedContent, signature);
            require(
                recoveredAddress == boltRelayerAddr,
                "relay signature invalid"
            );
        }

        {
            // store fulfill data
            FulfillData memory fdata = FulfillData(swapID, block.number, boltOperator);
            fulfills[swapID] = fdata;

            // reset relayer's stake lock
            bytes32 mapkey = keccak256(
                abi.encodePacked(
                    getLockAmount(s.crossAmount),
                    s.nonce,
                    getRouteID(s.route),
                    s.srcMsg.tokenOut,
                    s.requester,
                    boltRelayerAddr,
                    swapID,
                    LockTypes.SWAP_LOCK
                )
            );
            uint unlockTime = lockedFunds[mapkey];
            // check swap not expired
            require(block.number < unlockTime, "swap expired");
            lockedFunds[mapkey] = block.number + params.lockDuration();
        }

        {
            // - move swap value to locked value in operator & relayer 's locked lists
            (uint[] memory fees, uint crossAmount) = getSwapFees(
                s.crossAmount + s.totalFees
            );
            require(
                crossAmount == s.crossAmount,
                "recomputed crossAmount mismatch"
            );
            _lockStake(
                crossAmount + fees[uint(BoltActors.OPERATOR)],
                s.nonce,
                getRouteID(s.route),
                s.srcMsg.tokenOut,
                s.requester,
                boltOperator,
                swapID,
                LockTypes.PENDING_REWARD
            );
            _lockStake(
                fees[uint(BoltActors.RELAYER)],
                s.nonce,
                getRouteID(s.route),
                s.srcMsg.tokenOut,
                s.requester,
                boltRelayerAddr,
                swapID,
                LockTypes.PENDING_REWARD
            );
            _lockStake(
                fees[uint(BoltActors.PROTOCOL)],
                s.nonce,
                getRouteID(s.route),
                s.srcMsg.tokenOut,
                s.requester,
                PROTOCOL_FEE_RECIPIENT,
                swapID,
                LockTypes.PENDING_REWARD
            );
        }
        s.status = Status.FULFILLED;
    }

    function slash(SlashRules rule, SwapData calldata s, address boltOperator,
        address boltRelayerAddr, bytes calldata signature)
        external
    {
        bytes32 h = computeSwapID(s);
        // verify signature
        bytes32 signedContent = keccak256(
            abi.encodePacked(RELAY_MESSAGE_PREFIX, h, boltOperator)
        );
        address recoveredAddress = ECDSA.recover(signedContent, signature);
        require(
            recoveredAddress == boltRelayerAddr,
            "slash: relay signature invalid"
        );

        uint amt;
        address token;
        if (rule == SlashRules.RULE1) {
            (amt, token) = _slashRule1(h, s, boltRelayerAddr);
        } else if (rule == SlashRules.RULE2) {
            (amt, token) = _slashRule2(h, s, boltOperator, boltRelayerAddr);
        } else {
            revert("slash rule invalid");
        }

        // update stake balances
        boltRelayers[boltRelayerAddr].stakesByRoute[getRouteID(s.route)].stakeByToken[token] -= amt;
        boltRelayers[boltRelayerAddr].stakesByRoute[getRouteID(s.route)].totalLockedByToken[token] -= amt;

        emit Slash(rule, amt, token, boltRelayerAddr, h);

        // move funds
        // will update
        if (token == NATIVE_TOKEN_ADDRESS) {
            TransferHelper.safeTransferETH(PROTOCOL_FEE_RECIPIENT, amt);
        } else {
            TransferHelper.safeTransfer(token, PROTOCOL_FEE_RECIPIENT, amt);
        }
    }

    function _slashRule1(bytes32 swapID, SwapData calldata s, address boltRelayerAddr)
        internal returns (uint, address)
    {
        require(
            s.route.dst == CURRENT_NETWORK,
            "SR1 fulfill dstNetwork invalid"
        );
        require(computeSwapID(s) == swapID, "invalid swap hash");
        FulfillData memory f = fulfills[swapID];
        SwapData memory swapState = swaps[swapID];
        require(
            swapState.status == Status.INVALID && f.boltOperator == address(0),
            "SR1 fulfill exists"
        );

        // TODO: advance swap status

        return (s.crossAmount, s.dstMsg.tokenIn);
    }

    function _slashRule2(bytes32 swapID, SwapData calldata s, address boltOperator, address boltRelayerAddr)
        internal returns (uint, address)
    {
        require(
            s.route.src == CURRENT_NETWORK,
            "SR2 fulfill srcNetwork invalid"
        );
        FulfillData memory f = fulfills[swapID];
        require(boltOperator != f.boltOperator, "SR2-OP");

        // TODO: advance swap status

        return (getLockAmount(s.crossAmount), s.srcMsg.tokenOut);
    }
}
