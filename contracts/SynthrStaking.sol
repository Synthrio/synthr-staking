// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract SynthrStaking is Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    /// @notice Address of reward token contract.
    IERC20 public immutable SYNTH;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Info of each user.
    /// `amount` SYNTH token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 lockType;
        uint256 unlockEnd;
        int256 rewardDebt;
    }

    struct LockInfo {
        bool exist;
        uint64 lastRewardBlock;
        uint256 maxPoolSize;
        uint256 penalty;
        uint256 coolDownPeriod;
        uint256 totalStaked;
        uint256 rewardPerBlock;
        uint256 accRewardPerShare;
        uint256 epoch;
    }

    bool public killed;
    bool public emergencyWithdrawAllowed;

    /// @notice Total lock amount of users
    uint256 public totalSupply;

    uint256 public penaltyAmount;

    /// @notice Info of each user that stakes SYNTH tokens.
    mapping(address => UserInfo) public userInfo;

    mapping(address => uint256) public coolDownPeriod;

    mapping(uint256 => LockInfo) public lockInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, address indexed to, uint256 amount);
    event Claimed(address indexed user, address indexed to, uint256 pendingRewardAmount);
    event LogUpdatePool(uint64 lastRewardBlock, uint256 accRewardPerShare);
    event EpochUpdated(address indexed owner, uint256[] lockType, uint256[] rewardPerBlock);
    event EmergencyWithdraw(address indexed user, uint256 amount);
    event PoolAlived(address indexed owner, bool _alive);
    event KillPool(address indexed owner, bool _killed);
    event RecoveredToken(address indexed owner, address indexed token, uint256 amount);
    event WithdrawPenalty(address indexed owner, address indexed to, uint256 penaltyAmount);
    event ToggleEmergencyWithdraw(address indexed owner, bool emergencyWithdrawAllowed);

    constructor(address _admin, address _SYNTH, uint256[] memory _lockType, LockInfo[] memory _lockInfo)
        Ownable(_admin)
    {
        require(_lockInfo.length == _lockType.length, "SynthrStaking: length not equal");
        require(_SYNTH != address(0), "SynthrStaking: Address Zero Found");
        SYNTH = IERC20(_SYNTH);

        for (uint256 i; i < _lockType.length; ++i) {
            lockInfo[_lockType[i]] = _lockInfo[i];
        }
    }

    modifier isAlive() {
        require(!killed, "SynthrStaking: pool is killed");
        _;
    }

    /// @dev return user reward debt
    /// @param _user address of user
    function userRewardsDebt(address _user) external view returns (int256) {
        return userInfo[_user].rewardDebt;
    }

    /// @notice View function to see pending reward of user in pool at current block.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(address _user) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_user, block.number);
    }

    /// @notice View function to see pending reward of user at future block.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingRewardAtBlock(address _user, uint256 _blockNumber) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_user, _blockNumber);
    }

    /**
     * @dev pause pool to restrict pool functionality, can only be called by admin
     */
    function pausePool() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause pool, can only be called by admin
     */
    function unpausePool() external onlyOwner {
        _unpause();
    }

    /**
     * @dev kill pool to restrict pool functionality, can only be called by admin
     */
    function killPool() external onlyOwner {
        killed = true;
        emit KillPool(msg.sender, true);
    }

    /**
     * @dev revive pool, can only be called by admin
     */
    function revivePool() external onlyOwner {
        killed = false;
        emit PoolAlived(msg.sender, false);
    }

    function setLockInfo(uint256 _lockType, uint256 _maxPoolSize, uint256 _penalty, uint256 _coolDownPeriod)
        external
        onlyOwner
    {
        require(_penalty <= 100, "SynthrStaking: Penalty percentage greater than 100");
        LockInfo memory _lockInfo = lockInfo[_lockType];
        _lockInfo.coolDownPeriod = _coolDownPeriod;
        _lockInfo.maxPoolSize = _maxPoolSize;
        _lockInfo.penalty = _penalty;
        _lockInfo.exist = true;

        lockInfo[_lockType] = _lockInfo;
    }

    function toggleEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawAllowed = !emergencyWithdrawAllowed;

        emit ToggleEmergencyWithdraw(msg.sender, emergencyWithdrawAllowed);
    }

    /// @notice update epoch of pool
    function updateEpoch(
        uint256 _rewardAmount,
        uint256[] memory _rewardPerBlock,
        uint256[] memory _lockType
    ) external whenNotPaused isAlive onlyOwner {
        require(_rewardPerBlock.length == _lockType.length, "SynthrStaking: length not equal");

        for (uint256 i; i < _rewardPerBlock.length; ++i) {
            LockInfo memory _lockInfo = lockInfo[_lockType[i]];
            _lockInfo.rewardPerBlock = _rewardPerBlock[i];
            ++_lockInfo.epoch;

            lockInfo[_lockType[i]] = _lockInfo;
        }

        SYNTH.safeTransferFrom(msg.sender, address(this), _rewardAmount);
        emit EpochUpdated(msg.sender, _lockType, _rewardPerBlock);
    }

    /// @notice Deposit token.
    function deposit(uint256 _amount, uint256 _lockType) external whenNotPaused isAlive {
        LockInfo memory _lockInfo = _updatePool(_lockType);

        require(_lockInfo.totalStaked + _amount <= _lockInfo.maxPoolSize, "SynthrStaking: max amount limit exceed");

        UserInfo memory _user = userInfo[msg.sender];
        require(_user.unlockEnd == 0 || _user.unlockEnd > block.timestamp, "SynthrStaking: withdraw locked token");

        require(_user.lockType == 0 || _user.lockType == _lockType, "SynthrStaking: lock type differ");

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(_lockInfo.accRewardPerShare, _amount);

        if (_user.amount == 0) {
            _user.unlockEnd = block.timestamp + _lockType;
            _user.lockType = _lockType;
        }
        _user.amount += _amount;
        _user.rewardDebt += _calRewardDebt;

        userInfo[msg.sender] = _user;

        totalSupply += _amount;
        _lockInfo.totalStaked += _amount;
        lockInfo[_lockType] = _lockInfo;

        SYNTH.safeTransferFrom(msg.sender, address(this), _amount);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _to Receiver rewards.
    function claim(address _to) external whenNotPaused {
        UserInfo memory _user = userInfo[msg.sender];
        require(_user.unlockEnd < block.timestamp, "SynthrStaking: claim after lock end");
        LockInfo memory _lockInfo = _updatePool(_user.lockType);

        (int256 accumulatedReward, uint256 _pendingReward) =
            _calAccumulatedAndPendingReward(_lockInfo.accRewardPerShare, _user.amount, _user.rewardDebt);

        // Effects
        lockInfo[_user.lockType] = _lockInfo;
        _user.rewardDebt = accumulatedReward;
        userInfo[msg.sender] = _user;

        // Interactions
        if (_pendingReward != 0) {
            SYNTH.safeTransfer(_to, _pendingReward);
        }

        emit Claimed(msg.sender, _to, _pendingReward);
    }

    function withdrawRequest() external whenNotPaused {
        uint256 _lockType = userInfo[msg.sender].lockType;
        coolDownPeriod[msg.sender] = block.timestamp + lockInfo[_lockType].coolDownPeriod;
    }

    /// @notice Withdraw  token from pool and claim proceeds for transaction sender to `to`.
    /// @param _to Receiver of the SYNTH tokens with pending reward(in SYNTHs).
    function withdraw(address _to) external whenNotPaused {
        uint256 _coolDownPeriod = coolDownPeriod[msg.sender];
        require(_coolDownPeriod != 0, "SynthrStaking: request for withdraw");
        require(_coolDownPeriod < block.timestamp, "SynthrStaking: lock time not end");
        UserInfo memory _user = userInfo[msg.sender];
        LockInfo memory _lockInfo = _updatePool(_user.lockType);

        (, uint256 _pendingReward) =
            _calAccumulatedAndPendingReward(_lockInfo.accRewardPerShare, _user.amount, _user.rewardDebt);

        uint256 _amount = _user.amount;
        totalSupply -= _amount;
        _lockInfo.totalStaked -= _amount;
        if (_user.unlockEnd > block.timestamp) {
            uint256 _lockType = _user.lockType;
            _amount = (_amount * (100 - lockInfo[_lockType].penalty)) / 100;
            penaltyAmount += _user.amount - _amount;
        }

        lockInfo[_user.lockType] = _lockInfo;
        delete userInfo[msg.sender];
        coolDownPeriod[msg.sender] = 0;

        // Interactions
        SYNTH.safeTransfer(_to, _pendingReward + _amount);

        emit Withdraw(msg.sender, _to, _pendingReward + _amount);
    }

    function emergencyWithdraw() public whenNotPaused {
        require(emergencyWithdrawAllowed, "SynthrStaking: emergency withdraw not allowed");
        UserInfo memory _user = userInfo[msg.sender];
        uint256 _amount = _user.amount;
        require(_amount > 0, "SynthrStaking: Amount should be non zero");

        LockInfo memory _lockInfo = lockInfo[_user.lockType];
        _lockInfo.totalStaked -= _amount;
        lockInfo[_user.lockType] = _lockInfo;
        delete userInfo[msg.sender];

        totalSupply -= _amount;

        // Interactions
        SYNTH.safeTransfer(msg.sender, _amount);

        emit EmergencyWithdraw(msg.sender, _amount);
    }

    function recoverToken(address _token, address _to, uint256 _amount) external onlyOwner whenNotPaused {
        if (_token == address(SYNTH)) {
            require(
                IERC20(_token).balanceOf(address(this)) - _amount >= totalSupply,
                "SynthrStaking: can not withdraw user token"
            );
        }
        IERC20(_token).safeTransfer(_to, _amount);

        emit RecoveredToken(msg.sender, _token, _amount);
    }

    function withdrawPenalty(address _to) external onlyOwner whenNotPaused {
        uint256 oldPenaltyAmount = penaltyAmount;
        penaltyAmount = 0;
        emit WithdrawPenalty(msg.sender, _to, oldPenaltyAmount);
        SYNTH.safeTransfer(_to, oldPenaltyAmount);
    }

    /// @notice Update reward variables of the pool.
    function _updatePool(uint256 _lockType) public returns (LockInfo memory _lockInfo) {
        _lockInfo = lockInfo[_lockType];
        require(_lockInfo.exist, "SynthrStaking: lock type not exist");
        uint256 _lpSupply = totalSupply;
        if (block.number > _lockInfo.lastRewardBlock) {
            if (_lpSupply > 0) {
                uint256 _blocks = block.number - _lockInfo.lastRewardBlock;
                uint256 _rewardAmount = (_blocks * _lockInfo.rewardPerBlock);
                _lockInfo.accRewardPerShare += _calAccPerShare(_rewardAmount, _lpSupply);
            }
            _lockInfo.lastRewardBlock = uint64(block.number);

            emit LogUpdatePool(_lockInfo.lastRewardBlock, _lockInfo.accRewardPerShare);
        }
    }

    function _pendingRewardAmount(address _user, uint256 _blockNumber) internal view returns (uint256 _pending) {
        uint256 _lpSupply = totalSupply;
        UserInfo memory _userInfo = userInfo[_user];
        LockInfo memory _lockInfo = lockInfo[_userInfo.lockType];
        uint256 _accRewardPerShare = _lockInfo.accRewardPerShare;
        if (_blockNumber > _lockInfo.lastRewardBlock && _lpSupply != 0) {
            uint256 _blocks = _blockNumber - (_lockInfo.lastRewardBlock);
            uint256 _rewardAmount = (_blocks * _lockInfo.rewardPerBlock);
            _accRewardPerShare += (_calAccPerShare(_rewardAmount, _lpSupply));
        }
        _pending = uint256(_calAccRewardPerShare(_accRewardPerShare, _userInfo.amount) - _userInfo.rewardDebt);
    }

    function _calAccPerShare(uint256 _rewardAmount, uint256 _lpSupply) internal pure returns (uint256) {
        return (_rewardAmount * ACC_REWARD_PRECISION) / _lpSupply;
    }

    function _calAccRewardPerShare(uint256 _accRewardPerShare, uint256 _amount) internal pure returns (int256) {
        return int256((_amount * _accRewardPerShare) / ACC_REWARD_PRECISION);
    }

    function _calAccumulatedAndPendingReward(uint256 _accRewardPerShare, uint256 _amount, int256 _rewardDebt)
        internal
        pure
        returns (int256 _accumulatedReward, uint256 _pendingReward)
    {
        _accumulatedReward = _calAccRewardPerShare(_accRewardPerShare, _amount);
        _pendingReward = uint256(_accumulatedReward - (_rewardDebt));
    }
}
