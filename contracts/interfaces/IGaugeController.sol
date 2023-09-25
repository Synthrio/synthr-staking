// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IGaugeController {
    function increaseReward(uint256 index, uint256 amount, address user) external;
    function decreaseReward(uint256 index, uint256 amount, address user) external;
    function decreaseRewardAndClaim(uint256 index, uint256 amount, address user) external;
}