// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMain.sol";
import "./Parameters.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
// import "hardhat/console.sol";

/// @title Main logic contract for Bolt Protocol
contract Main is IMain, MainStructs {
    using Counters for Counters.Counter;

    uint public constant MAX_RELAYERS_LEN = 100;
    Networks public immutable CURRENT_NETWORK;
    address public constant NATIVE_TOKEN_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public immutable NATIVE_WRAPPED_TOKEN;
    Parameters public immutable params; 

    mapping (address => BoltRelayer) public boltRelayers;
    address[] public boltRelayerAddresses;
    Counters.Counter private swapCounter;
    mapping (bytes32 => SwapData) public swaps;

    constructor(address _wrapped, Networks _net, address _params) {
        NATIVE_WRAPPED_TOKEN = _wrapped;
        CURRENT_NETWORK = _net;
        params = Parameters(_params);
    }

    /// @notice Any relayer can add stake to take swap requests & earn fees;
    /// @notice the stake is bound to one route, which consist of source & destination networks (stake amounts must be identical)
    /// @param routes Routes to stake funds to e.g. [(ETH, PLG), (ETH, AVAX)]
    /// @param amounts The amount to stake for each route
    /// @param token The token to stake (zero for native coin)
    function stake(Route[] memory routes, uint[] memory amounts, address token) validRoutes(routes) external payable {
        uint totalAmount = 0;
        BoltRelayer storage r = boltRelayers[msg.sender];
        for (uint i = 0; i < routes.length; i++) {
            MultiTokenStakedFunds storage msf = boltRelayers[msg.sender].stakeMap[routeId(routes[i])];
            msf.stake[token].amount += amounts[i];         
            totalAmount += amounts[i];
        }
        if (token == NATIVE_TOKEN_ADDRESS) {
            require(totalAmount == msg.value, "stake native amount invalid");    
        } else {
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), totalAmount);
        }
        if (r.unstakeEnableBlock == 0) {
            // new relayer
            r.unstakeEnableBlock = block.number + params.durationToFirstUnstake();
            boltRelayerAddresses.push(msg.sender);
        }
        
        emit Stake(msg.sender, routes, amounts, token);
    }

    function unstake(Route memory route, uint amount, address token) external {
        BoltRelayer storage r = boltRelayers[msg.sender];
        StakedFunds memory sf = _getStakedFunds(msg.sender, route, token);
        require(block.number >= r.unstakeEnableBlock, "first unstake time not met");
        require(sf.amount > 0, "unstake zero"); 

        uint newLockedTotal = amount;
        for (uint i = 0; i < sf.locked.length; i++) {
            newLockedTotal += sf.locked[i].amount;
        }
        require(newLockedTotal < sf.amount, "unstake: not enough funds");

        uint unlockTime = _lockStake(msg.sender, route, token, amount, bytes32(0), StakeLockTypes.UNSTAKE);
        emit Unstake(msg.sender, route, amount, token, unlockTime);
    }

    function _getStakedFunds(address relayerAddr, Route memory route, address token) internal view returns (StakedFunds memory) {
        BoltRelayer storage r = boltRelayers[relayerAddr];
        return r.stakeMap[routeId(route)].stake[token];
    }

    function routeId(Route memory r) public pure returns (uint) {
        return uint(r.src) * 256 + uint(r.dst);
    }

    modifier validRoutes(Route[] memory rs) {
        for (uint i = 0; i < rs.length; i++) {
            require(rs[i].src != rs[i].dst, "ROUTE invalid");
            require(rs[i].src == CURRENT_NETWORK || rs[i].dst == CURRENT_NETWORK, "route must contain current net");
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

    function swap(uint amount, address boltRelayerAddr, Route memory route, ExecutableMessage calldata srcMsg, ExecutableMessage calldata dstMsg) external payable {
        (address returnToken, uint returnAmt) = _executeSrcMsg(amount, srcMsg);
        require(returnToken == srcMsg.tokenOut, "swap srcMsg tokenOut mismatch");

        uint availableStake = getAvailableStake(boltRelayerAddr, route, srcMsg.tokenOut);
        (uint[] memory fee, uint crossAmount) = getSwapFees(returnAmt);
        uint lockAmount = getLockAmount(crossAmount);
        require(availableStake >= lockAmount, "swap: relayer insufficient stake");

        swapCounter.increment();
        // store new swap data
        SwapData memory newSwapData = SwapData(swapCounter.current(), amount, crossAmount, boltRelayerAddr, route, srcMsg, dstMsg, Status.WAITING);
        bytes32 h = computeSwapID(newSwapData);
        _lockStake(boltRelayerAddr, route, returnToken, lockAmount, h, StakeLockTypes.SWAP_LOCK);
        swaps[h] = newSwapData;
    }

    function computeSwapID(SwapData memory s) public pure returns (bytes32) {
        bytes memory content = abi.encode(s); // TODO: non-EVM-specific marshalling
        return keccak256(content);
    }

    function _lockStake(address _raddr, Route memory route, address token, uint amount, bytes32 h, StakeLockTypes ltype) internal returns (uint unlockTime) {
        if (ltype == StakeLockTypes.UNSTAKE) {
            unlockTime = block.number + params.durationToUnstake();
        } else if (ltype == StakeLockTypes.SWAP_LOCK) {
            unlockTime = block.number + params.lockDuration();
        }
        LockedFunds memory newLock = LockedFunds(amount, unlockTime, h, ltype);

        BoltRelayer storage r = boltRelayers[_raddr];
        r.stakeMap[routeId(route)].stake[token].locked.push(newLock);
        return unlockTime;
    }

    function _executeSrcMsg(uint amount, ExecutableMessage calldata srcMsg) internal returns (address, uint) {
        if (srcMsg.callData.length == 0) {
            // blank msg
            require(srcMsg.tokenIn == srcMsg.tokenOut && srcMsg.callAddress == address(0), "srcMsg (blank) invalid");
            if (srcMsg.tokenIn == NATIVE_TOKEN_ADDRESS) {
                require(amount == msg.value, "swap native amount invalid");    
            } else {
                TransferHelper.safeTransferFrom(srcMsg.tokenIn, msg.sender, address(this), amount);
            }
            return (srcMsg.tokenIn, amount);
        }
        // TODO
        return (srcMsg.tokenIn, amount);
    }

    function _executeDstMsg(uint crossAmount, ExecutableMessage calldata dstMsg) internal returns (address, uint) {
        if (dstMsg.callData.length == 0) {
            // blank msg
            require(dstMsg.tokenIn == dstMsg.tokenOut, "dstMsg (blank) invalid");
            if (dstMsg.tokenIn == NATIVE_TOKEN_ADDRESS) {
                TransferHelper.safeTransferETH(dstMsg.callAddress, crossAmount);
            } else {
                TransferHelper.safeTransfer(dstMsg.tokenIn, dstMsg.callAddress, crossAmount);
            }
            return (dstMsg.tokenIn, crossAmount);
        }
        // TODO
        return (dstMsg.tokenIn, crossAmount);
    }

    // TBD: internal
    function getSwapFees(uint srcAmount) public view returns (uint[] memory, uint) {
        require(uint(BoltActors.RELAYER) == 0, "fee params invalid");
        uint bp = params.BASE_PRECISION();
        uint feeActorsLen = uint(BoltActors.OPERATOR) + 1;
        uint[] memory fees = new uint[](feeActorsLen);
        uint crossAmount = srcAmount;
        for (uint i = 0; i < feeActorsLen; i++) {
            uint fee = crossAmount * params.feePercent(i) / bp;
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
        return crossAmount * (bp + x1) / bp;
    }

    function getAvailableStake(address relayerAddr, Route memory route, address token) public view returns (uint) {
        StakedFunds memory sf = _getStakedFunds(relayerAddr, route, token);
        return getAvailableStake(sf);
    }

    function getAvailableStake(StakedFunds memory sf) public pure returns (uint) {
        uint result = sf.amount;
        for (uint i = 0; i < sf.locked.length; i++) {
            result -= sf.locked[i].amount; // must not underflow
        }
        return result;
    }

    function getAvailableRelayers(Route memory route, uint amount, address token) public view returns (address[] memory) {
        address[] memory result = new address[](MAX_RELAYERS_LEN);
        uint cur = 0;
        for (uint i = 0; i < boltRelayerAddresses.length; i++) {
            uint stk = getAvailableStake(boltRelayerAddresses[i], route, token);
            if (stk >= amount) {
                result[cur] = boltRelayerAddresses[i];
                cur++;
            }
        }
        return result;
    }

    // TODO
    
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata boltOperatorAddr) external payable {}
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable {}
    function relayReturn(bytes32 swapDataHash, address boltOperator, bytes calldata signature) external {}
    function slash(bytes[2] calldata signatures, SwapTranscript calldata ts) external {}
    
}


