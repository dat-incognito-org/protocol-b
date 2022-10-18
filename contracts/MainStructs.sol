// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

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
        PROTOCOL,
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
        // uint routeId;
        address tokenIn;
        address callAddress;
        bytes callData; // includes amount, receiver etc.
        address tokenOut;
    }

    struct SwapData {
        address requester;
        address boltRelayerAddr;
        Route route;
        uint nonce;
        uint crossAmount;
        uint totalFees;
        ExecutableMessage srcMsg;
        ExecutableMessage dstMsg;
        uint startBlock;
        Status status;
    }

    struct FulfillData {
        SwapData swapData;
        uint startBlock;
        address boltOperator;
    }

    struct RelayData {
        bytes32 swapID;
        address boltOperator;
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
        mapping(address => StakedFunds) stake;
    }

    struct BoltRelayer {
        mapping(uint => MultiTokenStakedFunds) stakeMap;
        uint unstakeEnableBlock;
        bytes[] extraAddresses; // placeholder
    }
}