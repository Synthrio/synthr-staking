// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

interface IVotingEscrow {
    struct LockedBalance {
        int128 amount;
        uint256 end;
    }
    
    function balanceOf(address addr) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function locked(address addr) external view returns (LockedBalance memory);
    function token() external view returns (address);
    function balanceOf(address _user, uint256 _t) external view returns (uint256);
    function lockedEnd(address _user) external view returns (uint256);
}
