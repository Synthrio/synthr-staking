// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

contract SynthToken is ERC20Burnable, Pausable, Ownable2Step {
    constructor(address _owner, address _reciever, uint256 _totalSupply) ERC20("SYNTHR", "SYNTH") Ownable(_owner) {
        require(_totalSupply > 0, "Synthr: amount must be non zero");
        _mint(_reciever, _totalSupply);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _update(address from, address to, uint256 value) internal virtual override whenNotPaused {
        super._update(from, to, value);
    }
}
