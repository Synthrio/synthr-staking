// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract SynthrNFT is ERC721Upgradeable, OwnableUpgradeable {
    uint256 private _nextTokenId;
    uint256 public totalLockAmount;
    mapping(address user => uint256 stakedAmount) public lockAmount;

    event TransferBatch(address indexed operator, address[] to, uint256[] ids);
    event MintBatch();

    function setLockAmount(address user_, uint256 amount_) external onlyOwner {
        require(user_ != address(0), "Synthr NFT: Address must be non zero");
        require(amount_ > 0, "Synthr NFT: Lock amount should be more than zero");
        lockAmount[user_] = amount_;
        totalLockAmount += amount_;
    }

    function initialize(string memory name_, string memory symbol_, address owner_) public initializer {
        __ERC721_init(name_, symbol_);
        __Ownable_init(owner_);
    }

    function safeMint(address to) public onlyOwner returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function safeMintBatch(address[] calldata _to) public onlyOwner {
        require(_to.length > 1, "Synthr NFT: Batch minting valid for minting more than one");
        uint256 tokenId;
        for (uint256 i = 0; i < _to.length; i++) {
            tokenId = safeMint(_to[i]);
        }

        emit MintBatch();
    }

    function safeTransferBatch(address[] calldata _to, uint256[] calldata _ids) public onlyOwner {
        require(_to.length > 1, "Synthr NFT: Batch transfer valid for more than one transfer");
        require(_ids.length == _to.length, "SynthrNFT: ids and to length mismatch");
        address operator = _msgSender();
        for (uint256 i = 0; i < _to.length; i++) {
            _safeTransfer(operator, _to[i], _ids[i], "");
        }

        emit TransferBatch(operator, _to, _ids);
    }
}
