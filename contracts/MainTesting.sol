// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Main.sol";

contract MainTestDst is Main {
    constructor(
        address _wrapped,
        Networks _net,
        address _params
    ) Main(_wrapped, _net, _params) {}

    function newRoute(Networks src, Networks dst) public pure returns (Route memory) {
        return Route(src, dst);
    }
}
