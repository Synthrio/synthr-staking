// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../../interfaces/ILBPair.sol";
import "./BaseDexLpFarmingLightChain.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarmingERC1155LightChain is BaseDexLpFarmingLightChain {
    using SafeERC20 for IERC20;

    ILBPair public LBPair;

    /// @notice liquidity amount of user corresponds to token id in pool.
    mapping(address => mapping(uint256 => uint256)) public liqudityOfId;

    /// @param _lzPoint LayerZero EndPoint contract address.
    constructor(
        ILBPair _LBPair,
        address _lzPoint
    ) BaseDexLpFarmingLightChain(_lzPoint) {
        LBPair = _LBPair;
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _user Address of user.
    /// @return _pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        address _user
    ) external view returns (uint256 _pending) {
        (, uint256 _lpSupply) = LBPair.getReserve();
        _pending = _pendingReward(_user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @return _pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory _pool) {
        (, uint256 lpSupply) = LBPair.getReserve();
        _pool = _updatePool(lpSupply);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenIds LP token ids to deposit.
    /// @param _tokenAmounts LP token amount to deposit.
    function depositBatch(
        uint256[] memory _tokenIds,
        uint256[] memory _tokenAmounts
    ) external {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        // Effects
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _liquidity = _getLiquidity(_tokenIds[i]);

            int256 _liquidityDifference = int256(_liquidity) -
                int256(liqudityOfId[msg.sender][_tokenIds[i]]);
            liqudityOfId[msg.sender][_tokenIds[i]] = _liquidity;
            _depositLiquidity(
                _tokenIds[i],
                _tokenAmounts[i],
                _liquidityDifference,
                _pool.accRewardPerShare,
                _user
            );
        }

        // Interactions
        LBPair.batchTransferFrom(
            msg.sender,
            address(this),
            _tokenIds,
            _tokenAmounts
        );

        emit DepositBatch(msg.sender, _tokenIds);
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

            uint256 _liquidity = _getLiquidity(_tokenIds[i]);
            liqudityOfId[msg.sender][_tokenIds[i]] = 0;

            _withdrawLiquidity(
                _tokenIds[i],
                _liquidity,
                _pool.accRewardPerShare,
                _user
            );
        }

        LBPair.batchTransferFrom(
            address(this),
            msg.sender,
            _tokenIds,
            _tokensAmount
        );

        emit WithdrawBatch(msg.sender, _tokenIds);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(address to) external payable {
        PoolInfo memory pool = updatePool();
        _harvest(pool.accRewardPerShare, to);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `to`.
    /// @param _tokenIds LP token ids to withdraw.
    function withdrawAndHarvest(
        uint256[] memory _tokenIds,
        address _to
    ) external payable {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        PoolInfo memory pool = updatePool();

        uint256[] memory _tokensAmount = new uint256[](_tokenIds.length);

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            uint256 _amount = userTokenAmount[msg.sender][_tokenIds[i]];
            require(_amount != 0, "Farming: token not deposited");
            _tokensAmount[i] = _amount;

            uint256 _liquidity = _getLiquidity(_tokenIds[i]);
            liqudityOfId[msg.sender][_tokenIds[i]] = 0;

            _withdrawAndHarvest(
                _tokenIds[i],
                _liquidity,
                pool.accRewardPerShare,
                _user,
                _to
            );
        }
        // Interactions
        LBPair.batchTransferFrom(address(this), _to, _tokenIds, _tokensAmount);
    }

    function _getLiquidity(uint256 _tokenId) internal view returns (uint256) {
        (, uint256 _liquidity) = LBPair.getBin(uint24(_tokenId));
        return _liquidity;
    }
}
