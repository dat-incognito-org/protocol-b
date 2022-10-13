// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // for test fixtures

interface IMain {
    function stake(MainStructs.Route[] memory routes, uint[] memory amount, address token) external payable;
    function unstake(MainStructs.Route memory r, uint amount, address token) external;
    function swap(uint amount, address relayer, MainStructs.Route memory route, MainStructs.ExecutableMessage calldata srcMsg, MainStructs.ExecutableMessage calldata dstMsg) external payable;
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata boltOperatorAddr) external payable;
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable;
    function relayReturn(bytes32 swapDataHash, address boltOperator, bytes calldata signature) external;
    function slash(bytes[2] calldata signatures, MainStructs.SwapTranscript calldata ts) external;
    function getAvailableRelayers(MainStructs.Route memory route, uint amount, address token) external view returns (address[] memory);

    event Stake(address relayer, MainStructs.Route[] routes, uint[] amount, address token);
    event Unstake(address relayer, MainStructs.Route route, uint amount, address token, uint unlockTime);

}

abstract contract MainStructs {
    enum Networks {
        ETH,
        PLG,
        BSC,
        AVAX
    }

    enum NetworkRoles {
        SOURCE,
        DESTINATION
    }

    enum BoltActors {
        RELAYER,
        OPERATOR,
        WATCHER
    }

    enum SlashRules {
        RULE1,
        RULE2,
        RULE3
    }

    enum Status {
        INVALID,
        WAITING,
        FULFILLED,
        COMPLETED,
        REFUNDED
    }

    enum StakeLockTypes {
        SWAP_LOCK,
        UNSTAKE
    }

    struct Route {
        Networks src;
        Networks dst;
    }

    // TODO: byte marshaling
    // TODO: move to executor
    struct ExecutableMessage {
        uint routeId;
        address tokenIn;
        address callAddress;
        bytes callData; // includes amount, receiver etc.
        address tokenOut;
    }

    struct SwapData {
        uint nonce;
        uint srcAmount;
        uint crossAmount; // fees are functions of crossAmount & srcAmount
        address boltRelayerAddr;
        Route route;
        ExecutableMessage srcMsg;
        ExecutableMessage dstMsg;
        Status status;
    }

    struct SwapTranscript {
        SwapData swapData;
        address operator;
    }

    struct LockedFunds {
        uint amount;
        uint until;
        bytes32 h; // the swap ID this is locked for
        StakeLockTypes lockType;
    }

    struct StakedFunds {
        uint amount;
        LockedFunds[] locked;
    }

    struct MultiTokenStakedFunds {
        mapping (address => StakedFunds) stake;
    }

    struct BoltRelayer {
        mapping (uint => MultiTokenStakedFunds) stakeMap;
        uint unstakeEnableBlock;
        bytes[] extraAddresses; // placeholder
    }
}