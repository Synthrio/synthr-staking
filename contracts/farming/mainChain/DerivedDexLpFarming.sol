// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "../../interfaces/ITokenTracker.sol";
import "./BaseDexLpFarming.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarming is BaseDexLpFarming {
    using SafeERC20 for IERC20;

    address public liquidityPool;
    address public nativeToken;

    ITokenTracker public tokenTracker;

    /// @param _lzPoint LayerZero EndPoint contract address.
    constructor(
        IERC20 _rewardToken,
        ITokenTracker _tokenTracker,
        address _liquidityPool,
        address _nativeToken,
        address _lzPoint

    ) BaseDexLpFarming(_rewardToken,_lzPoint) {
        tokenTracker = _tokenTracker;
        liquidityPool = _liquidityPool;
        nativeToken = _nativeToken;
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _user Address of user.
    /// @return _pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        address _user
    ) external view returns (uint256 _pending) {
        uint256 _lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        _pending = _pendingReward(_user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @return _pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory _pool) {
        uint256 lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        _pool = _updatePool(lpSupply);
    }

    /// @notice Deposit LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenId LP token id to deposit.
    function deposit(uint256 _tokenId) public {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        _deposit(_tokenId, _pool.accRewardPerShare,_user);
        emit Deposit(msg.sender, _tokenId);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param _tokenIds LP token ids to deposit.
    function depositBatch(uint256[] memory _tokenIds) public {
        PoolInfo memory _pool = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        // Effects
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _deposit(_tokenIds[i], _pool.accRewardPerShare, _user);
        }
        emit DepositBatch(msg.sender, _tokenIds);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param _tokenId LP token id to withdraw.
    function withdraw(uint256 _tokenId) public {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");
        PoolInfo memory _pool = updatePool();

        _withdraw(_tokenId, _pool.accRewardPerShare, _user);
        emit Withdraw(msg.sender, _tokenId);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param _tokenIds LP token ids to withdraw.
    function withdrawBatch(uint256[] memory _tokenIds) public {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        PoolInfo memory _pool = updatePool();

        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _withdraw(_tokenIds[i], _pool.accRewardPerShare,_user);
        }

        emit WithdrawBatch(msg.sender, _tokenIds);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param _to Receiver of REWARD_TOKEN rewards.
    function harvest(address _to) external {
        PoolInfo memory pool = updatePool();
        _harvest(pool.accRewardPerShare, _to);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `_to`.
    /// @param _tokenId LP token id index to withdraw.
    function withdrawAndHarvest(
        uint256 _tokenId,
        address _to
    ) external {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");
        require(userTokenAmount[msg.sender][_tokenId] != 0, "Farming: can not withdraw");

        PoolInfo memory _pool = updatePool();

        uint256 _liquidity = _getLiquidity(_tokenId);

        // Effects
        _withdrawAndHarvest(
            _tokenId,
            _liquidity,
            _pool.accRewardPerShare,
            _user,
            _to
        );

        // Interactions
        tokenTracker.transferFrom(address(this), _to, _tokenId);
    }

    function _deposit(
        uint256 _tokenId,
        uint256 _accRewardPerShare,
        UserInfo memory _user
    ) internal {

        uint256 _liquidity = _getLiquidity(_tokenId);

        _depositLiquidity(_tokenId, 1, int256(_liquidity), _accRewardPerShare, _user);      // amount of token is one.

        // Interactions
        tokenTracker.transferFrom(msg.sender, address(this), _tokenId);
    }

    function _withdraw(
        uint256 _tokenId,
        uint256 _accRewardPerShare,
        UserInfo memory _user
    ) internal  {
        require(userTokenAmount[msg.sender][_tokenId] != 0, "Farming: can not withdraw");
        uint256 _liquidity = _getLiquidity(_tokenId);

        _withdrawLiquidity(
            _tokenId,
            _liquidity,
            _accRewardPerShare,
            _user
        );

        // Interactions
        tokenTracker.transferFrom(address(this), msg.sender, _tokenId);
    }

    function _getLiquidity(uint256 _tokenId) internal view returns(uint256) {
        
        (, , , , , , , uint256 _liquidity, , , , ) = tokenTracker.positions(
            _tokenId
        );

        return _liquidity;
    }
}
