// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IParameters {
    function lockDuration() external view returns (uint);
    function durationToUnstake() external view returns (uint);
    function durationToFirstUnstake() external view returns (uint);
    function BASE_PRECISION() external view returns (uint);
    function minFee(uint) external view returns (uint);
    function feePercent(uint) external view returns (uint);
    function overCollateralPercent(uint) external view returns (uint);
}