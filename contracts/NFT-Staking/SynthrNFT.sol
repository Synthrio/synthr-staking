// SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SynthrNFT is ERC721, Ownable2Step {
    uint256 public tokenIdCount;
    mapping(uint256 tokenId => uint256 stakedAmount) public lockAmount;

    event BatchMinted();

    constructor(string memory name_, string memory symbol_, address owner_) ERC721(name_, symbol_) Ownable(owner_) {}

    function setLockAmount(uint256 tokenId_, uint256 amount_) external onlyOwner {
        require(tokenId_ != 0, "Synthr NFT: Token-ID must be non zero");
        require(amount_ > 0, "Synthr NFT: Amount must be non zero");
        lockAmount[tokenId_] = amount_;
    }

    function safeMint(address to) external onlyOwner returns (uint256 tokenId) {
        tokenId = tokenIdCount++;
        _safeMint(to, tokenId);
    }

    function safeMintBatch(address[] calldata _to) external onlyOwner {
        require(_to.length > 1, "Synthr NFT: Mint more than one");
        uint256 tokenId = tokenIdCount;
        for (uint256 i = 0; i < _to.length; i++) {
            _safeMint(_to[i], tokenId++);
        }
        tokenIdCount = tokenId;

        emit BatchMinted();
    }
}
