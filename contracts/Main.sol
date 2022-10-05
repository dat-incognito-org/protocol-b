// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMain.sol";
// import "hardhat/console.sol";

contract Main is IMain, MainStructs {
    mapping (address => Relayer) public relayers;

    constructor() {
    }

    function stake(NetworkRoles nwrole, uint amount, Networks[] calldata networks) external payable {
        StakedFunds storage sf = _stakedFundsStorage(nwrole);
        require(amount == msg.value, "stake ETH: amount invalid");
        require(sf.networks.length == 0 && sf.stakedAmount == 0, "add new only"); // TODO: add to existing
        sf.networks = networks;
        sf.stakedAmount = msg.value; // TODO: multiple tokens

        emit Stake(msg.sender, amount, networks);
    }

    function unstake(NetworkRoles nwrole) external {
        StakedFunds storage sf = _stakedFundsStorage(nwrole);
        require(sf.stakedAmount >= sf.lockedAmount, "invalid amounts");
        uint unstakeAmt = sf.stakedAmount - sf.lockedAmount;
        require(unstakeAmt > 0, "zero stake");

        (bool success, ) = address(msg.sender).call{value: unstakeAmt}("");
        require(success, "unstake failed");
        emit Unstake(msg.sender, unstakeAmt, sf.networks);
        sf.stakedAmount -= unstakeAmt;
    }

    function _stakedFundsStorage(NetworkRoles nwrole) internal view returns (StakedFunds storage sf) {
        Relayer storage r = relayers[msg.sender];
        if (nwrole == NetworkRoles.SOURCE) {
            sf = r.to;
        } else {
            sf = r.from;
        }
        return sf;
    }

    // TODO
    function swap(uint amount, address relayer, MainStructs.Networks dstNetwork, MainStructs.ExecutableMessage calldata srcMsg, MainStructs.ExecutableMessage calldata dstMsg) external payable {}
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata operatorAddr) external payable {}
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable {}
    function relayReturn(bytes32 swapDataHash, address operator, bytes calldata signature) external {}
    function slash(bytes[2] calldata signatures, MainStructs.SwapTranscript calldata ts) external {}
}
