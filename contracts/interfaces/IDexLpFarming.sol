// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IDexLpFarming {
    function isTokenDeposited(
        address _user,
        uint256 _tokenId
    ) external view returns (bool);
}