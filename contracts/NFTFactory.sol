// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./SynthrNFT.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract SynthrNFTFactory is Ownable2Step {
    uint256 public nftCount;
    address internal implementation;
    mapping(string => address) public NFTs;

    event NFTCreated(address creator, string name, address nft);

    constructor(address owner_) Ownable(owner_) {}

    function createNFT(string memory name_, string memory symbol_, address owner_)
        public
        onlyOwner
        returns (address nft)
    {
        if (nftCount == 0) {
            SynthrNFT _implementation = new SynthrNFT();
            _implementation.initialize(name_, symbol_, owner_);
            implementation = address(_implementation);
            nftCount++;
            nft = address(_implementation);
        } else if (nftCount > 0) {
            bytes32 salt = keccak256(abi.encodePacked(name_, symbol_, owner_));
            nft = Clones.cloneDeterministic(implementation, salt);
            SynthrNFT(nft).initialize(name_, symbol_, owner_);
            nftCount++;
        }
        NFTs[name_] = nft;
        emit NFTCreated(address(this), name_, address(nft));
    }
}
