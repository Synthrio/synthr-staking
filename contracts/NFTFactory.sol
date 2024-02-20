// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "./SynthrNFT.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SynthrNFTFactory is Ownable2Step {
    mapping(string => address) public NFTs;

    event NFTCreated(address _creator, string _name, address _nft);

    function createNFT(string memory name_, string memory symbol_, address _nftOwner)
        public
        onlyOwner
        returns (address)
    {
        SynthrNFT nft = new SynthrNFT(name_, symbol_);
        NFTs[name_] = address(nft);
        nft.transferOwnership(owner()); // transfer ownership of NFT from Factory (address(this)) -> owner of factory
        emit NFTCreated(address(this), name_, address(nft));
        return address(nft);
    }
}
