// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IERC20 {
    function transferFrom(address, address, uint256) external returns (bool);
    function transfer(address, uint256) external returns (bool);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
}

contract AUM0 {
    // state and setTarget in progress
    struct Target {
        uint32 minDriftBps;
        uint32 bandBps;
        uint64 bountyQuote;
        uint16[] weightsBps;
    }
    mapping(address => Target) internal targets;
    mapping(address => mapping(uint256 => uint256)) public balanceOf;
}
