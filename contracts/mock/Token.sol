// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock SYNTH", "SYNTH") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
