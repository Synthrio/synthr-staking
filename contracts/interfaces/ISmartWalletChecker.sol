// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface ISmartWalletChecker {
    function check(address user) external returns (bool);
}
