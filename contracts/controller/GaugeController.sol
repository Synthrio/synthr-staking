// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @notice depositer get reward tokens on the basis or reward per block
contract GaugeController is AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant POOL_ROLE = keccak256("POOL_ROLE");
    uint256 public constant ACC_REWARD_PRECISION = 1e18;
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
    }

    /// @notice Info of each token in pool.
    struct RewardInfo {
        address token;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
    }

    /// @notice Info of each pool.
    mapping(address => PoolInfo) public poolInfo;
    /// @notice Address of the LP token for each pool.
    mapping(address => IERC20) public lpToken;

    mapping(address => RewardInfo[8]) public reward;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Claimed(address indexed user, address indexed pool, uint256 amount);
    event LogPoolAddition(address indexed pool, address indexed lpToken);
    event LogSetPool(address indexed pool, RewardInfo[] poolReward);
    event LogUpdatePool(address indexed pool, uint64 lastRewardBlock);
    event EpochUpdated(address indexed pool, uint256 newMaxRewardToken);
    event SetMaxRewardToken(uint256 newMaxRewardToken);

    constructor(address _admin) {
        _grantRole(CONTROLLER_ROLE, _admin);
    }

    function userRewards(address _pool, address _user) external view returns (int256[MAX_REWARD_TOKEN] memory) {
        return userInfo[_pool][_user].rewardDebt;
    }

    /// @notice View function to see pending reward of by token on frontend.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function userRewardByToken(address _pool, address _user, uint256 indexOfRewardToken)
        external
        view
        returns (uint256 pending_)
    {
        PoolInfo memory _poolInfo = poolInfo[_pool];
        UserInfo memory user = userInfo[_pool][_user];
        RewardInfo[MAX_REWARD_TOKEN] memory _rewardInfo = reward[_pool];
        uint256 lpSupply = lpToken[_pool].balanceOf(_pool);
        if (block.number > _poolInfo.lastRewardBlock && lpSupply != 0) {
            pending_ += _pendingRewardForToken(
                user.amount,
                user.rewardDebt[indexOfRewardToken],
                lpSupply,
                _rewardInfo[indexOfRewardToken].accRewardPerShare,
                _rewardInfo[indexOfRewardToken].rewardPerBlock,
                _poolInfo.lastRewardBlock,
                block.number
            );
        }
    }

    /// @notice View function to see pending reward at current block on frontend.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(address _pool, address _user) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_pool, _user, block.number);
    }

    /// @notice View function to see pending reward at future block on frontend.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingRewardAtBlock(address _pool, address _user, uint256 _blockNumber)
        external
        view
        returns (uint256 pending_)
    {
        pending_ = _pendingRewardAmount(_pool, _user, _blockNumber);
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param _lpToken Address of the LP ERC-20 token.
    function addPool(address _lpToken, address _pool, RewardInfo[] memory _reward) external {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "GaugeController: not authorized");
        lpToken[_pool] = IERC20(_lpToken);

        poolInfo[_pool] = PoolInfo({epoch: 0, lastRewardBlock: uint64(block.number), index: _reward.length - 1});

        RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];
        for (uint256 i = 0; i < _reward.length; ++i) {
            _rewardInfo[i] = _reward[i];
        }

        _grantRole(POOL_ROLE, _pool);
        emit LogPoolAddition(_pool, address(_lpToken));
    }

    /// @notice function to add reward token in pool on frontend.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _reward array of reward token info to add in pool
    function addRewardToken(address _pool, RewardInfo[] memory _reward) external {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "GaugeController: not authorized");
        PoolInfo memory _poolInfo = poolInfo[_pool];
        uint256 _index = _poolInfo.index + 1;
        require(_index + _reward.length <= MAX_REWARD_TOKEN, "GaugeController: excced reward tokens");
        RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];
        uint256 _len = _index + _reward.length;
        for (uint256 i = _index; i < _len; ++i) {
            _rewardInfo[i] = _reward[i - _index];
        }
        poolInfo[_pool].index += _reward.length;
        emit LogSetPool(_pool, _reward);
    }

    /// @notice update epoch for given pool
    /// @param _pool Pool address of pool to be updated. Make sure to update all active pools.
    /// @param _indexes index of rewardInfo array.
    /// @param _rewardPerBlock array of rewardPerBlock
    function updateEpoch(
        address _pool,
        address _user,
        uint256[] memory _indexes,
        uint256[] memory _rewardPerBlock,
        uint256[] memory _rewardAmount
    ) external {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "GaugeController: not authorized");
        require(_indexes.length == _rewardPerBlock.length, "GaugeController: length of array doesn't mach");

        RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];

        for (uint256 i = 0; i < _indexes.length; ++i) {
            _rewardInfo[_indexes[i]].rewardPerBlock = _rewardPerBlock[i];
            IERC20(_rewardInfo[_indexes[i]].token).safeTransferFrom(_user, address(this), _rewardAmount[i]);
        }

        poolInfo[_pool].epoch++;
        emit EpochUpdated(_pool, poolInfo[_pool].epoch);
    }

    /// @notice Deposit LP tokens to pool for syUSD allocation.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _amount LP token amount to deposit.
    /// @param _to The receiver of `amount` deposit benefit.
    function updateReward(address _pool, address _to, uint256 _amount, bool _increase) external {
        require(hasRole(POOL_ROLE, msg.sender), "GaugeController: not authorized");
        PoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][_to];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_pool];

        int256[MAX_REWARD_TOKEN] memory _rewardDebt = _user.rewardDebt;

        // Effects
        for (uint256 i = 0; i <= _poolInfo.index; ++i) {
            int256 _calRewardDebt = _calAccReward(rewardInfo[i].accRewardPerShare, _amount);
            if (_increase) {
                _user.amount += _amount;
                _rewardDebt[i] += _calRewardDebt;
            } else {
                _user.amount -= _amount;
                _rewardDebt[i] -= _calRewardDebt;
            }
        }

        _user.rewardDebt = _rewardDebt;
        userInfo[_pool][_to] = _user;
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _to Receiver of syUSD rewards.
    function claim(address _pool, address _to) external {
        PoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_pool];
        uint256 _totalPendingReward;
        for (uint256 i = 0; i <= _poolInfo.index; ++i) {
            (int256 accumulatedReward, uint256 _pendingReward) = _claimForToken(
                _user.amount, _user.rewardDebt[i], rewardInfo[i].accRewardPerShare, rewardInfo[i].token, _to
            );
            // Effects
            _user.rewardDebt[i] = accumulatedReward;
            _totalPendingReward += _pendingReward;
        }
        userInfo[_pool][msg.sender] = _user;
        emit Claimed(msg.sender, _pool, _totalPendingReward);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _to Receiver of syUSD rewards.
    /// @param _index token index in reward tokens of pool.
    function claimForToken(address _pool, address _to, uint256 _index) external {
        updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_pool];

        (int256 accumulatedReward, uint256 _pendingReward) = _claimForToken(
            _user.amount, _user.rewardDebt[_index], rewardInfo[_index].accRewardPerShare, rewardInfo[_index].token, _to
        );

        _user.rewardDebt[_index] = accumulatedReward;

        userInfo[_pool][msg.sender] = _user;
        emit Claimed(msg.sender, _pool, _pendingReward);
    }

    /// @notice Withdraw LP tokens from pool and claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _amount LP token amount to withdraw.
    /// @param _to Receiver of the LP tokens and syUSD rewards.
    function decreaseRewardAndClaim(address _pool, uint256 _amount, address _to) external {
        require(hasRole(POOL_ROLE, msg.sender), "GaugeController: not authorized");
        PoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][_to];
        RewardInfo[MAX_REWARD_TOKEN] memory rewardInfo = reward[_pool];
        uint256 _totalPendingReward;
        for (uint256 i = 0; i <= _poolInfo.index; ++i) {
            int256 accumulatedReward = _calAccReward(rewardInfo[i].accRewardPerShare, _user.amount);
            uint256 _pendingReward = uint256(accumulatedReward - (_user.rewardDebt[i]));

            // Effects
            _user.rewardDebt[i] = accumulatedReward - (_calAccReward(_amount, rewardInfo[i].accRewardPerShare));
            // Interactions
            if (_pendingReward != 0) {
                IERC20(rewardInfo[i].token).safeTransfer(_to, _pendingReward);
                _totalPendingReward += _pendingReward;
            }
        }

        _user.amount -= _amount;
        userInfo[_pool][_to] = _user;

        emit Claimed(_to, _pool, _totalPendingReward);
    }

    /// @notice Update reward variables of the given pool.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @return _poolInfo Returns the pool that was updated.
    function updatePool(address _pool) public returns (PoolInfo memory _poolInfo) {
        _poolInfo = poolInfo[_pool];
        RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];

        uint256 lpSupply = lpToken[_pool].balanceOf(_pool);
        if (block.number > _poolInfo.lastRewardBlock && lpSupply > 0) {
            uint256 _index = _poolInfo.index + 1;
            for (uint256 i = 0; i < _index; ++i) {
                _rewardInfo[i].accRewardPerShare += _calAccFromRewardPerBlock(
                    _poolInfo.lastRewardBlock, _rewardInfo[i].rewardPerBlock, lpSupply, block.number
                );
            }
        }
        _poolInfo.lastRewardBlock = uint64(block.number);
        poolInfo[_pool] = _poolInfo;
        emit LogUpdatePool(_pool, uint64(block.number));
    }

    function _calAccReward(uint256 _accRewardPerShare, uint256 _amount) internal pure returns (int256) {
        return int256((_amount * _accRewardPerShare) / ACC_REWARD_PRECISION);
    }

    function _calAccRewardPerShare(uint256 _rewardAmount, uint256 _lpSupply) internal pure returns (uint256) {
        return (_rewardAmount * ACC_REWARD_PRECISION) / _lpSupply;
    }

    function _calRewardAmount(uint256 _lastRewardBlock, uint256 _rewardPerBlock, uint256 _blockNumber)
        internal
        pure
        returns (uint256)
    {
        uint256 blocks = _blockNumber - _lastRewardBlock;
        return blocks * _rewardPerBlock;
    }

    function _calAccFromRewardPerBlock(
        uint256 _lastRewardBlock,
        uint256 _rewardPerBlock,
        uint256 _lpSupply,
        uint256 _blockNumber
    ) internal pure returns (uint256) {
        uint256 rewardAmount = _calRewardAmount(_lastRewardBlock, _rewardPerBlock, _blockNumber);
        return _calAccRewardPerShare(rewardAmount, _lpSupply);
    }

    function _pendingRewardForToken(
        uint256 _amount,
        int256 _rewardDebt,
        uint256 _lpSupply,
        uint256 _accRewardPerShare,
        uint256 _rewardPerBlock,
        uint256 _lastRewardBlock,
        uint256 _blockNumber
    ) internal pure returns (uint256 _pending) {
        _accRewardPerShare += _calAccFromRewardPerBlock(_lastRewardBlock, _rewardPerBlock, _lpSupply, _blockNumber);
        _pending = uint256(_calAccReward(_accRewardPerShare, _amount) - (_rewardDebt));
    }

    function _pendingRewardAmount(address _pool, address _user, uint256 _blockNumber)
        internal
        view
        returns (uint256 pending_)
    {
        PoolInfo memory _poolInfo = poolInfo[_pool];
        UserInfo memory user = userInfo[_pool][_user];
        RewardInfo[MAX_REWARD_TOKEN] memory _rewardInfo = reward[_pool];
        uint256 lpSupply = lpToken[_pool].balanceOf(_pool);
        if (block.number > _poolInfo.lastRewardBlock && lpSupply != 0) {
            for (uint256 i = 0; i <= _poolInfo.index; ++i) {
                pending_ += _pendingRewardForToken(
                    user.amount,
                    user.rewardDebt[i],
                    lpSupply,
                    _rewardInfo[i].accRewardPerShare,
                    _rewardInfo[i].rewardPerBlock,
                    _poolInfo.lastRewardBlock,
                    _blockNumber
                );
            }
        }
    }

    function _claimForToken(
        uint256 _amount,
        int256 _rewardDebt,
        uint256 _accRewardPerShare,
        address _token,
        address _to
    ) internal returns (int256 _accmulatedReward, uint256 _pendingReward) {
        _accmulatedReward = _calAccReward(_accRewardPerShare, _amount);

        _pendingReward = uint256(_accmulatedReward - _rewardDebt);

        if (_pendingReward != 0) {
            IERC20(_token).safeTransfer(_to, _pendingReward);
        }
    }
}
