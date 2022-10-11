// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IMain {
    function stake(MainStructs.NetworkRoles nwrole, uint amount, address token, MainStructs.Networks[] calldata networks) external payable;
    function unstake(MainStructs.NetworkRoles nwrole, address token) external;
    function swap(uint amount, address relayer, MainStructs.Networks dstNetwork, MainStructs.ExecutableMessage calldata srcMsg, MainStructs.ExecutableMessage calldata dstMsg) external payable;
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata boltOperatorAddr) external payable;
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable;
    function relayReturn(bytes32 swapDataHash, address boltOperator, bytes calldata signature) external;
    function slash(bytes[2] calldata signatures, MainStructs.SwapTranscript calldata ts) external;
    function getEligibleRelayers(uint amount, address token) external view returns (MainStructs.BoltRelayer[] memory);

    event Stake(address relayer, uint amount, address token, MainStructs.Networks[] networks);
    event Unstake(address relayer, uint amount, address token, MainStructs.Networks[] networks);

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
        RULE3,
    }

    enum Status {
        INVALID,
        WAITING,
        FULFILLED,
        COMPLETED,
        REFUNDED
    }

    struct Route {
        Networks src;
        Networks dst;
    }

    struct ExecutableMessage {
        address tokenIn;
        address callAddress;
        bytes callData; // includes amount, receiver etc.
        address tokenOut;
    }

    struct SwapData {
        uint srcAmount;
        uint crossAmount; // fees are functions of crossAmount & srcAmount
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
    }

    struct StakedFunds {
        uint stakedAmount;
        LockedFunds[] locked;
        Networks[] networks;
    }

    struct BoltRelayer {
        mapping (uint => StakedFunds) stake;
        bytes[] extraAddresses; // placeholder
    }
}