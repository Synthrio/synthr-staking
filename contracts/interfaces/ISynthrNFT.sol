// SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.8.24;

interface ISynthrNFT {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function lockAmount(uint256 _tokenId) external view returns (uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeMint(address to) external returns (uint256);
    function safeMintBatch(address[] calldata _to) external;
}
