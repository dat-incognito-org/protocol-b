// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IMain {
    function stake(MainStructs.NetworkRoles nwrole, uint amount, MainStructs.Networks[] calldata networks) external payable;
    function unstake(MainStructs.NetworkRoles nwrole) external;
    function swap(uint amount, address relayer, MainStructs.Networks dstNetwork, MainStructs.ExecutableMessage calldata srcMsg, MainStructs.ExecutableMessage calldata dstMsg) external payable;
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata operatorAddr) external payable;
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable;
    function relayReturn(bytes32 swapDataHash, address operator, bytes calldata signature) external;
    function slash(bytes[2] calldata signatures, MainStructs.SwapTranscript calldata ts) external;

    event Stake(address relayer, uint amount, MainStructs.Networks[] networks);
    event Unstake(address relayer, uint amount, MainStructs.Networks[] networks);

}

abstract contract MainStructs {
    enum Networks {
        ETH,
        PLG,
        BSC
    }

    enum NetworkRoles {
        SOURCE,
        DESTINATION
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
        MainStructs.Networks srcNetwork;
        MainStructs.Networks dstNetwork;
        MainStructs.ExecutableMessage srcMsg;
        MainStructs.ExecutableMessage dstMsg;
    }

    // struct FulfillData {}

    struct SwapTranscript {
        SwapData swapData;
        address operator;
        // bytes32 relayerRoot;
    }

    struct StakedFunds {
        uint stakedAmount;
        uint lockedAmount; // TODO: add time as list
        Networks[] networks;
    }

    struct Relayer {
        StakedFunds to;
        StakedFunds from;
        bytes[] extraAddresses; // placeholder
    }

}