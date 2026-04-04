// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}
interface IFeed {
    function latestAnswer() external view returns (int256);
    function decimals() external view returns (uint8);
}

contract AUM0 {
    error WeightsMustSum();
    error UnknownAccount();
    error DriftNotImproved(uint256 before_, uint256 after_);
    error BadFill(uint256 got, uint256 expected, uint256 bandBps);
    error StockToStockForbidden();
    error BelowThreshold();

    struct Target {
        uint32 minDriftBps;
        uint32 bandBps;
        uint64 bountyQuote;
        uint16[] weightsBps;
    }

    IERC20[] public assets; // 0 = quote
    IFeed[]  public feeds;
    address public router;
    mapping(address => Target) internal targets;
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    constructor(IERC20[] memory _assets, IFeed[] memory _feeds, address _router) {
        require(_assets.length == _feeds.length, "length");
        assets = _assets; feeds = _feeds; router = _router;
    }

    function setTarget(uint16[] calldata bps, uint32 minDrift, uint32 band, uint64 bounty) external {
        if (bps.length != assets.length) revert WeightsMustSum();
        uint256 s;
        for (uint256 i; i < bps.length; ++i) s += bps[i];
        if (s != 10000) revert WeightsMustSum();
        targets[msg.sender] = Target(minDrift, band, bounty, bps);
    }

    function deposit(uint256 i, uint256 amt) external {
        require(i < assets.length, "asset");
        assets[i].transferFrom(msg.sender, address(this), amt);
        balanceOf[msg.sender][i] += amt;
    }

    function withdraw(uint256 i, uint256 amt) external {
        balanceOf[msg.sender][i] -= amt;
        assets[i].transfer(msg.sender, amt);
    }

    // drift and rebalance in progress
}
