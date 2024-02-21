// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SynthrNFT is ERC721, Ownable2Step {
    uint256 public tokenIdCount;
    mapping(uint256 tokenId => uint256 stakedAmount) public lockAmount;

    event BatchMinted(address[] to);

    constructor(string memory name_, string memory symbol_, address owner_) ERC721(name_, symbol_) Ownable(owner_) {}

    function safeMint(address to, uint256 lpAmount) external onlyOwner returns (uint256 tokenId) {
        tokenId = tokenIdCount++;
        _safeMint(to, tokenId);
        lockAmount[tokenId] = lpAmount;
    }

    function safeMintBatch(address[] calldata _to, uint256[] calldata _lpAmount) external onlyOwner {
        require(_to.length > 1, "Synthr NFT: Mint more than one");
        uint256 tokenId = tokenIdCount;
        for (uint256 i = 0; i < _to.length; i++) {
            _safeMint(_to[i], tokenId++);
            lockAmount[tokenId] = _lpAmount[i];
        }
        tokenIdCount = tokenId;

        emit BatchMinted(_to);
    }
}
