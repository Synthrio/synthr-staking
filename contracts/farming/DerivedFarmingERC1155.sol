// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ILBPair.sol";
import "./BaseDexLpFarming.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarmingERC1155 is Ownable2Step, BaseDexLpFarming {
    using SafeERC20 for IERC20;

    /// @notice token ids of user in pool.
    mapping(uint256 => mapping(address => uint256[])) public amountOfId;

    ILBPair public LBPair;

    /// @param _rewardToken The REWARD token contract address.
    constructor(
        IERC20 _rewardToken,
        ILBPair _LBPair
    ) BaseDexLpFarming(_rewardToken) {
        LBPair = _LBPair;
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending) {
        (, uint256 _lpSupply) = LBPair.getReserve();
        pending = _pendingReward(_pid, _user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        (, uint256 lpSupply) = LBPair.getReserve();
        pool = _updatePool(pid, lpSupply);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIds LP token ids to deposit.
    function depositBatch(
        uint256 pid,
        uint256[] memory tokenIds,
        uint256[] memory tokenAmounts
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        // Effects
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _deposit(
                pid,
                tokenIds[i],
                tokenAmounts[i],
                user,
                pool.accRewardPerShare
            );
        }
        // Interactions
        LBPair.batchTransferFrom(
            msg.sender,
            address(this),
            tokenIds,
            tokenAmounts
        );
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIdsIndex LP token ids indexes to withdraw.
    function withdrawBatch(uint256 pid, uint256[] memory tokenIdsIndex) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        uint256[] memory ids = new uint256[](tokenIdsIndex.length);
        uint256[] memory tokenAmount = new uint256[](tokenIdsIndex.length);

        uint256[] memory _userTokenIds = userToken[pid][msg.sender];
        uint256[] memory _tokenAmounts = amountOfId[pid][msg.sender];

        for (uint256 i = 0; i < tokenIdsIndex.length; i++) {
            uint256 _tokenId = _userTokenIds[tokenIdsIndex[i]];
            (, uint256 _liquidity) = LBPair.getBin(uint24(_tokenId));

            ids[i] = _userTokenIds[tokenIdsIndex[i]];
            tokenAmount[i] = _tokenAmounts[tokenIdsIndex[i]];

            _tokenAmounts[tokenIdsIndex[i]] = _tokenAmounts[
                _tokenAmounts.length - i - 1
            ];
            _userTokenIds[tokenIdsIndex[i]] = _userTokenIds[
                _userTokenIds.length - i - 1
            ];

            user.amount -= _liquidity;

            if (user.amount == 0) {
                delete userToken[pid][msg.sender];
                delete amountOfId[pid][msg.sender];
            }

            _withdrawLiquidity(
                pid,
                _tokenId,
                user,
                pool.accRewardPerShare,
                _liquidity
            );

            emit Withdraw(msg.sender, pid, _tokenId);
        }
        if (userToken[pid][msg.sender].length != 0) {
            userToken[pid][msg.sender] = _userTokenIds;
            amountOfId[pid][msg.sender] = _tokenAmounts;
            for (uint256 i = 0; i < tokenIdsIndex.length; i++) {
                userToken[pid][msg.sender].pop();
                amountOfId[pid][msg.sender].pop();
            }
        }

        LBPair.batchTransferFrom(address(this), msg.sender, ids, tokenAmount);
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
    /// @param tokenIdsIndex LP token id indexes to withdraw.
    function withdrawAndHarvest(
        uint256 pid,
        uint256[] memory tokenIdsIndex,
        address to
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory _user = userInfo[pid][msg.sender];
        require(_user.amount != 0, "Farming: can not withdraw");

        uint256[] memory _userTokenIds = userToken[pid][msg.sender];
        uint256[] memory _tokenAmounts = amountOfId[pid][msg.sender];

        uint256 userAmount = _user.amount;

        uint256[] memory ids = new uint256[](tokenIdsIndex.length);
        uint256[] memory tokenAmount = new uint256[](tokenIdsIndex.length);

        for (uint256 i = 0; i < tokenIdsIndex.length; i++) {
            uint256 _tokenId = _userTokenIds[tokenIdsIndex[i]];
            (, uint256 _liquidity) = LBPair.getBin(uint24(_tokenId));
            ids[i] = _userTokenIds[tokenIdsIndex[i]];
            tokenAmount[i] = _tokenAmounts[tokenIdsIndex[i]];

            _tokenAmounts[tokenIdsIndex[i]] = _tokenAmounts[
                _tokenAmounts.length - 1
            ];
            _userTokenIds[tokenIdsIndex[i]] = _userTokenIds[
                _userTokenIds.length - 1
            ];

            _user.amount -= _liquidity;
            if (_user.amount != 0) {
                amountOfId[pid][msg.sender] = _tokenAmounts;
                amountOfId[pid][msg.sender].pop();
                userToken[pid][msg.sender] = _userTokenIds;
                userToken[pid][msg.sender].pop();
            } else {
                delete userToken[pid][msg.sender];
                delete amountOfId[pid][msg.sender];
            }
            _withdrawAndHarvest(
                pid,
                pool.accRewardPerShare,
                _tokenId,
                _liquidity,
                to,
                userAmount,
                _user
            );
        }
        // Interactions
        LBPair.batchTransferFrom(address(this), to, ids, tokenAmount);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        uint256[] memory _userTokenIds = userToken[pid][msg.sender];
        uint256[] memory _tokensAmount = amountOfId[pid][msg.sender];

        // Note: transfer can fail or succeed if `amount` is zero.

        delete amountOfId[pid][msg.sender];
        _emergencyWithdraw(pid, to);

        LBPair.batchTransferFrom(
            address(this),
            to,
            _userTokenIds,
            _tokensAmount
        );
    }

    function _deposit(
        uint _pid,
        uint256 _tokenId,
        uint256 _tokenAmount,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {
        amountOfId[_pid][msg.sender].push(_tokenAmount);
        (, uint256 liquidity) = LBPair.getBin(uint24(_tokenId));
        require(liquidity != 0, "Farming: no liquidity");
        _depositLiquidity(_pid, _tokenId, _user, _accRewardPerShare, liquidity);

        emit Deposit(msg.sender, _pid, _tokenId);
    }
}
