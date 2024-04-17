// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

contract SynthToken is ERC20, ERC20Burnable, ERC20Pausable, Ownable2Step {
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

    // The following function are overrides required by Solidity.
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Pausable)
    {
        super._update(from, to, value);
    }
}
