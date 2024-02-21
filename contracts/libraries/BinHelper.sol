// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import {PackedUint128Math} from "./PackedUint128Math.sol";
import {Uint256x256Math} from "./Uint256x256Math.sol";

/**
 * @title Liquidity Book Bin Helper Library
 * @author Trader Joe
 * @notice This library contains functions to help interaction with bins.
 */
library BinHelper {
    using Uint256x256Math for uint256;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;

    error BinHelper__CompositionFactorFlawed(uint24 id);
    error BinHelper__LiquidityOverflow();

    /**
     * @dev Returns the amount of tokens that will be received when burning the given amount of liquidity
     * @param binReserves The reserves of the bin
     * @param amountToBurn The amount of liquidity to burn
     * @param totalSupply The total supply of the liquidity book
     * @return amountsOut The encoded amount of tokens that will be received
     */
    function getAmountOutOfBin(bytes32 binReserves, uint256 amountToBurn, uint256 totalSupply)
        internal
        pure
        returns (bytes32 amountsOut)
    {
        (uint128 binReserveX, uint128 binReserveY) = binReserves.decode();

        uint128 amountXOutFromBin;
        uint128 amountYOutFromBin;

        if (binReserveX > 0) {
            amountXOutFromBin = uint128(amountToBurn.mulDivRoundDown(binReserveX, totalSupply));
        }

        if (binReserveY > 0) {
            amountYOutFromBin = uint128(amountToBurn.mulDivRoundDown(binReserveY, totalSupply));
        }

        amountsOut = amountXOutFromBin.encode(amountYOutFromBin);
    }
}
