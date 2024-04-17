// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract Synthr is ERC20Burnable, Pausable, Ownable2Step {
    constructor(address _owner, address _recipient, uint256 _totalSupply) ERC20("SYNTHR", "SYNTH") Ownable(_owner) {
        require(_totalSupply > 0, "Synthr: amount must be non zero");
        _mint(_recipient, _totalSupply);
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
