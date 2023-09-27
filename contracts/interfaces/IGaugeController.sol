// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IGaugeController {
    function updateReward(
        address pool,
        address user,
        uint256 amount,
        bool increase
    ) external;

    function decreaseRewardAndClaim(
        address pool,
        uint256 amount,
        address user
    ) external;
}
