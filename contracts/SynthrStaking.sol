// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract NftStaking is IERC721Receiver, Ownable, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;
    uint256 public constant THREE_MONTHS = 7776000;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 lockType;
        uint256 unlockEnd;
        int256 rewardDebt;
    }

    struct LockInfo {
        uint256 maxPoolSize;
        uint256 penalty;
        uint256 coolDownPeriod;
        uint256 totalStaked;
        bool exist;
    }

    struct PoolInfo {
        uint64 lastRewardBlock;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
        uint256 epoch;
    }

    bool public killed;
    
    uint256 public lockTime;

    uint256 public stakeAmount = 1000 * 1e18;

    /// @notice Total lock amount of users
    uint256 public totalSupply;

    PoolInfo public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    mapping(address => uint256) public coolDownPeriod;

    mapping(uint256 => LockInfo) public lockInfo;

    event Deposit(address indexed user, uint256 tokenId);
    event IncreaseDeposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 tokenId);
    event Claimed(address indexed user, uint256 pendingRewardAmount);
    event WithdrawAndClaim(address indexed user, uint256 pendingRewardAmount);
    event WithdrawPendingRewardAmount(
        address indexed user,
        uint256 pendingRewardAmount
    );
    event LogUpdatePool(uint64 lastRewardBlock, uint256 accRewardPerShare);
    event EpochUpdated(address indexed owner, uint256 rewardPerBlock);
    event LogUpdatedStakeAmount(address owner, uint256 stakeAmount);
    event LogUpdatedLockTime(address owner, uint256 lockTime);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event PoolAlived(address indexed owner, bool _alive);
    event KillPool(address indexed owner, bool _killed);
    event RollOverReward(address indexed user, uint256 newUnlockType, uint256 unlockTime);

    constructor(address _admin, address _rewardToken, uint256[] memory _lockType, LockInfo[] memory _lockInfo) Ownable(_admin) {
        require(_lockInfo.length == _lockType.length, "SynthrStaking: length not equal");
        lockTime = 10 days;
        REWARD_TOKEN = IERC20(_rewardToken);

        for (uint256 i; i < _lockType.length; i++) {
            lockInfo[_lockType[i]] = _lockInfo[i];
        }
    }

    modifier isAlive() {
        require(!killed, "SynthrStaking: pool is killed");
        _;
    }

    /// @dev retuen user reward debt
    /// @param _user address of user
    function userRewardsDebt(address _user) external view returns (int256) {
        return userInfo[_user].rewardDebt;
    }

    /// @notice View function to see pending reward of user in pool at current block.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(
        address _user
    ) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_user, block.number);
    }

    /// @notice View function to see pending reward of user at future block.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingRewardAtBlock(
        address _user,
        uint256 _blockNumber
    ) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_user, _blockNumber);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev pause pool to restrict pool functionality, can only by called by admin
     */
    function pausePool() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, can only by called by admin 
     */
    function unpausePool() external onlyOwner {
        _unpause();
    }

    /**
     * @dev kill pool to restrict pool functionality, can only by called by admin
     */
    function killPool() external onlyOwner {
        killed = true;
        emit KillPool(msg.sender, true);
    }

    /**
     * @dev revive pool, can only by called by admin 
     */
    function revivePool() external onlyOwner {
        killed = false;
        emit PoolAlived(msg.sender, false);
    }

    function setStakeAmount(
        uint256 _stakeAmount
    ) external onlyOwner {
        stakeAmount = _stakeAmount;
        emit LogUpdatedStakeAmount(msg.sender, stakeAmount);
    }

    function setLockTime(
        uint256 _lockTime
    ) external onlyOwner {
        lockTime = _lockTime;
        emit LogUpdatedLockTime(msg.sender, _lockTime);
    }

    /// @notice update epoch of pool
    function updateEpoch(
        address _user,
        uint256 _rewardAmount,
        uint256 _rewardPerBlock
    ) external whenNotPaused isAlive onlyOwner {
        PoolInfo memory _poolInfo = poolInfo;
        poolInfo.rewardPerBlock = _rewardPerBlock;
        ++_poolInfo.epoch;

        poolInfo = _poolInfo;

        REWARD_TOKEN.safeTransferFrom(_user, address(this), _rewardAmount);

        emit EpochUpdated(msg.sender, _rewardPerBlock);
    }

    /// @notice Update reward variables of the pool.
    function updatePool() internal returns (PoolInfo memory _poolInfo) {
        _poolInfo = poolInfo;
        uint256 _lpSupply = totalSupply;
        if (block.number > _poolInfo.lastRewardBlock) {
            if (_lpSupply > 0) {
                uint256 _blocks = block.number - _poolInfo.lastRewardBlock;
                uint256 _rewardAmount = (_blocks * _poolInfo.rewardPerBlock);
                _poolInfo.accRewardPerShare += _calAccPerShare(
                    _rewardAmount,
                    _lpSupply
                );
            }
            _poolInfo.lastRewardBlock = uint64(block.number);
            poolInfo = _poolInfo;

            emit LogUpdatePool(
                _poolInfo.lastRewardBlock,
                _poolInfo.accRewardPerShare
            );
        }
    }

    /// @notice Deposit token.
    function deposit(uint256 _amount, uint256 _lockType) external whenNotPaused isAlive {
        LockInfo memory _lockInfo = lockInfo[_lockType];
        require(_lockInfo.exist, "SynthrStaking: lock type not exist");
        require(_lockInfo.totalStaked + _amount <= _lockInfo.maxPoolSize, "SynthrStaking: max amount limit exceed");

        PoolInfo memory _poolInfo = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _amount
        );

        _user.amount = _amount;
        _user.rewardDebt += _calRewardDebt;
        _user.unlockEnd = block.timestamp + _lockType;
        _user.lockType = _lockType;

        userInfo[msg.sender] = _user;

        totalSupply += _amount;
        _lockInfo.totalStaked += _amount;
        lockInfo[_lockType] = _lockInfo;

        REWARD_TOKEN.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _to Receiver rewards.
    function claim(address _to) external whenNotPaused {
        PoolInfo memory _poolInfo = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        (
            int256 accumulatedReward,
            uint256 _pendingReward
        ) = _calAccumaltedAndPendingReward(
                _poolInfo.accRewardPerShare,
                _user.amount,
                _user.rewardDebt
            );

        // Effects
        _user.rewardDebt = accumulatedReward;
        userInfo[msg.sender] = _user;

        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingReward);
        }

        emit Claimed(msg.sender, _pendingReward);
    }

    function rollOverTime(uint256 _newLockType) external whenNotPaused isAlive {
        LockInfo memory _newlockInfo = lockInfo[_newLockType];
        require(_newlockInfo.exist, "SynthrStaking: lock type not exist");

        UserInfo memory _user = userInfo[msg.sender];
        require(_user.lockType < _newLockType, "SynthrStaking: Can only increase lock duration");
        require(_newlockInfo.totalStaked + _user.amount <= _newlockInfo.maxPoolSize, "SynthrStaking: max amount limit exceed");

        lockInfo[_newLockType].totalStaked -= _user.amount;
        uint256 _increaseTime = _newLockType - _user.lockType;
        _user.unlockEnd += _increaseTime;
        _user.lockType = _newLockType;
        userInfo[msg.sender] = _user;

        _newlockInfo.totalStaked += _user.amount;
        lockInfo[_newLockType] = _newlockInfo;

        emit RollOverReward(msg.sender, _newLockType, _user.unlockEnd);
    }

    function withdrawRequest() external whenNotPaused {
        uint256 _lockType = userInfo[msg.sender].lockType;
        coolDownPeriod[msg.sender] = block.timestamp + lockInfo[_lockType].coolDownPeriod;
    }

    /// @notice Withdraw  token from pool and claim proceeds for transaction sender to `to`.
    /// @param _to Receiver of the LP tokens and syUSD rewards.
    function withdraw(address _to) external whenNotPaused {
        uint256 _coolDownPeriod = coolDownPeriod[msg.sender];
        require(_coolDownPeriod != 0, "SynthrStaking: request for withdraw");
        require(_coolDownPeriod + lockTime < block.timestamp, "SynthrStaking: lock time not end");
        PoolInfo memory _poolInfo = updatePool();
        UserInfo memory _user = userInfo[msg.sender];

        (
            int256 accumulatedReward,
            uint256 _pendingReward
        ) = _calAccumaltedAndPendingReward(
                _poolInfo.accRewardPerShare,
                _user.amount,
                _user.rewardDebt
            );

        // Effects
        _user.rewardDebt =
            accumulatedReward -
            (_calAccRewardPerShare(_poolInfo.accRewardPerShare, _user.amount));

        uint256 _amount = _user.amount;
        if (_user.unlockEnd > block.timestamp) {
            uint256 _lockType = _user.lockType;
            _amount = (_amount * (100 - lockInfo[_lockType].penalty)) / 100;
        }

        delete userInfo[msg.sender];
        coolDownPeriod[msg.sender] = 0;

        totalSupply -= _amount;

        // Interactions
        REWARD_TOKEN.safeTransfer(_to, _pendingReward + _amount);

        emit WithdrawAndClaim(msg.sender, _pendingReward);
    }

    function emergencyWithdraw() public whenNotPaused {
        UserInfo memory _user = userInfo[msg.sender];
        uint256 _amount = _user.amount;

        delete userInfo[msg.sender];

        totalSupply -= _amount;

        // Interactions
        REWARD_TOKEN.safeTransfer(msg.sender, _amount);

        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function _pendingRewardAmount(
        address _user,
        uint256 _blockNumber
    ) internal view returns (uint256 _pending) {
        uint256 _lpSupply = totalSupply;
        UserInfo memory _userInfo = userInfo[_user];
        PoolInfo memory _pool = poolInfo;
        uint256 _accRewardPerShare = _pool.accRewardPerShare;
        if (_blockNumber > _pool.lastRewardBlock && _lpSupply != 0) {
            uint256 _blocks = _blockNumber - (_pool.lastRewardBlock);
            uint256 _rewardAmount = (_blocks * _pool.rewardPerBlock);
            _accRewardPerShare += (_calAccPerShare(_rewardAmount, _lpSupply));
        }
        _pending = uint256(
            _calAccRewardPerShare(_accRewardPerShare, _userInfo.amount) -
                _userInfo.rewardDebt
        );
    }

    function _calAccPerShare(
        uint256 _rewardAmount,
        uint256 _lpSupply
    ) internal pure returns (uint256) {
        return (_rewardAmount * ACC_REWARD_PRECISION) / _lpSupply;
    }

    function _calAccRewardPerShare(
        uint256 _accRewardPerShare,
        uint256 _amount
    ) internal pure returns (int256) {
        return int256((_amount * _accRewardPerShare) / ACC_REWARD_PRECISION);
    }

    function _calAccumaltedAndPendingReward(
        uint256 _accRewardPerShare,
        uint256 _amount,
        int256 _rewardDebt
    )
        internal
        pure
        returns (int256 _accumulatedReward, uint256 _pendingReward)
    {
        _accumulatedReward = _calAccRewardPerShare(_accRewardPerShare, _amount);
        _pendingReward = uint256(_accumulatedReward - (_rewardDebt));
    }

}