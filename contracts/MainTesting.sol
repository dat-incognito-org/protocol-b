// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Main.sol";

contract MainTestDst is Main {
    constructor(
        Networks _net,
        address _params,
        address _feeRecipient
    ) Main(_net, _params, _feeRecipient) {}
}
