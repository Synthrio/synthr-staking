// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Faucet is Ownable{
    
    IERC20 public SYNTH;

    uint256 public faucetAmount = 10000 * 1e18;

    mapping (address => uint256) public claimedAmount;

    event Claimed(address indexed user, uint256 amount);
    event RecoveredSynth(address indexed owner, uint256 amount);
    event LogUpdateSynth(address indexed owner, address indexed synth);
    event LogUpdateFaucetAmount(address indexed owner, uint256 amount);
    event LowBalance(address lastUser,uint256 amount);
 
    constructor(address _owner, address _synth) Ownable(_owner) {
        SYNTH = IERC20(_synth);
    }

    function setSynthToken(address _synth) external onlyOwner {
        SYNTH = IERC20(_synth);

        emit LogUpdateSynth(msg.sender, _synth);
    }

    function setFaucetAmount(uint256 _newFaucetAmount) external onlyOwner {
        faucetAmount = _newFaucetAmount;

        emit LogUpdateFaucetAmount(msg.sender, _newFaucetAmount);
    }

    function claim(uint256 _amount) external {
        require(_amount + claimedAmount[msg.sender] <= faucetAmount, "Faucet:  amount greater than faucet amount");

        claimedAmount[msg.sender] += _amount;

        SYNTH.transfer(msg.sender, _amount);

        uint256 balanceOfContract = SYNTH.balanceOf(address(this));

        if (balanceOfContract <= faucetAmount * 2) {
            emit LowBalance(msg.sender, balanceOfContract);
        }

        emit Claimed(msg.sender, _amount);
    }

    function recoverSynth(uint256 _amount) external onlyOwner {
        SYNTH.transfer(msg.sender, _amount);

        emit RecoveredSynth(msg.sender, _amount);
    }
}
