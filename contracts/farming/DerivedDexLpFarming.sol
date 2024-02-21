// SPDX-License-Identifier: UNLICENSED
pragma solidity = 0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ITokenTracker.sol";
import "./BaseDexLpFarming.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarming is Ownable2Step, BaseDexLpFarming {
    using SafeERC20 for IERC20;

    address public liquidityPool;
    address public nativeToken;

    ITokenTracker public tokenTracker;

    event TokenTrackerUpdated(ITokenTracker indexed newTokenTracker);
    event LiquidityPoolUpdated(address indexed newLiquidityPool);
    event NativeTokenUpdated(address indexed newNativeToken);

    /// @param _rewardToken The REWARD token contract address.
    constructor(IERC20 _rewardToken, ITokenTracker _tokenTracker, address _liquidityPool, address _nativeToken)
        BaseDexLpFarming(_rewardToken)
    {
        tokenTracker = _tokenTracker;
        liquidityPool = _liquidityPool;
        nativeToken = _nativeToken;
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _user Address of user.
    /// @return _pending REWARD_TOKEN reward for a given user.
    function pendingReward(address _user) external view returns (uint256 _pending) {
        uint256 _lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        _pending = _pendingReward(_user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @return _pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory _pool) {
        uint256 lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        _pool = _updatePool(lpSupply);
    }

    /// @notice Set the new TokenTracker, can only be called by owner.
    /// @param _tokenTracker The new TokenTracker.
    function setTokenTracker(ITokenTracker _tokenTracker) external onlyOwner {
        tokenTracker = _tokenTracker;
        emit TokenTrackerUpdated(_tokenTracker);
    }

    /// @notice Set the new TokenTracker, can only be called by owner.
    /// @param _nativeToken The new TokenTracker.
    function setNativeToken(address _nativeToken) external onlyOwner {
        nativeToken = _nativeToken;
        emit NativeTokenUpdated(_nativeToken);
    }

    /// @notice Set the new TokenTracker, can only be called by owner.
    /// @param _liquidityPool The new TokenTracker.
    function setLiquidityPool(address _liquidityPool) external onlyOwner {
        liquidityPool = _liquidityPool;
        emit LiquidityPoolUpdated(_liquidityPool);
    }

    /// @notice Deposit LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenId LP token id to deposit.
    function deposit(uint256 _tokenId) external {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;
        _deposit(_tokenId, _pool.accRewardPerShare, _user);
        emit Deposit(msg.sender, _tokenIds);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenIds LP token ids to deposit.
    function depositBatch(uint256[] memory _tokenIds) external {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        // Effects
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _deposit(_tokenIds[i], _pool.accRewardPerShare, _user);
        }

        emit Deposit(msg.sender, _tokenIds);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param _tokenId LP token id to withdraw.
    function withdraw(uint256 _tokenId) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");
        PoolInfo memory _pool = updatePool();

        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;
        _withdraw(_tokenId, _pool.accRewardPerShare, _user);
        emit Withdraw(msg.sender, _tokenIds);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param _tokenIds LP token ids to withdraw.
    function withdrawBatch(uint256[] memory _tokenIds) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        PoolInfo memory _pool = updatePool();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _withdraw(_tokenIds[i], _pool.accRewardPerShare, _user);
        }
        emit Withdraw(msg.sender, _tokenIds);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param _to Receiver of REWARD_TOKEN rewards.
    function harvest(address _to) external {
        PoolInfo memory pool = updatePool();
        uint256 _pendingRewardAmount = _harvest(pool.accRewardPerShare, _to);
        emit Harvest(msg.sender, _pendingRewardAmount);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `_to`.
    /// @param _tokenId LP token id index to withdraw.
    function withdrawAndHarvest(uint256 _tokenId, address _to) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");
        require(userTokenAmount[msg.sender][_tokenId] != 0, "Farming: can not withdraw");

        PoolInfo memory _pool = updatePool();

        uint256 _liquidity = _getLiquidity(_tokenId);

        // Effects
        uint256 _pendingAmount = _withdrawAndHarvest(_tokenId, _liquidity, _pool.accRewardPerShare, _user, _to);

        // Interactions
        tokenTracker.transferFrom(address(this), _to, _tokenId);

        uint256[] memory _tokenIds = new uint256[](1);
        _tokenIds[0] = _tokenId;
        emit WithdrawAndHarvest(msg.sender, _tokenIds, _pendingAmount);
    }

    function _deposit(uint256 _tokenId, uint256 _accRewardPerShare, UserInfo memory _user) internal {
        uint256 _liquidity = _getLiquidity(_tokenId);

        _depositLiquidity(_tokenId, 1, _liquidity, _accRewardPerShare, _user, false);

        // Interactions
        tokenTracker.transferFrom(msg.sender, address(this), _tokenId);
    }

    function _withdraw(uint256 _tokenId, uint256 _accRewardPerShare, UserInfo memory _user) internal {
        require(userTokenAmount[msg.sender][_tokenId] != 0, "Farming: can not withdraw");
        uint256 _liquidity = _getLiquidity(_tokenId);

        _withdrawLiquidity(_tokenId, _liquidity, _accRewardPerShare, _user);

        // Interactions
        tokenTracker.transferFrom(address(this), msg.sender, _tokenId);
    }

    function _getLiquidity(uint256 _tokenId) internal view returns (uint256) {
        (,,,,,,, uint256 _liquidity,,,,) = tokenTracker.positions(_tokenId);

        return _liquidity;
    }
}
