// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../interfaces/ISynthrNFT.sol";
import "../interfaces/ISynthrStaking.sol";

contract NftStaking is IERC721Receiver, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 tokenId;
        int256 rewardDebt;
    }

    /// @notice Info of each gauge pool.
    struct NFTPoolInfo {
        bool exist;
        uint64 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 rewardPerBlock;
        uint256 currentEpoch;
        uint256 epoch;
    }

    uint256 public stakeAmount = 1000 * 1e18;
    uint256 public secondPerBlock = 12;

    /// @notice Total lock amount of users in VotingEscrow
    uint256 public totalLockAmount;

    /// @notice synthr staking instance
    ISynthrStaking public synthrStaking;

    /// @notice Info of each pool.
    mapping(address => NFTPoolInfo) public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed pool, address indexed user, uint256 tokenId);
    event IncreaseDeposit(address indexed pool, address indexed user, uint256 amount);
    event Withdraw(address indexed pool, address indexed user, uint256 tokenId);
    event Claimed(
        address indexed pool,
        address indexed user,
        uint256 pendingRewardAmount
    );
    event WithdrawAndClaim(
        address indexed pool,
        address indexed user,
        uint256 pendingRewardAmount
    );
    event WithdrawPendingRewardAmount(
        address indexed pool,
        address indexed user,
        uint256 pendingRewardAmount
    );
    event LogPoolAddition(address indexed owner, address[] pool);
    event LogUpdatePool(
        address indexed pool,
        uint64 lastRewardBlock,
        uint256 accRewardPerShare
    );
    event EpochUpdated(
        address indexed owner,
        address[] pool,
        uint256[] rewardPerBlock
    );
    event totalLockAmountUpdated(address owner, uint256 totalLockAmount);
    event LogUpdatedStakeAmount(address owner, uint256 stakeAmount);

    constructor(address _admin, address _rewardToken, address _synthrStaking) Ownable(_admin) {
        REWARD_TOKEN = IERC20(_rewardToken);
        synthrStaking = ISynthrStaking(_synthrStaking);
    }

    /// @dev retuen user reward debt
    /// @param _pool address of pool
    /// @param _user address of user
    function userRewardsDebt(
        address _pool,
        address _user
    ) external view returns (int256) {
        return userInfo[_pool][_user].rewardDebt;
    }

    /// @notice View function to see pending reward of user in pool at current block.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(
        address _pool,
        address _user
    ) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_pool, _user, block.number);
    }

    /// @notice View function to see pending reward of user in pool at future block.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingRewardAtBlock(
        address _pool,
        address _user,
        uint256 _blockNumber
    ) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_pool, _user, _blockNumber);
    }

    /// @notice set total locked token for lpSupply
    function setTotalLockAmount(
        uint256 _totalLockAmount
    ) external onlyOwner {
        totalLockAmount = _totalLockAmount;

        emit totalLockAmountUpdated(msg.sender, totalLockAmount);
    }

    function setSecondPerBlock(
        uint256 _secondPerBlock
    ) external onlyOwner {
        secondPerBlock = _secondPerBlock;

        emit totalLockAmountUpdated(msg.sender, totalLockAmount);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function setStakeAmount(uint256 _stakeAmount) external onlyOwner {
        stakeAmount = _stakeAmount;
        emit LogUpdatedStakeAmount(msg.sender, stakeAmount);
    }

    /// @notice Add a new NFT pool. Can only be called by the owner.
    function addPool(
        address[] memory _pool
    ) external onlyOwner {
        for (uint256 i; i < _pool.length; i++) {
            poolInfo[_pool[i]].exist = true;
            poolInfo[_pool[i]].lastRewardBlock = uint64(block.number);
        }

        emit LogPoolAddition(msg.sender, _pool);
    }

    /// @notice update epoch of pool
    /// @param _pool addresses of pool to be updated.
    /// @param _rewardPerBlock array of rewardPerBlock
    function updateEpoch(
        address _user,
        uint256 _rewardAmount,
        address[] memory _pool,
        uint256[] memory _rewardPerBlock
    ) external onlyOwner {
        require(
            _rewardPerBlock.length == _pool.length,
            "NftStaking: length of array doesn't mach"
        );

        for (uint256 i; i < _pool.length; i++) {
            NFTPoolInfo memory _poolInfo = poolInfo[_pool[i]];
            require(_poolInfo.exist, "NftStaking: pool not exist");
            _poolInfo.rewardPerBlock = _rewardPerBlock[i];
            _poolInfo.lastRewardBlock = uint64(block.number);
            ++_poolInfo.epoch;
            poolInfo[_pool[i]] = _poolInfo;
        }

        REWARD_TOKEN.safeTransferFrom(_user, address(this), _rewardAmount);

        emit EpochUpdated(msg.sender, _pool, _rewardPerBlock);
    }

    /// @notice Update reward variables of the given pool.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    /// @return _poolInfo Returns the pool that was updated.
    function updatePool(
        address _pool
    ) public returns (NFTPoolInfo memory _poolInfo) {
        _poolInfo = poolInfo[_pool];
        require(_poolInfo.exist, "NftStaking: pool not exist");
        uint256 _lpSupply = totalLockAmount;
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
            poolInfo[_pool] = _poolInfo;
            emit LogUpdatePool(
                _pool,
                _poolInfo.lastRewardBlock,
                _poolInfo.accRewardPerShare
            );
        }
    }

    /// @notice Deposit NFT token.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    function deposit(address _pool, uint256 _tokenId) external {
        uint256 _amount = _checkStakeAmountAndLockEnd();

        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(_user.tokenId == 0, "NftStaking: already exist");

        NFTPoolInfo memory _poolInfo = updatePool(_pool);

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _amount
        );

        _user.amount = _amount;
        _user.rewardDebt += _calRewardDebt;
        _user.tokenId = _tokenId;

        userInfo[_pool][msg.sender] = _user;

        ISynthrNFT(_pool).safeTransferFrom(msg.sender, address(this), _tokenId);

        emit Deposit(_pool, msg.sender, _tokenId);
    }

    function increaseDeposit(address _pool) external {
        uint256 _amount = _checkStakeAmountAndLockEnd();

        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(_user.tokenId != 0, "NftStaking: token not deposit");

        NFTPoolInfo memory _poolInfo = updatePool(_pool);

        uint256 _updatedAmount = _amount - _user.amount;

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _updatedAmount
        );

        _user.amount = _amount;
        _user.rewardDebt += _calRewardDebt;

        userInfo[_pool][msg.sender] = _user;

        emit IncreaseDeposit(_pool, msg.sender, _updatedAmount);
    }

    function withdraw(address _pool) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _user.amount
        );

        uint256 _tokenId = _user.tokenId;

        _user.amount = 0;
        _user.rewardDebt -= _calRewardDebt;
        _user.tokenId = 0;

        userInfo[_pool][msg.sender] = _user;

        // Interactions
        ISynthrNFT(_pool).transferFrom(
            address(this),
            msg.sender,
            _tokenId
        );

        emit Withdraw(_pool, msg.sender, _tokenId);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    /// @param _to Receiver rewards.
    function claim(address _pool, address _to) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

        (
            int256 accumulatedReward,
            uint256 _pendingReward
        ) = _calAccumaltedAndPendingReward(
                _poolInfo.accRewardPerShare,
                _user.amount,
                _user.rewardDebt
            );

        uint256 _excessReward = _calculateExcessReward(msg.sender, _user.amount, _poolInfo.rewardPerBlock);
        if (_pendingReward < _excessReward) {
            _pendingReward = 0;
        } else {
            _pendingReward -= _excessReward;
        }

        // Effects
        _user.rewardDebt = accumulatedReward;
        userInfo[_pool][msg.sender] = _user;

        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingReward);
        }

        emit Claimed(msg.sender, _pool, _pendingReward);
    }

    /// @notice Withdraw NFT token from pool and claim proceeds for transaction sender to `to`.
    /// @param _pool address of the pool. See `NFTPoolInfo`.
    /// @param _to Receiver of the LP tokens and syUSD rewards.
    function withdrawAndClaim(address _pool, address _to) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

        (
            ,
            uint256 _pendingReward
        ) = _calAccumaltedAndPendingReward(
                _poolInfo.accRewardPerShare,
                _user.amount,
                _user.rewardDebt
            );

        uint256 _excessReward = _calculateExcessReward(msg.sender, _user.amount, _poolInfo.rewardPerBlock);
        if (_pendingReward < _excessReward) {
            _pendingReward = 0;
        } else {
            _pendingReward -= _excessReward;
        }

        // Effects
        uint256 _tokenId = _user.tokenId;
        delete userInfo[_pool][msg.sender];

        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingReward);
        }

        ISynthrNFT(_pool).transferFrom(
            address(this),
            msg.sender,
            _tokenId
        );

        emit WithdrawAndClaim(_pool, msg.sender, _pendingReward);
    }

    function _pendingRewardAmount(
        address _pool,
        address _user,
        uint256 _blockNumber
    ) internal view returns (uint256 _pending) {
        uint256 _lpSupply = totalLockAmount;
        NFTPoolInfo memory _poolInfo = poolInfo[_pool];
        UserInfo memory _userInfo = userInfo[_pool][_user];
        uint256 _accRewardPerShare = _poolInfo.accRewardPerShare;
        if (_blockNumber > _poolInfo.lastRewardBlock && _lpSupply != 0) {
            uint256 _blocks = _blockNumber - (_poolInfo.lastRewardBlock);
            uint256 _rewardAmount = (_blocks * _poolInfo.rewardPerBlock);
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

    function _checkStakeAmountAndLockEnd() internal view returns(uint256) {
        ISynthrStaking.UserInfo memory _userInfo = synthrStaking.userInfo(msg.sender);
        require(_userInfo.amount >= stakeAmount, "NftStaking: low amount staked");
        require(_userInfo.unlockEnd > block.timestamp, "NftStaking: lock time expired");

        return _userInfo.amount;
    }

    function _calculateExcessReward(address _user, uint256 _amount, uint256 _rewardPerBlock) internal view returns(uint256 _excessReward) {
        uint256 _lockEndTime = (synthrStaking.userInfo(_user)).unlockEnd;
        uint256 _rewardAmount = ((block.timestamp - _lockEndTime) / secondPerBlock) * _rewardPerBlock;
        uint256 _accPerShare = _calAccPerShare(_rewardAmount, totalLockAmount); 
        _excessReward = uint256(_calAccRewardPerShare(_accPerShare, _amount));
    }
}
