// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface INftToken {
    function transferFrom(address _from, address _to, uint256 _amount) external;
    function lockAmount(uint256 _tokenId) external view returns (uint256);
    function totalLockAmount() external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}
