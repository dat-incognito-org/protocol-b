// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMain.sol";
import "./Parameters.sol";
import "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
// import "hardhat/console.sol";

/// @title Main logic contract for Bolt Protocol
contract Main is IMain, MainStructs {
    Networks public immutable CURRENT_NETWORK;
    address public constant NATIVE_TOKEN_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public immutable NATIVE_WRAPPED_TOKEN;
    Parameters public immutable params; 

    mapping (address => BoltRelayer) public boltRelayers;
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
            MultiTokenStakedFunds storage sf = _stakedFundsStorage(msg.sender, routes[i]);
            sf.stake[token].amount += amounts[i];         
            totalAmount += amounts[i];
        }
        if (token == NATIVE_TOKEN_ADDRESS) {
            require(totalAmount == msg.value, "stake ETH: amount invalid");    
        } else {
            TransferHelper.safeTransferFrom(token, msg.sender, address(this), totalAmount);
        }
        if (r.unstakeEnableBlock == 0) {
            // new relayer
            r.unstakeEnableBlock = block.number + params.durationToFirstUnstake();
        }
        
        emit Stake(msg.sender, routes, amounts, token);
    }

    function unstake(Route memory r, uint amount, address token) external {
        MultiTokenStakedFunds storage sf = _stakedFundsStorage(msg.sender, r);
        require(sf.stake[token].amount > 0, "unstake zero"); 

        uint newLockedTotal = amount;
        for (uint i = 0; i < sf.stake[token].locked.length; i++) {
            newLockedTotal += sf.stake[token].locked[i].amount; // must not overflow
        }
        require(newLockedTotal < sf.stake[token].amount, "not enough funds to unstake");
        LockedFunds memory newLock = LockedFunds(amount, block.number + params.durationToUnstake(), bytes32(0), StakeLockTypes.UNSTAKE);
        sf.stake[token].locked.push(newLock);

        // emit Unstake(msg.sender, newLockedTotal, token, sf.networks);
        // sf.stakedAmount -= newLockedTotal;
    }

    function _stakedFundsStorage(address relayerAddr, Route memory route) internal view returns (MultiTokenStakedFunds storage sf) {
        BoltRelayer storage r = boltRelayers[relayerAddr];
        return r.stakeMap[routeId(route)];
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

    // TODO
    function swap(uint amount, address boltRelayer, Networks dstNetwork, ExecutableMessage calldata srcMsg, ExecutableMessage calldata dstMsg) external payable {}
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata boltOperatorAddr) external payable {}
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable {}
    function relayReturn(bytes32 swapDataHash, address boltOperator, bytes calldata signature) external {}
    function slash(bytes[2] calldata signatures, SwapTranscript calldata ts) external {}
    function getAvailableRelayers(uint amount, address token) public view returns (address[] memory r) {
        return r;
    }
}


