// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice depositer get reward tokens on the basis or reward per block
contract GaugeController is AccessControl{
    using SafeERC20 for IERC20;

    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256[] rewardDebt;
    }

    /// @notice Info of each gauge pool.
    struct PoolInfo {
        uint256 epoch;
        uint64 lastRewardBlock;
        address poolContractAddres;
        RewardInfo[] reward;
    }

    /// @notice Info of each token in pool.
    struct RewardInfo{
        address token;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
    }

    address public owner;

    uint256 private constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Info of each pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each pool.
    IERC20[] public lpToken;

    /// @notice Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;

    event Claimed(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(uint256 indexed pid, IERC20 indexed lpToken);
    event LogSetPool(uint256 indexed pid, RewardInfo[] poolReward);
    event LogUpdatePool(uint256 indexed pid, uint64 lastRewardBlock, uint256 lpSupply, uint256 accSushiPerShare);


    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "GaugeController: not authorized");
        _;
    }

    /// @notice Returns the number of gauge pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(uint256 _epoch, IERC20 _lpToken, address _poolContractAddres, RewardInfo[] memory _rewardInfo) public onlyOwner {
        uint256 lastRewardBlock = block.number;
        lpToken.push(_lpToken);

        poolInfo.push(PoolInfo({
            epoch: _epoch,
            lastRewardBlock: uint64(lastRewardBlock),
            poolContractAddres: _poolContractAddres,
            reward: _rewardInfo
        }));

        _grantRole(POOL_ROLE, _poolContractAddres);
        emit LogPoolAddition(lpToken.length - 1, _lpToken);
    }

    function set(uint256 _pid, RewardInfo[] memory _reward) public onlyOwner {
        poolInfo[_pid].reward = _reward;
        emit LogSetPool(_pid, _reward);
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending reward for a given user.
    function pendingSYNTH(uint256 _pid, address _user) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];

        for (uint256 i = 0; i<pool.reward.length; ++i) {
            uint256 accRewardPerShare = pool.reward[i].accRewardPerShare;
            uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
            if (block.number > pool.lastRewardBlock && lpSupply != 0) {
                uint256 blocks = block.number - (pool.lastRewardBlock);
                uint256 rewardAmount = blocks * (pool.reward[i].rewardPerBlock);
                accRewardPerShare = accRewardPerShare + (rewardAmount * (ACC_REWARD_PRECISION) / lpSupply);
            }
            pending += (user.amount * (accRewardPerShare) / ACC_REWARD_PRECISION) - uint256(user.rewardDebt[i]);
        }
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Calculates and returns the `amount` of SUSHI per block.
    function rewardPerBlock() public view returns (uint256 amount) {
        
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(pool.poolContractAddres);
            for (uint256 i = 0; i<pool.reward.length; ++i) {
                if (lpSupply > 0) {
                    uint256 blocks = block.number - (pool.lastRewardBlock);
                    uint256 rewardAmount = blocks * (pool.reward[i].rewardPerBlock);
                    pool.reward[i].accRewardPerShare = pool.reward[i].accRewardPerShare + uint128(rewardAmount * (ACC_REWARD_PRECISION) / lpSupply);
                }
                pool.lastRewardBlock = uint64(block.number);
                poolInfo[pid] = pool;
            emit LogUpdatePool(pid, pool.lastRewardBlock, lpSupply, pool.reward[i].rewardPerBlock);
            }
        }
    }

    /// @notice Deposit LP tokens to pool for syUSD allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function increaseReward(uint256 pid, uint256 amount, address to) public {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][to];

        // Effects
        user.amount = user.amount + (amount);
        for (uint256 i = 0; i<pool.reward.length; ++i) {
            user.rewardDebt[i] = user.rewardDebt[i] + (int256(amount * (pool.reward[i].accRewardPerShare) / ACC_REWARD_PRECISION));
        }

        userInfo[pid][to] = user;

    }

    /// @notice Withdraw LP tokens from pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens.
    function decreaseReward(uint256 pid, uint256 amount, address to) public {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory _user = userInfo[pid][to];

        // Effects
        for (uint256 i = 0; i<pool.reward.length; ++i) {
            _user.rewardDebt[i] = _user.rewardDebt[i] - (int256(amount * (pool.reward[i].accRewardPerShare) / ACC_REWARD_PRECISION));
        }
        
        _user.amount = _user.amount - (amount);
        userInfo[pid][to] = _user;
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of syUSD rewards.
    function claim(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        uint256 _totalPendingSushi;
        for (uint256 i = 0; i<pool.reward.length; ++i) {
            int256 accumulatedReward = int256(user.amount * (pool.reward[i].accRewardPerShare) / ACC_REWARD_PRECISION);
            uint256 _pendingSushi = uint256(accumulatedReward - (user.rewardDebt[i]));
            
            // Effects
            user.rewardDebt[i] = accumulatedReward;

            // Interactions
            if (_pendingSushi != 0) {
                IERC20(pool.reward[i].token).safeTransfer(to, _pendingSushi);
                _totalPendingSushi += _pendingSushi;
                // SYNTH.safeTransfer(to, _pendingSushi);
            }
        }
        emit Claimed(msg.sender, pid, _totalPendingSushi);
    }
    
    /// @notice Withdraw LP tokens from pool and claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and syUSD rewards.
    function decreaseRewardAndClaim(uint256 pid, uint256 amount, address to) public {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory _user = userInfo[pid][msg.sender];
        uint256 _totalPendingSushi;
        for (uint256 i = 0; i<pool.reward.length; ++i) {
            int256 accumulatedReward = int256(_user.amount * (pool.reward[i].accRewardPerShare) / ACC_REWARD_PRECISION);
            uint256 _pendingSushi = uint256(accumulatedReward - (_user.rewardDebt[i]));
            
            // Effects
            _user.rewardDebt[i] = accumulatedReward;
            userInfo[pid][msg.sender] = _user;
            // Interactions
            if (_pendingSushi != 0) {
                IERC20(pool.reward[i].token).safeTransfer(to, _pendingSushi);
                _totalPendingSushi += _pendingSushi;
            }
        }

        emit Claimed(msg.sender, pid, _totalPendingSushi);
    }

}