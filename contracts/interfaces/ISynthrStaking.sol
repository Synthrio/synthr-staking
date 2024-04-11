// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

interface ISynthrStaking {
    struct UserInfo {
        uint256 amount;
        uint256 lockType;
        uint256 unlockEnd;
        int256 rewardDebt;
    }

    function userInfo(address user) external view returns(UserInfo memory);
}