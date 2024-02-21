// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./SynthrNFT.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

contract SynthrNFTFactory is Ownable2Step {
    address internal implementation;
    mapping(string => address) public NFTs;

    event NFTCreated(address creator, string name, address nft);

    constructor(address owner_) Ownable(owner_) {}

    function setImplementation() external onlyOwner returns (SynthrNFT _implementation) {
        _implementation = new SynthrNFT();
        _implementation.initialize("Template-Synthr-NFT", "tNFT", msg.sender);
        implementation = address(_implementation);
    }

    function createNFT(string memory name_, string memory symbol_, address nftOwner_)
        public
        onlyOwner
        returns (address nft)
    {
        require(implementation != address(0), "Factory: Template Implementation not yet set");
        bytes32 salt = keccak256(abi.encodePacked(name_, symbol_, nftOwner_));
        nft = Clones.cloneDeterministic(implementation, salt);
        SynthrNFT(nft).initialize(name_, symbol_, nftOwner_);

        NFTs[name_] = nft;
        emit NFTCreated(address(this), name_, address(nft));
    }
}
