// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ILBPair {
    function batchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external;

    function getBin(uint24 id) external view returns (uint128, uint128);

    function getReserve() external view returns (uint128, uint128);
}
