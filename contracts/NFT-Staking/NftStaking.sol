// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISynthrNFT.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract NftStaking is IERC721Receiver, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 lockEnd;
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

    /// @notice Info of each pool.
    mapping(address => NFTPoolInfo) public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;

    event Deposit(address indexed pool, address indexed user, uint256 tokenId);
    event Withdraw(address indexed pool, address indexed user, uint256 tokenId);
    event Claimed(address indexed pool, address indexed user, uint256 pendingRewardAmount);
    event WithdrawAndClaim(address indexed pool, address indexed user, uint256 pendingRewardAmount);
    event LogPoolAddition(address indexed owner, address[] pool);
    event LogUpdatePool(address indexed pool, uint64 lastRewardBlock, uint256 accRewardPerShare);
    event EpochUpdated(address indexed owner, address[] pool, uint256[] rewardPerBlock);
    event totalLockAmountUpdated(address owner, uint256 totalLockAmount);

    constructor(address _admin, address _rewardToken) Ownable(_admin) {
        REWARD_TOKEN = IERC20(_rewardToken);
    }

    /// @dev retuen user reward debt
    /// @param _pool address of pool
    /// @param _user address of user
    function userRewardsDebt(address _pool, address _user) external view returns (int256) {
        return userInfo[_pool][_user].rewardDebt;
    }

    /// @notice View function to see pending reward of user in pool at current block.
    /// @param _pool The address of the pool. See `poolInfo`.
    /// @param _user Address of user.
    /// @return pending_ reward for a given user.
    function pendingReward(address _pool, address _user) external view returns (uint256 pending_) {
        pending_ = _pendingRewardAmount(_pool, _user, block.number);
    }

    /// @notice View function to see pending reward of user in pool at future block.
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

    /// @notice set total locked token for lpSupply
    function setTotalLockAmount(uint256 _totalLockAmount) external onlyOwner {
        totalLockAmount = _totalLockAmount;

        emit totalLockAmountUpdated(msg.sender, totalLockAmount);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /// @notice Add a new NFT pool. Can only be called by the owner.
    function addPool(address[] memory _pool) external onlyOwner {
        for (uint256 i; i < _pool.length; i++) {
            poolInfo[_pool[i]].exist = true;
            poolInfo[_pool[i]].lastRewardBlock = uint64(block.number);
        }

        emit LogPoolAddition(msg.sender, _pool);
    }

    /// @notice update epoch of pool
    /// @param _pool addresses of pool to be updated.
    /// @param _rewardPerBlock array of rewardPerBlock
    function updateEpoch(address _user, uint256 _rewardAmount, address[] memory _pool, uint256[] memory _rewardPerBlock)
        external
        onlyOwner
    {
        require(_rewardPerBlock.length == _pool.length, "NftStaking: length of array doesn't mach");

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
    function updatePool(address _pool) public returns (NFTPoolInfo memory _poolInfo) {
        _poolInfo = poolInfo[_pool];
        require(_poolInfo.exist, "NftStaking: pool not exist");
        uint256 _lpSupply = totalLockAmount;
        if (block.number > _poolInfo.lastRewardBlock) {
            if (_lpSupply > 0) {
                uint256 _blocks = block.number - _poolInfo.lastRewardBlock;
                uint256 _rewardAmount = (_blocks * _poolInfo.rewardPerBlock);
                _poolInfo.accRewardPerShare += _calAccPerShare(_rewardAmount, _lpSupply);
            }
            _poolInfo.lastRewardBlock = uint64(block.number);
            poolInfo[_pool] = _poolInfo;
            emit LogUpdatePool(_pool, _poolInfo.lastRewardBlock, _poolInfo.accRewardPerShare);
        }
    }

    /// @notice Deposit NFT token.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    function deposit(address _pool, uint256 _tokenId) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);

        UserInfo memory _user = userInfo[_pool][msg.sender];
        require(_user.tokenId == 0, "NftStaking: already exist");
        (uint256 _lockAmount, uint256 _lockEndBlockNumber) = ISynthrNFT(_pool).getuserData(_tokenId);

        // Effects
        int256 _calRewardDebt = _calAccRewardPerShare(_poolInfo.accRewardPerShare, _lockAmount);

        _user.amount += _lockAmount;
        _user.rewardDebt += _calRewardDebt;
        _user.lockEnd = _lockEndBlockNumber;
        _user.tokenId = _tokenId;

        userInfo[_pool][msg.sender] = _user;

        ISynthrNFT(_pool).safeTransferFrom(msg.sender, address(this), _tokenId);

        emit Deposit(_pool, msg.sender, _tokenId);
    }

    function withdraw(address _pool) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

       (uint256 _lockAmount,) = ISynthrNFT(_pool).getuserData(_user.tokenId);
        int256 _calRewardDebt = _calAccRewardPerShare(_poolInfo.accRewardPerShare, _lockAmount);

        _user.amount -= _lockAmount;
        _user.rewardDebt -= _calRewardDebt;

        userInfo[_pool][msg.sender] = _user;

        // Interactions
        ISynthrNFT(_pool).transferFrom(address(this), msg.sender, _user.tokenId);

        emit Withdraw(_pool, msg.sender, _user.tokenId);
    }

    /// @notice Claim proceeds for transaction sender to `to`.
    /// @param _pool The address of the pool. See `NFTPoolInfo`.
    /// @param _to Receiver rewards.
    function claim(address _pool, address _to) external {
        NFTPoolInfo memory _poolInfo = updatePool(_pool);
        UserInfo memory _user = userInfo[_pool][msg.sender];

        int256 accumulatedReward = _calAccRewardPerShare(_poolInfo.accRewardPerShare, _user.amount);
        uint256 _pendingReward = uint256(accumulatedReward - _user.rewardDebt);
        uint256 _exccessReward = _calculateExcessRewardAtBlock(_user.lockEnd, _user.amount, _poolInfo.rewardPerBlock, block.number);
        if (_pendingReward < _exccessReward) {
            _pendingReward -= _exccessReward;
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

        (uint256 _lockAmount,) = ISynthrNFT(_pool).getuserData(_user.tokenId);

        int256 accumulatedReward = _calAccRewardPerShare(_poolInfo.accRewardPerShare, _user.amount);
        uint256 _pendingReward = uint256(accumulatedReward - (_user.rewardDebt));
        uint256 _exccessReward = _calculateExcessRewardAtBlock(_user.lockEnd, _user.amount, _poolInfo.rewardPerBlock, block.number);

        if (_pendingReward < _exccessReward) {
            _pendingReward -= _exccessReward;
        }

        // Effects
        _user.rewardDebt = accumulatedReward - (_calAccRewardPerShare(_poolInfo.accRewardPerShare, _lockAmount));
        _user.amount -= _lockAmount;
        userInfo[_pool][msg.sender] = _user;

        // Interactions
        if (_pendingReward != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingReward);
        }

        ISynthrNFT(_pool).transferFrom(address(this), msg.sender, _user.tokenId);

        emit WithdrawAndClaim(_pool, msg.sender, _pendingReward);
    }

    function _pendingRewardAmount(address _pool, address _user, uint256 _blockNumber)
        internal
        view
        returns (uint256 _pending)
    {
        uint256 _lpSupply = totalLockAmount;
        NFTPoolInfo memory _poolInfo = poolInfo[_pool];
        UserInfo memory _userInfo = userInfo[_pool][_user];
        uint256 _accRewardPerShare = _poolInfo.accRewardPerShare;
        if (_blockNumber > _poolInfo.lastRewardBlock && _lpSupply != 0) {
            uint256 _blocks = _blockNumber - (_poolInfo.lastRewardBlock);
            uint256 _rewardAmount = (_blocks * _poolInfo.rewardPerBlock);
            _accRewardPerShare += (_calAccPerShare(_rewardAmount, _lpSupply));
        }
        _pending = uint256(_calAccRewardPerShare(_accRewardPerShare, _userInfo.amount) - _userInfo.rewardDebt);
        uint256 _excessReward = _calculateExcessRewardAtBlock(_userInfo.lockEnd, _userInfo.amount, _poolInfo.rewardPerBlock, _blockNumber);
        if (_pending < _excessReward) return 0;
        _pending -= _excessReward;
    }

    function _calAccPerShare(uint256 _rewardAmount, uint256 _lpSupply) internal pure returns (uint256) {
        return (_rewardAmount * ACC_REWARD_PRECISION) / _lpSupply;
    }

    function _calAccRewardPerShare(uint256 _accRewardPerShare, uint256 _amount) internal pure returns (int256) {
        return int256((_amount * _accRewardPerShare) / ACC_REWARD_PRECISION);
    }

    function _calculateExcessRewardAtBlock(uint256 _LockblockNum, uint256 _amount, uint256 _rewardPerBlock, uint256 _currentBlock) internal view returns(uint256) {
        uint256 _lpSupply = totalLockAmount;
        uint256 _accShare;
        if (_currentBlock > _LockblockNum) {
            if (_lpSupply > 0) {
                uint256 _blocks = _currentBlock - _LockblockNum;
                uint256 _rewardAmount = (_blocks * _rewardPerBlock);
                _accShare = _calAccPerShare(_rewardAmount, _lpSupply);
            }
        }

        return uint256(_calAccRewardPerShare(_accShare, _amount));
    }
}
