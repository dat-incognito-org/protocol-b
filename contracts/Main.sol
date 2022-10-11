// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IMain.sol";
// import "hardhat/console.sol";

/// @title Main logic contract for Bolt Protocol
contract Main is IMain, MainStructs {
    Networks public immutable CURRENT_NETWORK;
    address public constant NATIVE_TOKEN_ADDRESS = 0x0000000000000000000000000000000000000000;
    address public immutable NATIVE_WRAPPED_TOKEN;

    mapping (address => Relayer) public boltRelayers;
    mapping (bytes32 => SwapData) public swaps;

    constructor(address _wrapped, address _net) {
        NATIVE_WRAPPED_TOKEN = _wrapped;
        CURRENT_NETWORK = _net;
    }

    /// @notice Any relayer can add stake to take swap requests & earn fees;
    /// @notice the stake is bound to one route, which consist of source & destination networks (stake amounts must be identical)
    /// @param routes Routes to stake funds to e.g. [(ETH, PLG), (ETH, AVAX)]
    /// @param amounts The amount to stake for each route
    /// @param token The token to stake (zero for native coin)
    function stake(Route[] routes, uint[] amounts, address token) external payable {
        StakedFunds storage sf = _stakedFundsStorage(nwrole);
        require(amount == msg.value, "stake ETH: amount invalid");
        require(sf.networks.length == 0 && sf.stakedAmount == 0, "add new only"); // TODO: add to existing
        sf.networks = networks;
        sf.stakedAmount = msg.value; // TODO: multiple tokens

        emit Stake(msg.sender, amount, token, networks);
    }

    function unstake(Route r, address token) external {
        StakedFunds storage sf = _stakedFundsStorage(nwrole);
        require(sf.stakedAmount >= sf.lockedAmount, "invalid amounts");
        uint unstakeAmt = sf.stakedAmount - sf.lockedAmount;
        require(unstakeAmt > 0, "zero stake");

        (bool success, ) = address(msg.sender).call{value: unstakeAmt}("");
        require(success, "unstake failed");
        emit Unstake(msg.sender, unstakeAmt, token, sf.networks);
        sf.stakedAmount -= unstakeAmt;
    }

    function _stakedFundsStorage(NetworkRoles nwrole) internal view returns (StakedFunds storage sf) {
        Relayer storage r = boltRelayers[msg.sender];
        if (nwrole == NetworkRoles.SOURCE) {
            sf = r.to;
        } else {
            sf = r.from;
        }
        return sf;
    }

    function routeId(Route r) public pure returns (uint) {
        return r.src * 256 + r.dst;
    }

    modifier validRoute(Route r) {
        require(r.src != r.dst, "ROUTE invalid");
        require(r.src == CURRENT_NETWORK || r.dst == CURRENT_NETWORK, "route must contain current net");
        _;
    }

    modifier validSrc(Route r) {
        require(r.src != r.dst, "ROUTE invalid");
        require(r.src == CURRENT_NETWORK, "SRC invalid");
        _;
    }

    modifier validDst(Route r) {
        require(r.src != r.dst, "ROUTE invalid");
        require(r.dst == CURRENT_NETWORK, "DST invalid");
        _;
    }

    // TODO
    function swap(uint amount, address boltRelayer, Networks dstNetwork, ExecutableMessage calldata srcMsg, ExecutableMessage calldata dstMsg) external payable {}
    function fulfill(MainStructs.SwapData calldata swapData, bytes calldata boltOperatorAddr) external payable {}
    function relay(MainStructs.SwapTranscript calldata swapData, bytes calldata signature, bool serving) external payable {}
    function relayReturn(bytes32 swapDataHash, address boltOperator, bytes calldata signature) external {}
    function slash(bytes[2] calldata signatures, SwapTranscript calldata ts) external {}
    function getAvailableRelayers(uint amount, address token) public view returns (Relayer[] memory r) {
        return r;
    }
}

contract BoltParameters is Ownable {
    uint public constant BASE_PRECISION = 10000; // "percent" variables below are expressed in precision e.g. 2500 means 25%

    uint[] public watcherRewardPercent; // reward percent varies per slash rule; there are 3 rules initially

    uint[] public burnedCollateralPercent;

    uint[] public minFee; // minFee is defined for each actor role
    uint[] public feePercent; // minFee is defined for each actor role

    // durations are in blocks (vary by network)
    uint public durationToUnstake; // from stake accepted -> unstake enabled
    uint public lockDuration; // time to lock a relayer's stake after a swap



    constructor(uint[] memory _wreward, uint[] memory _burn, uint[] _minFee, uint[] _feePercent) {
        watcherRewardPercent = _wreward;
        burnedCollateralPercent = _burn;
        minFee = _minFee;
        feePercent = _feePercent;
    }

    // setters
    function setWatcherRewardPercent(uint8 i, uint v) external onlyOwner {
        require(i <= watcherRewardPercent.length, "watcherRewardPercent invalid index");
        watcherRewardPercent[i] = v;
    }

    function setAllWatcherRewardPercent(uint[] lst) external onlyOwner {
        watcherRewardPercent = lst;
    }
}
