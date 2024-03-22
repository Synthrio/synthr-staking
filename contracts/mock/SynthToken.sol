// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract SynthToken is ERC20, Ownable2Step {
    constructor(address _owner) ERC20("SynthrToken ", "SYNTH") Ownable(_owner) {}

    function mint(address _to, uint256 _amount) public onlyOwner {
        require(_amount > 0, "Synthr: amount must be non zero");
        _mint(_to, _amount);
    }

    function burn(address _to, uint256 _amount) public onlyOwner {
        _burn(_to, _amount);
    }
}
