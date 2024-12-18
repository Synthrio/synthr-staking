// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;
// todo verify dex lp farming of erc1155 in arbitrum goerli

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ILBPair.sol";
import "./BaseDexLpFarming.sol";
import {PackedUint128Math} from "../libraries/PackedUint128Math.sol";
import {BinHelper} from "../libraries/BinHelper.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarmingERC1155 is Ownable2Step, BaseDexLpFarming {
    using SafeERC20 for IERC20;
    using PackedUint128Math for bytes32;
    using PackedUint128Math for uint128;
    using BinHelper for bytes32;

    ILBPair public LBPair;

    /// @notice liquidity amount of user corresponds to token id in pool.
    mapping(address => mapping(uint256 => uint256)) public liqudityOfId;
    /// @notice liquidity amount of tokenX user deposited in LBPair pool corresponds to Token Id.
    mapping(address => mapping(uint256 => uint256)) public liquidityAmountX;

    event LBPairUpdated(ILBPair indexed newLBPair);

    /// @param _rewardToken The REWARD token contract address.
    constructor(IERC20 _rewardToken, ILBPair _LBPair) BaseDexLpFarming(_rewardToken) {
        LBPair = _LBPair;
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _user Address of user.
    /// @return _pending REWARD_TOKEN reward for a given user.
    function pendingReward(address _user) external view returns (uint256 _pending) {
        (, uint256 _lpSupply) = LBPair.getReserves();
        _pending = _pendingReward(_user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @return _pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory _pool) {
        (, uint256 lpSupply) = LBPair.getReserves();
        _pool = _updatePool(lpSupply);
    }

    /// @notice Set the new Lbpair, can only be called by owner.
    /// @param _lbPair The new Lbpair
    function setLBPair(ILBPair _lbPair) external onlyOwner {
        LBPair = _lbPair;
        emit LBPairUpdated(_lbPair);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenIds LP token ids to deposit.
    /// @param _tokenAmounts LP token amount to deposit.
    function depositBatch(uint256[] memory _tokenIds, uint256[] memory _tokenAmounts) external {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        // Effects
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            require(_tokenAmounts[i] != 0, "Farming: zero token amount");
            (uint256 _liquidityX, uint256 _liquidity) = _getLiquidityAmount(_tokenIds[i], msg.sender);
            liquidityAmountX[msg.sender][_tokenIds[i]] = _liquidityX;
            bool neg;
            uint256 _liquidityDifference;

            if (_liquidity > liqudityOfId[msg.sender][_tokenIds[i]]) {
                _liquidityDifference = _liquidity - liqudityOfId[msg.sender][_tokenIds[i]];
            } else {
                _liquidityDifference = liqudityOfId[msg.sender][_tokenIds[i]] - _liquidity;
                neg = true;
            }

            liqudityOfId[msg.sender][_tokenIds[i]] = _liquidity;
            _depositLiquidity(_tokenIds[i], _tokenAmounts[i], _liquidityDifference, _pool.accRewardPerShare, _user, neg);
        }

        // Interactions
        LBPair.batchTransferFrom(msg.sender, address(this), _tokenIds, _tokenAmounts);

        emit Deposit(msg.sender, _tokenIds);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param _tokenIds LP token ids to withdraw.
    function withdrawBatch(uint256[] memory _tokenIds) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        PoolInfo memory _pool = updatePool();
        uint256[] memory _tokensAmount = new uint256[](_tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _amount = userTokenAmount[msg.sender][_tokenIds[i]];
            require(_amount != 0, "Farming: no token available");
            _tokensAmount[i] = _amount;

            liqudityOfId[msg.sender][_tokenIds[i]] = 0;
            (, uint256 _liquidity) = _getLiquidityAmount(_tokenIds[i], msg.sender);

            _withdrawLiquidity(_tokenIds[i], _liquidity, _pool.accRewardPerShare, _user);
        }

        LBPair.batchTransferFrom(address(this), msg.sender, _tokenIds, _tokensAmount);

        emit Withdraw(msg.sender, _tokenIds);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(address to) external {
        PoolInfo memory pool = updatePool();
        uint256 _pendingRewardAmount = _harvest(pool.accRewardPerShare, to);
        emit Harvest(msg.sender, _pendingRewardAmount);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `to`.
    /// @param _tokenIds LP token ids to withdraw.
    function withdrawAndHarvest(uint256[] memory _tokenIds, address _to) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        PoolInfo memory pool = updatePool();

        uint256[] memory _tokensAmount = new uint256[](_tokenIds.length);
        uint256 _totalPendingAmount;
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _amount = userTokenAmount[msg.sender][_tokenIds[i]];
            require(_amount != 0, "Farming: token not deposited");
            _tokensAmount[i] = _amount;

            liqudityOfId[msg.sender][_tokenIds[i]] = 0;
            (, uint256 _liquidity) = _getLiquidityAmount(_tokenIds[i], msg.sender);

            _totalPendingAmount += _withdrawAndHarvest(_tokenIds[i], _liquidity, pool.accRewardPerShare, _user, _to);
        }
        // Interactions
        LBPair.batchTransferFrom(address(this), _to, _tokenIds, _tokensAmount);
        emit WithdrawAndHarvest(msg.sender, _tokenIds, _totalPendingAmount);
    }

    function getLiquidityIds(uint256[] calldata _tokenIds) external view returns (uint256[] memory tokenIds) {
        uint256 liquidity;
        uint256 liquidityX;
        uint256 idIndex;
        tokenIds = new uint256[](_tokenIds.length);
        for (uint256 index; index < _tokenIds.length; ++index) {
            (liquidityX, liquidity) = _getLiquidity(_tokenIds[index]);
            if (liquidity != 0 || liquidityX != 0) {
                tokenIds[idIndex] = _tokenIds[index];
                ++idIndex;
            }
        }
    }

    function _getLiquidity(uint256 _tokenId) internal view returns (uint256, uint256) {
        return LBPair.getBin(uint24(_tokenId));
    }

    function _getLiquidityAmount(uint256 _id, address _user)
        internal
        view
        returns (uint256 _liquidityX, uint256 _liquidityY)
    {
        (uint128 reserveX, uint128 reserveY) = LBPair.getBin(uint24(_id));
        uint256 amountInBin = LBPair.balanceOf(_user, _id);
        bytes32 binReserves = reserveX.encode(reserveY);
        uint256 supply = LBPair.totalSupply(_id);

        bytes32 amountsOutFromBin = binReserves.getAmountOutOfBin(amountInBin, supply);
        (_liquidityX, _liquidityY) = amountsOutFromBin.decode();
    }
}
