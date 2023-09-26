// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

interface IGaugeController {
    function updataReward(uint256 index, uint256 amount, address user, bool increase) external;
    function decreaseRewardAndClaim(uint256 index, uint256 amount, address user) external;
}