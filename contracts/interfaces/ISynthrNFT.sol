// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

interface ISynthrNFT {

    function transferFrom(address from, address to, uint256 tokenId) external;
    function getuserData(uint256 _tokenId) external view returns (uint256, uint256);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function safeMint(address to, uint256 lpAmount) external returns (uint256);
    function safeMintBatch(address[] calldata _to, uint256[] calldata _lpAmount) external;
}
