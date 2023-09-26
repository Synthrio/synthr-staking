// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice depositer get reward tokens on the basis or reward per block
contract GaugeController is AccessControl{
    using SafeERC20 for IERC20;

    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");
    uint256 private constant ACC_REWARD_PRECISION = 1e18;
    uint256 public constant MAX_REWARD_TOKEN = 8;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256[8] rewardDebt;
    }

    /// @notice Info of each gauge pool.
    struct PoolInfo {
        uint256 index;
        uint256 epoch;
        uint64 lastRewardBlock;
        address pool;
    }

    mapping (address => RewardInfo[8]) public reward;

    /// @notice Info of each token in pool.
    struct RewardInfo{
        address token;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
    }

    address public owner;

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
    event EpochUpdated(uint256 indexed pid, uint256 newMaxRewardToken);
    event SetMaxRewardToken(uint256 newMaxRewardToken);

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
    function addPool(uint256 _epoch, IERC20 _lpToken, address _pool, RewardInfo[] memory _reward) public onlyOwner {
        lpToken.push(_lpToken);

        poolInfo.push(PoolInfo({
            epoch: _epoch,
            lastRewardBlock: uint64(block.number),
            pool: _pool,
            index: _reward.length - 1
        }));

        RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];
        for (uint256 i = 0; i<_reward.length; ++i) {
            _rewardInfo[i] = _reward[i];
        }

        reward[_pool] = _rewardInfo;

        _grantRole(POOL_ROLE, _pool);
        emit LogPoolAddition(lpToken.length - 1, _lpToken);
    }

    /// @notice function to add reward token in pool on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _reward array of reward token info to add in pool
    function addRewardToken(uint256 _pid, RewardInfo[] memory _reward) public onlyOwner {
        PoolInfo memory _poolInfo = poolInfo[_pid];
        RewardInfo[MAX_REWARD_TOKEN] memory _rewardInfo = reward[_poolInfo.pool];
        uint256 _index =_poolInfo.index;
        for (uint256 i = _index; i< _reward.length; ++i) {
            _rewardInfo[i] = _reward[i - _index];
        }
        poolInfo[_pid].index += _reward.length - 1;
        emit LogSetPool(_pid, _reward);
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(uint256 _pid, address _user) external view returns (uint256 pending_) {
        PoolInfo memory _poolInfo = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_poolInfo.pool];

        for (uint256 i = 0; i< _poolInfo.index; ++i) {
            uint256 accRewardPerShare = rewardInfo[i].accRewardPerShare;
            uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
            if (block.number > _poolInfo.lastRewardBlock && lpSupply != 0) {
                uint256 blocks = block.number - (_poolInfo.lastRewardBlock);
                uint256 rewardAmount = blocks * (rewardInfo[i].rewardPerBlock);
                accRewardPerShare = accRewardPerShare + (rewardAmount * (ACC_REWARD_PRECISION) / lpSupply);
            }
            pending_ += (user.amount * (accRewardPerShare) / ACC_REWARD_PRECISION) - uint256(user.rewardDebt[i]);
        }
    }

    /// @notice update epoch for given pool 
    /// @param _pid Pool ID of pool to be updated. Make sure to update all active pools.
    /// @param _newEpoch new epoch.
    function updateEpoch(uint256 _pid, uint256 _newEpoch) external {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        poolInfo[_pid].epoch = _newEpoch;
        emit EpochUpdated(_pid, _newEpoch);
    }

    /// @notice Update reward variables for all pools. Be careful of gas spending!
    /// @param pids Pool IDs of all to be updated. Make sure to update all active pools.
    function massUpdatePools(uint256[] calldata pids) external {
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; ++i) {
            updatePool(pids[i]);
        }
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return poolInfo_ Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory poolInfo_) {
        poolInfo_ = poolInfo[pid];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[poolInfo_.pool];
        if (block.number > poolInfo_.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(poolInfo_.pool);
            uint256 _index = poolInfo_.index;
            for (uint256 i = 0; i<_index; ++i) {
                if (lpSupply > 0) {
                    uint256 blocks = block.number - (poolInfo_.lastRewardBlock);
                    uint256 rewardAmount = blocks * (rewardInfo[i].rewardPerBlock);
                    rewardInfo[i].accRewardPerShare = rewardInfo[i].accRewardPerShare + uint128(rewardAmount * (ACC_REWARD_PRECISION) / lpSupply);
                }
                poolInfo_.lastRewardBlock = uint64(block.number);
                poolInfo[pid] = poolInfo_;
            emit LogUpdatePool(pid, poolInfo_.lastRewardBlock, lpSupply, rewardInfo[i].rewardPerBlock);
            }
        }
    }

    /// @notice Deposit LP tokens to pool for syUSD allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param amount LP token amount to deposit.
    /// @param to The receiver of `amount` deposit benefit.
    function updateReward(uint256 pid, uint256 amount, address to, bool _increase) public {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        PoolInfo memory _poolInfo = updatePool(pid);
        UserInfo memory user = userInfo[pid][to];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_poolInfo.pool]; 

        int256[MAX_REWARD_TOKEN] memory _rewardDebt = user.rewardDebt;

        // Effects
        if (_increase) {
            user.amount = user.amount + (amount);
            for (uint256 i = 0; i<rewardInfo.length; ++i) {
                _rewardDebt[i] = _rewardDebt[i] + (int256(amount * (rewardInfo[i].accRewardPerShare) / ACC_REWARD_PRECISION));
            }
        }
        else {
            user.amount = user.amount - (amount);
            for (uint256 i = 0; i<rewardInfo.length; ++i) {
                _rewardDebt[i] = _rewardDebt[i] - (int256(amount * (rewardInfo[i].accRewardPerShare) / ACC_REWARD_PRECISION));
            }
        }

        user.rewardDebt = _rewardDebt;
        userInfo[pid][to] = user;

    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of syUSD rewards.
    function claim(uint256 pid, address to) public {
        PoolInfo memory _poolInfo = updatePool(pid);
        UserInfo storage user = userInfo[pid][msg.sender];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_poolInfo.pool];
        uint256 _totalPendingReward;
        for (uint256 i = 0; i< _poolInfo.index; ++i) {
            int256 accumulatedReward = int256(user.amount * (rewardInfo[i].accRewardPerShare) / ACC_REWARD_PRECISION);
            uint256 _pendingReward = uint256(accumulatedReward - (user.rewardDebt[i]));
            
            // Effects
            user.rewardDebt[i] = accumulatedReward;

            // Interactions
            if (_pendingReward != 0) {
                IERC20(rewardInfo[i].token).safeTransfer(to, _pendingReward);
                _totalPendingReward += _pendingReward;
            }
        }
        emit Claimed(msg.sender, pid, _totalPendingReward);
    }
    
    /// @notice Withdraw LP tokens from pool and claim proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param _amount LP token amount to withdraw.
    /// @param to Receiver of the LP tokens and syUSD rewards.
    function decreaseRewardAndClaim(uint256 pid, uint256 _amount, address to) public {
        require(hasRole(POOL_ROLE, msg.sender), "VotingEscrow: pools only");
        PoolInfo memory _poolInfo = updatePool(pid);
        UserInfo memory _user = userInfo[pid][msg.sender];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_poolInfo.pool];
        uint256 _totalPendingReward;
        for (uint256 i = 0; i< _poolInfo.index; ++i) {
            int256 accumulatedReward = int256(_user.amount * (rewardInfo[i].accRewardPerShare) / ACC_REWARD_PRECISION);
            uint256 _pendingReward = uint256(accumulatedReward - (_user.rewardDebt[i]));
            
            // Effects
            _user.rewardDebt[i] = accumulatedReward;
            _user.amount -= _amount;
            userInfo[pid][msg.sender] = _user;
            // Interactions
            if (_pendingReward != 0) {
                IERC20(rewardInfo[i].token).safeTransfer(to, _pendingReward);
                _totalPendingReward += _pendingReward;
            }
        }

        emit Claimed(msg.sender, pid, _totalPendingReward);
    }

}