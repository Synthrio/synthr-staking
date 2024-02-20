// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../libraries/BinHelper.sol";
import "../libraries/PackedUint128Math.sol";

contract LibTest {
    function encodeTest(uint128 x1, uint128 x2) external pure returns(bytes32){
        return PackedUint128Math.encode(x1, x2);
    }

    function decodeTest(bytes32 x) external pure returns(uint128, uint128){
        return PackedUint128Math.decode(x);
    }

    function getAmount(bytes32 binReserves, uint256 amountToBurn, uint256 totalSupply) external pure returns(bytes32) {
        return BinHelper.getAmountOutOfBin(binReserves, amountToBurn, totalSupply);
    }
}