// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../interfaces/ILBPair.sol";
import "./BaseDexLpFarming.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DerivedDexLpFarming1155 is Ownable2Step, BaseDexLpFarming{
    using SafeERC20 for IERC20;

    uint256 private constant ACC_REWARD_PRECISION = 1e18;

    /// @notice token ids of user in pool.
    mapping(uint256 => mapping(address => uint256[])) public amountOfId;

    ILBPair public LBPair;

    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint
    );

    /// @param _rewardToken The REWARD token contract address.
    constructor(
        IERC20 _rewardToken,
        ILBPair _LBPair
    ) BaseDexLpFarming(_rewardToken){
        LBPair = _LBPair;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    function add(uint256 allocPoint) public onlyOwner {

        _addPool(allocPoint);

        emit LogPoolAddition(poolInfo.length ,allocPoint);
    }


    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending) {
        (,uint256 _lpSupply) = LBPair.getReserve();
        pending = _pendingReward(_pid, _user, _lpSupply);
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
       (,uint256 lpSupply) = LBPair.getReserve();
        pool = _updatePool(pid, lpSupply);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIds LP token ids to deposit.
    function depositBatch(uint256 pid, uint256[] memory tokenIds, uint256[] memory tokenAmounts) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        // Effects
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _deposit(pid, tokenIds[i],tokenAmounts[i], user, pool.accRewardPerShare);
        }
        // Interactions
        LBPair.batchTransferFrom(msg.sender, address(this), tokenIds, tokenAmounts);
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenIds LP token ids to withdraw.
    function withdrawBatch(uint256 pid, uint256[] memory tokenIds, uint256[] memory tokenAmounts) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _withdraw(
                pid,
                tokenIds[i],
                tokenAmounts[i],
                user,
                pool.accRewardPerShare
            );
        }
        LBPair.batchTransferFrom(address(this), msg.sender, tokenIds, tokenAmounts);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(uint256 pid, address to) external {
        PoolInfo memory pool = updatePool(pid);
        _harvest(pid, pool, to);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param tokenId LP token id to withdraw.
    function withdrawAndHarvest(
        uint256 pid,
        uint256[] memory tokenId,
        address to,
        uint256[] memory tokensAmount
    ) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory _user = userInfo[pid][msg.sender];
        require(_user.amount != 0, "DexLpFarming: can not withdraw");
        for (uint256 i = 0; i < tokenId.length; i++) {
            _withdraw(
                pid,
                tokenId[i],
                tokensAmount[i],
                _user,
                pool.accRewardPerShare
            );
        (,uint256 userAmount) = LBPair.getBin(uint24(tokenId[i]));
        _withdrawAndHarvest(pid, pool, tokenId[i],tokensAmount[i], to, userAmount, _user);
        }
        // Interactions
        LBPair.batchTransferFrom(address(this), to, tokenId, tokensAmount);
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

        LBPair.batchTransferFrom(address(this), to, _userTokenIds, _tokensAmount);
    }

    function _deposit(
        uint _pid,
        uint256 _tokenId,
        uint256 _tokenAmount,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {
        amountOfId[_pid][msg.sender].push(_tokenAmount);
        (,uint256 userAmount) = LBPair.getBin(uint24(_tokenId));
        _depositLiquidity(_pid,_tokenId, _user, _accRewardPerShare, userAmount);

        emit Deposit(msg.sender, _pid, _tokenId);
    }

    function _withdraw(
        uint _pid,
        uint256 _tokenId,
        uint256 _tokenAmount,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {

        uint256[] memory _userTokenIds = userToken[_pid][msg.sender];
        uint256[] memory _tokenAmounts = amountOfId[_pid][msg.sender];
        for (uint256 i = 0; i < _userTokenIds.length; i++) {
            if (_userTokenIds[i] == _tokenId) {
                _tokenAmounts[i] -= _tokenAmount;
                break;
            }
        }

        if (_user.amount != 0) {
            amountOfId[_pid][msg.sender] = _tokenAmounts;

        } else {
            delete userToken[_pid][msg.sender];
            delete amountOfId[_pid][msg.sender];
        }

        (,uint256 userAmount) = LBPair.getBin(uint24(_tokenId));
        
        _withdrawLiquidity(_pid, _tokenId, _user, _accRewardPerShare, userAmount);


        emit Withdraw(msg.sender, _pid, _tokenId);
    }
}