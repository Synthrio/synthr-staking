// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SynthrNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    event TransferBatch(address indexed operator, address[] to, uint256[] ids);
    event MintBatch(address indexed operator, address[] to);

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    function safeMint(address to) public onlyOwner {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function safeMintBatch(address[] memory _to) public onlyOwner {
        require(_to.length > 1, "Synthr NFT: Batch minting valid for minting more than one");
        address operator = _msgSender();
        for (uint256 i = 0; i < _to.length; i++) {
            safeMint(_to[i]);
        }

        emit MintBatch(operator, _to);
    }

    function safeTransferBatch(address[] memory _to, uint256[] memory _ids) public onlyOwner {
        require(_to.length > 1, "Synthr NFT: Batch transfer valid for more than one transfer");
        require(_ids.length == _to.length, "SynthrNFT: ids and to length mismatch");
        address operator = _msgSender();
        for (uint256 i = 0; i < _to.length; i++) {
            _safeTransfer(operator, _to[i], _ids[i], "");
        }

        emit TransferBatch(operator, _to, _ids);
    }
}
