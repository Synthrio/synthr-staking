// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {ERC721, ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title SynthrNFT
 * @dev A contract for creating and managing Synthr NFTs (Non-Fungible Tokens).
 */
contract SynthrNFT is ERC721URIStorage, Ownable2Step {
    uint256 public tokenIdCount;

    event BatchMinted(address[] to, uint256 lastTokenIdMinted);

    /**
     * @dev Constructor to initialize the SynthrNFT contract.
     * @param name_ The name of the NFT contract.
     * @param symbol_ The symbol of the NFT contract.
     * @param owner_ The initial owner of the contract.
     */
    constructor(string memory name_, string memory symbol_, address owner_) ERC721(name_, symbol_) Ownable(owner_) {}

    /**
     * @dev Safely mints a single token and assigns it to the specified address.
     * @param to The address to which the token will be minted.
     * @param tokenURI for storing and managing metadata URIs associated with NFTs
     * @return tokenId The ID of the minted token.
     * @notice Only owner of this contract is allowed to mint tokens
     */
    function safeMint(address to, string memory tokenURI) external onlyOwner returns (uint256 tokenId) {
        tokenId = ++tokenIdCount;
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
    }

    /**
     * @dev Safely mints multiple tokens and assigns them to specified addresses.
     * @param _to An array of addresses to which tokens will be minted.
     * @param _tokenURIs An array of URIs for storing and managing metadata URIs associated with NFTs
     * @notice Only owner of this contract is allowed to mint tokens
     */
    function safeMintBatch(address[] calldata _to, string[] calldata _tokenURIs) external onlyOwner {
        require(_to.length == _tokenURIs.length, "Synthr NFT: Invalid input length");
        require(_to.length > 0, "Synthr NFT: Empty input");
        uint256 tokenId = tokenIdCount;
        for (uint256 i = 0; i < _to.length; i++) {
            _safeMint(_to[i], ++tokenId);
            _setTokenURI(tokenId, _tokenURIs[i]);
        }
        tokenIdCount = tokenId;

        emit BatchMinted(_to, tokenIdCount);
    }
}
