// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

// import "hardhat/console.sol";

contract Main {
    mapping (address => Relayer) public relayers;

    event Stake(uint amount);
    event Unstake(uint amount);

    struct Relayer {
        address[] to;
        address[] from; // TODO
        uint stakedAmount;
        uint lockedAmount; // TODO: add time as list
        bytes[] extraAddresses; // placeholder
    }

    constructor() {
    }

    function stake() external payable {
        Relayer storage r = relayers[msg.sender];
        r.stakedAmount = msg.value;

        emit Stake(msg.value);
    }

    function unstake() external {
        require(relayers[msg.sender].stakedAmount >= relayers[msg.sender].lockedAmount, "invalid amounts");
        uint unstakeAmt = relayers[msg.sender].stakedAmount - relayers[msg.sender].lockedAmount;
        require(unstakeAmt > 0, "zero stake");

        emit Unstake(unstakeAmt);
        (bool success, ) = address(msg.sender).call{value: unstakeAmt}("");
        require(success, "unstake failed");
    }
}
