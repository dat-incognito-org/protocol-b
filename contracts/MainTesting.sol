// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Main.sol";

contract MainTestDst is Main {
    constructor(
        Networks _net,
        address _params
    ) Main(_net, _params, NATIVE_TOKEN_ADDRESS) {}

    function newRoute(Networks src, Networks dst) public pure returns (Route memory) {
        return Route(src, dst);
    }
}
