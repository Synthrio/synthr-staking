// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title SynthrNFT
 * @dev A contract for creating and managing Synthr NFTs (Non-Fungible Tokens).
 */
contract SynthrNFT is ERC721, Ownable2Step {

    struct UserInfo {
        uint256 stakedAmount;
        uint256 lockEnd;
    }

    uint256 public tokenIdCount;
    mapping(uint256 tokenId => UserInfo) public userData;

    event BatchMinted(address[] to, uint256 lastTokenIdMinted);

    /**
     * @dev Constructor to initialize the SynthrNFT contract.
     * @param name_ The name of the NFT contract.
     * @param symbol_ The symbol of the NFT contract.
     * @param owner_ The initial owner of the contract.
     */
    constructor(string memory name_, string memory symbol_, address owner_) ERC721(name_, symbol_) Ownable(owner_) {}

    function getuserData(uint256 _tokenId) external view returns(uint256, uint256) {
        return (userData[_tokenId].stakedAmount, userData[_tokenId].lockEnd);
    }

    /**
     * @dev Safely mints a single token and assigns it to the specified address.
     * @param to The address to which the token will be minted.
     * @param lpAmount The amount of LP (Liquidity Provider (Synthr token)) tokens staked when obtaining this NFT.
     * @return tokenId The ID of the minted token.
     * @notice Only owner of this contract is allowed to mint tokens
     */
    function safeMint(address to, uint256 lpAmount, uint256 endBlockNumber) external onlyOwner returns (uint256 tokenId) {
        tokenId = ++tokenIdCount;
        _safeMint(to, tokenId);
        userData[tokenId].stakedAmount = lpAmount;
        userData[tokenId].lockEnd = endBlockNumber;
    }

    /**
     * @dev Safely mints multiple tokens and assigns them to specified addresses.
     * @param _to An array of addresses to which tokens will be minted.
     * @param _lpAmount An array of LP amounts corresponding to each address.
     * @notice Only owner of this contract is allowed to mint tokens
     */
    function safeMintBatch(address[] calldata _to, uint256[] calldata _lpAmount, uint256[] calldata _endBlockNumber) external onlyOwner {
        require(_to.length > 1, "Synthr NFT: Mint more than one");
        uint256 tokenId = tokenIdCount;
        for (uint256 i = 0; i < _to.length; i++) {
            _safeMint(_to[i], ++tokenId);
            userData[tokenId].stakedAmount = _lpAmount[i];
            userData[tokenId].lockEnd = _endBlockNumber[i];
        }
        tokenIdCount = tokenId;

        emit BatchMinted(_to, tokenIdCount);
    }
}
