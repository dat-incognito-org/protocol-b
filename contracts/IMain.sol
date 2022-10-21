// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol"; // for test fixtures
import "./MainStructs.sol";

interface IMain {
    function stake(
        MainStructs.Route[] memory routes,
        uint[] memory amount,
        address token
    ) external payable;

    function unstake(
        MainStructs.Route memory r,
        uint amount,
        address token
    ) external;

    function swap(
        uint amount,
        address boltRelayer,
        MainStructs.Route memory route,
        MainStructs.ExecutableMessage calldata srcMsg,
        MainStructs.ExecutableMessage calldata dstMsg
    ) external payable;

    function fulfill(MainStructs.SwapData calldata s, address boltOperator)
        external
        payable;

    function relay(
        bytes32 swapID,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external;

    function relayReturn(
        bytes32 swapID,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external;

    function slash(
        MainStructs.SlashRules rule,
        MainStructs.SwapData calldata s,
        address boltOperator,
        address boltRelayerAddr,
        bytes calldata signature
    ) external;

    function getAvailableRelayers(
        MainStructs.Route memory route,
        uint amount,
        address token
    ) external view returns (address[] memory);

    event Stake(
        address boltRelayer,
        uint[] routes,
        uint[] amount,
        address token
    );
    event Unstake(
        address boltRelayer,
        uint route,
        uint amount,
        address token,
        uint unlockTime
    );
    event Swap(
        address requester,
        address boltRelayer,
        uint route,
        bytes32 swapID
    );
    event Fulfill(
        address boltOperator,
        address boltRelayer,
        uint route,
        bytes32 swapID
    );
    event Lock(
        MainStructs.LockTypes lockType,
        uint amount,
        uint nonce,
        uint routeID,
        address token,
        address depositor,
        address receiver,
        bytes32 swapID
    );
    event Slash(
        MainStructs.SlashRules rule,
        uint amount,
        address token,
        address boltRelayerAddress,
        bytes32 swapID
    );
}
