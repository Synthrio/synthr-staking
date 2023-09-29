// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract DexLpFarming is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Info of each DexLpFarming user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each DexLpFarming pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of reward token to distribute per block.
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardBlock;
        uint64 allocPoint;
    }

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Info of each DexLpFarming pool.
    PoolInfo[] public poolInfo;
    /// @notice Address of the LP token for each DexLpFarming pool.
    IERC721[] public lpToken;

    /// @notice Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    /// @notice token ids of user in pool.
    mapping(uint256 => mapping(address => uint256[])) public userToken;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public rewardPerBlock;
    uint256 public currentEpoch;
    uint256 private constant ACC_REWARD_PRECISION = 1e18;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        address indexed to
    );
    event Harvest(address indexed user, uint256 indexed pid, uint256 amount);
    event LogPoolAddition(
        uint256 indexed pid,
        uint256 allocPoint,
        IERC721 indexed lpToken
    );
    event LogSetPool(uint256 indexed pid, uint256 allocPoint);
    event LogUpdatePool(
        uint256 indexed pid,
        uint64 lastRewardBlock,
        uint256 lpSupply,
        uint256 accRewardPerShare
    );
    event LogRewardPerBlock(uint256 rewardPerBlock, uint256 indexed currentEpoch, uint256 amount);

    /// @param _rewardToken The REWARD token contract address.
    constructor(IERC20 _rewardToken) {
        REWARD_TOKEN = _rewardToken;
    }

    /// @notice Returns the number of DexLpFarming pools.
    function poolLength() public view returns (uint256 pools) {
        pools = poolInfo.length;
    }

    /// @notice Returns the number of user tokens ids in the pool.
    function userTokenIds(
        uint256 pid,
        address user
    ) public view returns (uint256[] memory) {
        return userToken[pid][user];
    }

    /// @notice Add a new LP to the pool. Can only be called by the owner.
    /// DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    /// @param allocPoint AP of the new pool.
    /// @param _lpToken Address of the LP ERC-20 token.
    function add(uint256 allocPoint, IERC721 _lpToken) public onlyOwner {
        totalAllocPoint += allocPoint;
        lpToken.push(_lpToken);

        poolInfo.push(
            PoolInfo({
                allocPoint: uint64(allocPoint),
                lastRewardBlock: uint64(block.number),
                accRewardPerShare: 0
            })
        );
        emit LogPoolAddition(lpToken.length - 1, allocPoint, _lpToken);
    }

    /// @notice Update the given pool's reward token allocation point. Can only be called by the owner.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _allocPoint New AP of the pool.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOwner {
        uint256 _totalAllocPoint = totalAllocPoint;
        _totalAllocPoint += _allocPoint;
        _totalAllocPoint -= poolInfo[_pid].allocPoint;
        totalAllocPoint = _totalAllocPoint;
        poolInfo[_pid].allocPoint = uint64(_allocPoint);
        emit LogSetPool(_pid, _allocPoint);
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerBlock The amount of reward token to be distributed per block number.
    /// @param _user address from which reward is to be distributed.
    /// @param _amount The amount of reward token to be deposit in dexLpFarmin.
    function setRewardPerBlock(uint256 _rewardPerBlock, address _user, uint256 _amount) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;
        ++currentEpoch;
        REWARD_TOKEN.safeTransferFrom(_user, address(this), _amount);
        emit LogRewardPerBlock(_rewardPerBlock, currentEpoch, _amount);
    }

    /// @notice View function to see pending reward on frontend.
    /// @param _pid The index of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending REWARD_TOKEN reward for a given user.
    function pendingReward(
        uint256 _pid,
        address _user
    ) external view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo[_pid];
        UserInfo memory user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 lpSupply = lpToken[_pid].balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 blocks = block.number - (pool.lastRewardBlock);
            uint256 rewardAmount = (blocks *
                (rewardPerBlock) *
                (pool.allocPoint)) / totalAllocPoint;
            accRewardPerShare += ((rewardAmount * (ACC_REWARD_PRECISION)) /
                lpSupply);
        }
        pending = uint256(
            int256((user.amount * accRewardPerShare) / ACC_REWARD_PRECISION) -
                user.rewardDebt
        );
    }

    /// @notice Update reward variables of the given pool.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @return pool Returns the pool that was updated.
    function updatePool(uint256 pid) public returns (PoolInfo memory pool) {
        pool = poolInfo[pid];
        if (block.number > pool.lastRewardBlock) {
            uint256 lpSupply = lpToken[pid].balanceOf(address(this));
            if (lpSupply > 0) {
                uint256 blocks = block.number - pool.lastRewardBlock;
                uint256 rewardAmount = (blocks *
                    rewardPerBlock *
                    pool.allocPoint) / totalAllocPoint;
                pool.accRewardPerShare += uint128(
                    (rewardAmount * ACC_REWARD_PRECISION) / lpSupply
                );
            }
            pool.lastRewardBlock = uint64(block.number);
            poolInfo[pid] = pool;
            emit LogUpdatePool(
                pid,
                pool.lastRewardBlock,
                lpSupply,
                pool.accRewardPerShare
            );
        }
    }

    /// @notice Deposit LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param id LP token id to deposit.
    function deposit(uint256 pid, uint256 id) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        _deposit(pid, id, user, pool.accRewardPerShare);
    }

    /// @notice Deposit batch LP tokens to DexLpFarming for REWARD_TOKEN allocation.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param id LP token ids to deposit.
    function depositBatch(uint256 pid, uint256[] memory id) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];

        // Effects
        for (uint256 i = 0; i < id.length; i++) {
            _deposit(pid, id[i], user, pool.accRewardPerShare);
        }
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param id LP token ids to withdraw.
    function withdrawBatch(uint256 pid, uint256[] memory id) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        uint256[] memory _userTokenIds = userToken[pid][msg.sender];

        for (uint256 i = 0; i < id.length; i++) {
            _withdraw(pid, id[i], user, pool.accRewardPerShare, _userTokenIds);
        }
    }

    /// @notice Withdraw LP tokens from DexLpFarming.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param id LP token id to withdraw.
    function withdraw(uint256 pid, uint256 id) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        uint256[] memory _userTokenIds = userToken[pid][msg.sender];

        _withdraw(pid, id, user, pool.accRewardPerShare, _userTokenIds);
    }

    /// @notice Harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of REWARD_TOKEN rewards.
    function harvest(uint256 pid, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        int256 accumulatedReward = int256(
            (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION
        );
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        user.rewardDebt = accumulatedReward;
        userInfo[pid][msg.sender] = user;
        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(to, _pendingReward);
        }

        emit Harvest(msg.sender, pid, _pendingReward);
    }

    /// @notice Withdraw LP tokens from DexLpFarming and harvest proceeds for transaction sender to `to`.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param id LP token id to withdraw.
    function withdrawAndHarvest(uint256 pid, uint256 id, address to) public {
        PoolInfo memory pool = updatePool(pid);
        UserInfo memory user = userInfo[pid][msg.sender];
        require(user.amount != 0, "DexLpFarming: can not withdraw");

        int256 accumulatedReward = int256(
            (user.amount * pool.accRewardPerShare) / ACC_REWARD_PRECISION
        );
        uint256 _pendingReward = uint256(accumulatedReward - user.rewardDebt);

        // Effects
        user.rewardDebt =
            accumulatedReward -
            int256((pool.accRewardPerShare) / ACC_REWARD_PRECISION);
        user.amount -= 1;

        userInfo[pid][msg.sender] = user;
        // Interactions
        REWARD_TOKEN.safeTransfer(to, _pendingReward);

        lpToken[pid].transferFrom(address(this), to, id);

        emit Withdraw(msg.sender, pid, id);
        emit Harvest(msg.sender, pid, _pendingReward);
    }

    /// @notice Withdraw without caring about rewards. EMERGENCY ONLY.
    /// @param pid The index of the pool. See `poolInfo`.
    /// @param to Receiver of the LP tokens.
    function emergencyWithdraw(uint256 pid, address to) public {
        UserInfo memory user = userInfo[pid][msg.sender];
        uint256[] memory _userTokenIds = userToken[pid][msg.sender];
        uint256 amount = user.amount;

        // Note: transfer can fail or succeed if `amount` is zero.
        for (uint256 i = 0; i < _userTokenIds.length; i++)
            lpToken[pid].transferFrom(address(this), to, _userTokenIds[i]);

        delete userInfo[pid][msg.sender];
        delete userToken[pid][msg.sender];
        emit EmergencyWithdraw(msg.sender, pid, amount, to);
    }

    function _deposit(
        uint _pid,
        uint256 _id,
        UserInfo memory _user,
        uint256 _accRewardPerShare
    ) internal {
        _user.amount += 1;
        userToken[_pid][msg.sender].push(_id);
        _user.rewardDebt += int256(_accRewardPerShare / ACC_REWARD_PRECISION);
        userInfo[_pid][msg.sender] = _user;

        // Interactions
        lpToken[_pid].transferFrom(msg.sender, address(this), _id);

        emit Deposit(msg.sender, _pid, _id);
    }

    function _withdraw(
        uint _pid,
        uint256 _id,
        UserInfo memory _user,
        uint256 _accRewardPerShare,
        uint256[] memory _userTokenIds
    ) internal {
        _user.rewardDebt -= int256((_accRewardPerShare) / ACC_REWARD_PRECISION);
        for (uint256 i = 0; i < _userTokenIds.length; i++) {
            if (_userTokenIds[i] == _id) {
                _userTokenIds[i] = _userTokenIds[_userTokenIds.length - 1];
                break;
            }
        }

        _user.amount -= 1;
        if (_user.amount != 0) {
            userToken[_pid][msg.sender] = _userTokenIds;
        } else {
            delete userToken[_pid][msg.sender];
        }
        userInfo[_pid][msg.sender] = _user;

        // Interactions
        lpToken[_pid].transferFrom(address(this), msg.sender, _id);

        emit Withdraw(msg.sender, _pid, _id);
    }
}
