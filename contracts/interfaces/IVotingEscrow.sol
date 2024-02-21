// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IVotingEscrow {
    function token() external view returns (address);

    function balanceOf(address _user, uint256 _t) external view returns (uint256);
}
