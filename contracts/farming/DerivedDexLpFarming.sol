// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ITokenTracker.sol";
import "./BaseDexLpFarming.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarming is Ownable2Step, BaseDexLpFarming {
    using SafeERC20 for IERC20;

    ITokenTracker public tokenTracker;

    address public liquidityPool;
    address public nativeToken;

    /// @param _rewardToken The REWARD token contract address.
    constructor(
        IERC20 _rewardToken,
        ITokenTracker _tokenTracker,
        address _liquidityPool,
        address _nativeToken
    ) BaseDexLpFarming(_rewardToken) {
        tokenTracker = _tokenTracker;
        liquidityPool = _liquidityPool;
        nativeToken = _nativeToken;
    }

    function getIndex(
        uint256 _pid,
        uint256 _tokenId
    ) external view returns (uint256) {
        uint256[] memory tokenIds = userToken[_pid][msg.sender];
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (tokenIds[i] == _tokenId) {
                return i;
            }
        }
        revert("token id not present");
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending) {
        uint256 _lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        pending = _pendingReward(_pid, _user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        uint256 lpSupply = IERC20(nativeToken).balanceOf(liquidityPool);
        pool = _updatePool(pid, lpSupply);
    }

    /// @notice Deposit LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenId LP token id to deposit.
    function deposit(uint256 pid, uint256 tokenId) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        _deposit(pid, tokenId, user, pool.accRewardPerShare);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIds LP token ids to deposit.
    function depositBatch(uint256 pid, uint256[] memory tokenIds) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        // Effects
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _deposit(pid, tokenIds[i], user, pool.accRewardPerShare);
        }
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIdsIndex LP token ids to withdraw.
    function withdrawBatch(uint256 pid, uint256[] memory tokenIdsIndex) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        for (uint256 i = 0; i < tokenIdsIndex.length; i++) {
            _withdraw(pid, tokenIdsIndex[i], user, pool.accRewardPerShare);
        }
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIdIndex LP token id index to withdraw.
    function withdraw(uint256 pid, uint256 tokenIdIndex) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        _withdraw(pid, tokenIdIndex, user, pool.accRewardPerShare);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(uint256 pid, address to) external {
        PoolInfo memory pool = updatePool(pid);
        _harvest(pid, pool.accRewardPerShare, to);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIdIndex LP token id index to withdraw.
    function withdrawAndHarvest(
        uint256 pid,
        uint256 tokenIdIndex,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory _user = userInfo[pid][msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");
        uint256[] memory _userTokenIds = userToken[pid][msg.sender];

        uint256 _tokenId = _userTokenIds[tokenIdIndex];
        _userTokenIds[tokenIdIndex] = _userTokenIds[_userTokenIds.length - 1];

        (, , , , , , , uint256 liquidity, , , , ) = tokenTracker.positions(
            _tokenId
        );
        uint256 userAmount = _user.amount;
        _user.amount -= liquidity;
        if (_user.amount != 0) {
            userToken[pid][msg.sender] = _userTokenIds;
            userToken[pid][msg.sender].pop();
        } else {
            delete userToken[pid][msg.sender];
        }

        // Effects
        _withdrawAndHarvest(
            pid,
            pool.accRewardPerShare,
            _tokenId,
            liquidity,
            to,
            userAmount,
            _user
        );

        // Interactions
        tokenTracker.transferFrom(address(this), to, _tokenId);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        uint256[] memory _userTokenIds = userToken[pid][msg.sender];

        // Note: transfer can fail or succeed if `amount` is zero.
        for (uint256 i = 0; i < _userTokenIds.length; i++)
            tokenTracker.transferFrom(address(this), to, _userTokenIds[i]);

        _emergencyWithdraw(pid, to);
    }

    function _deposit(
        uint _pid,
        uint256 _tokenId,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {
        (, , , , , , , uint256 liquidity, , , , ) = tokenTracker.positions(
            _tokenId
        );
        require(liquidity != 0, "Farming: no liquidity");
        _depositLiquidity(_pid, _tokenId, _user, _accRewardPerShare, liquidity);

        // Interactions
        tokenTracker.transferFrom(msg.sender, address(this), _tokenId);
        emit Deposit(msg.sender, _pid, _tokenId);
    }

    function _withdraw(
        uint _pid,
        uint256 _tokenIdIndex,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {
        uint256[] memory _userTokenIds = userToken[_pid][msg.sender];

        uint256 _tokenId = _userTokenIds[_tokenIdIndex];

        _userTokenIds[_tokenIdIndex] = _userTokenIds[_userTokenIds.length - 1];

        (, , , , , , , uint256 liquidity, , , , ) = tokenTracker.positions(
            _tokenId
        );

        _user.amount -= liquidity;

        if (_user.amount != 0) {
            userToken[_pid][msg.sender] = _userTokenIds;
            userToken[_pid][msg.sender].pop();
        } else {
            delete userToken[_pid][msg.sender];
        }

        _withdrawLiquidity(
            _pid,
            _tokenId,
            _user,
            _accRewardPerShare,
            liquidity
        );

        // Interactions
        tokenTracker.transferFrom(address(this), msg.sender, _tokenId);

        emit Withdraw(msg.sender, _pid, _tokenId);
    }
}
