// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;


import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CrossClaim is NonblockingLzApp, ERC20 {
    uint16 public constant SEND_MESSAGE = 1;
    uint16 public srcChain;

    event ReceivePacket(address indexed account, bytes path, uint16 indexed packetType, uint16 indexed srcChainId, uint64 nonce);

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) ERC20("MoCK token sample", "mock"){}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        uint16 packetType;
        assembly {
            packetType := mload(add(_payload, 32))
        }

        srcChain = _srcChainId;

        address account;
        uint amount;

        require(packetType == SEND_MESSAGE, "Claim: invalid message");
        (, account, amount) = abi.decode(_payload, (uint16, address, uint));
        
        _mint(account, amount);

        {
            bytes memory path = trustedRemoteLookup[_srcChainId];
            emit ReceivePacket(account, path, packetType, _srcChainId, _nonce);
        }
    }

}