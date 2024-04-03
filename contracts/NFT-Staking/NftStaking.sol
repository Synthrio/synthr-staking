// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISynthrNFT.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../interfaces/IVotingEscrow.sol";

contract NftStaking is IERC721Receiver, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
    bytes32 public constant PAUSE_ROLE = keccak256("PAUSE_ROLE");

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        bool isPause;
        uint256 amount;
        uint256 pendingReward;
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

    /// @notice Total lock amount of users in VotingEscrow
    uint256 public totalLockAmount;

    /// @notice voting escrow instance
    IVotingEscrow public votingEscrow;

    /// @notice Info of each pool.
    mapping(address => NFTPoolInfo) public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    /// @notice token id of user has deposited in pool.
    mapping(address => mapping(uint256 => address)) public tokenOwner;

    event Deposit(address indexed pool, address indexed user, uint256 tokenId);
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
    event withdrawPendingRewardAmount(
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

    constructor(address _admin, address _rewardToken, address _votingEscrow) {
        REWARD_TOKEN = IERC20(_rewardToken);
        votingEscrow = IVotingEscrow(_votingEscrow);
        _grantRole(CONTROLLER_ROLE, _admin);
        _setRoleAdmin(CONTROLLER_ROLE, CONTROLLER_ROLE);
        _setRoleAdmin(CONTROLLER_ROLE, PAUSE_ROLE);
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

    function pauseUserReward(
        address _pool,
        address[] memory _users
    ) external onlyRole(PAUSE_ROLE) {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        for (uint256 i; i < _users.length; i++) {
            UserInfo memory _userInfo = userInfo[_pool][_users[i]];
            (
                int256 accumulatedReward,
                uint256 _pendingReward
            ) = _calAccumaltedAndPendingReward(
                    _poolInfo.accRewardPerShare,
                    _userInfo.amount,
                    _userInfo.rewardDebt
                );

            _userInfo.rewardDebt = accumulatedReward;
            userInfo[_pool][msg.sender] = _userInfo;

            _userInfo.isPause = true;
            _userInfo.pendingReward += _pendingReward;
            userInfo[_pool][_users[i]] = _userInfo;
        }
    }

    function unpuaseReward(address _pool) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);

        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(_user.isPause, "NftStaking: user is not paused");
        require(_user.tokenId != 0, "NftStaking: token id not deposited");
        require(votingEscrow.lockedEnd(msg.sender) > block.timestamp, "NftStaking: lock time expired");

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _user.amount
        );

        _user.rewardDebt += _calRewardDebt;
        _user.isPause = false;

        userInfo[_pool][msg.sender] = _user;
    }

    function withdrawPendingReward(address _pool) external {
        UserInfo memory _userInfo = userInfo[_pool][msg.sender];
        uint256 _pendingAmount = _userInfo.pendingReward;
        if (_pendingAmount != 0) {
            REWARD_TOKEN.safeTransfer(msg.sender, _pendingAmount);
        }

        _userInfo.pendingReward = 0;
        userInfo[_pool][msg.sender] = _userInfo;

        emit withdrawPendingRewardAmount(_pool, msg.sender, _pendingAmount);
    }

    /// @notice set total locked token for lpSupply
    function setTotalLockAmount(
        uint256 _totalLockAmount
    ) external onlyRole(CONTROLLER_ROLE) {
        totalLockAmount = _totalLockAmount;

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

    /// @notice Add a new NFT pool. Can only be called by the owner.
    function addPool(
        address[] memory _pool
    ) external onlyRole(CONTROLLER_ROLE) {
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
    ) external onlyRole(CONTROLLER_ROLE) {
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
        NFTPoolInfo memory _poolInfo = updatePool(_pool);

        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(_user.tokenId == 0, "NftStaking: already exist");
        (uint256 _lockAmount, ) = ISynthrNFT(_pool).getuserData(_tokenId);

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _lockAmount
        );

        _user.amount += _lockAmount;
        _user.rewardDebt += _calRewardDebt;
        _user.isPause = false;

        userInfo[_pool][msg.sender] = _user;

        ISynthrNFT(_pool).safeTransferFrom(msg.sender, address(this), _tokenId);

        emit Deposit(_pool, msg.sender, _tokenId);
    }

    function withdraw(address _pool) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

        (uint256 _lockAmount, ) = ISynthrNFT(_pool).getuserData(_user.tokenId);
        int256 _calRewardDebt = _calAccRewardPerShare(
            _poolInfo.accRewardPerShare,
            _lockAmount
        );

        _user.amount -= _lockAmount;
        _user.rewardDebt -= _calRewardDebt;

        userInfo[_pool][msg.sender] = _user;

        // Interactions
        ISynthrNFT(_pool).transferFrom(
            address(this),
            msg.sender,
            _user.tokenId
        );

        emit Withdraw(_pool, msg.sender, _user.tokenId);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    /// @param _to Receiver rewards.
    function claim(address _pool, address _to) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(!_user.isPause, "NftStaking: reward paused");

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
        require(!_user.isPause, "NftStaking: reward paused");

        (uint256 _lockAmount, ) = ISynthrNFT(_pool).getuserData(_user.tokenId);

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
            (_calAccRewardPerShare(_poolInfo.accRewardPerShare, _lockAmount));
        _user.amount -= _lockAmount;
        userInfo[_pool][msg.sender] = _user;

        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingReward);
        }

        ISynthrNFT(_pool).transferFrom(
            address(this),
            msg.sender,
            _user.tokenId
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
}
