// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IParameters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Parameters is Ownable, IParameters {
    uint public constant BASE_PRECISION = 10000; // "percent" variables below are expressed in precision e.g. 2500 means 25%

    uint[] public watcherRewardPercent; // reward percent varies per slash rule; there are 3 rules initially

    uint[] public overCollateralPercent;

    uint[] public minFee; // minFee is defined for each actor role
    uint[] public feePercent; // feePercent is defined for each actor role

    // durations are in blocks (vary by network)
    uint public durationToUnstake; // from unstake accepted -> funds returned
    uint public durationToFirstUnstake; // from stake accepted -> unstake enabled
    uint public lockDuration; // time to lock a relayer's stake after a swap
    
    // will remove
    uint public swapExpiryDuration; 
    uint public fulfillExpiryDuration;

    constructor(
        uint[] memory _wreward,
        uint[] memory _oc,
        uint[] memory _minFee,
        uint[] memory _feePercent,
        uint[5] memory durations   
    ) {
        watcherRewardPercent = _wreward;
        overCollateralPercent = _oc;
        minFee = _minFee;
        feePercent = _feePercent;
        durationToUnstake = durations[0];
        durationToFirstUnstake = durations[1];
        lockDuration = durations[2];
        swapExpiryDuration = durations[3];
        fulfillExpiryDuration = durations[4];
    }

    // setters
    function setWatcherRewardPercent(uint8 i, uint v) external onlyOwner {
        require(
            i <= watcherRewardPercent.length,
            "watcherRewardPercent invalid index"
        );
        watcherRewardPercent[i] = v;
    }

    function setAllWatcherRewardPercent(uint[] memory lst) external onlyOwner {
        watcherRewardPercent = lst;
    }
}
