// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SynthToken is ERC20, Ownable2Step {
    constructor(address _owner, address _reciever, uint256 _totalSupply) ERC20("SynthrToken ", "SYNTH") Ownable(_owner) {
        require(_totalSupply > 0, "Synthr: amount must be non zero");
        _mint(_reciever, _totalSupply);
    }

    function burn(address _to, uint256 _amount) public onlyOwner {
        _burn(_to, _amount);
    }
}
