// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IMain {
    function stake() external payable;
    function unstake() external;
}