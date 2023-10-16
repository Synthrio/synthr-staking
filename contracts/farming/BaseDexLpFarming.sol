// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @notice The (older) DexLpFarming contract gives out a constant number of REWARD_TOKEN tokens per block.
contract BaseDexLpFarming is Ownable2Step {
    using SafeERC20 for IERC20;

    uint256 public constant ACC_REWARD_PRECISION = 1e18;

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Info of each DexLpFarming user.
    /// `amount` Liquidity amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each DexLpFarming pool.
    /// `lastRewardBlock` The last pool updated timestamp.
    /// `rewardPerBlock` The total amount of reward to distribute.
    /// Also known as the amount of reward token to distribute per block.
    /// `accRewardPerShare` reward per liquidity amount
    struct PoolInfo {
        uint64 lastRewardBlock;
        uint128 accRewardPerShare;
        uint256 rewardPerBlock;
        uint256 currentEpoch;
    }

    /// @notice Info of each DexLpFarming pool.
    PoolInfo public pool;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    /// @notice amount of token id of user has deposited in pool.
    mapping(address => mapping(uint256 => uint256)) public userTokenAmount;

    event Deposit(address indexed user, uint256 tokenId);
    event Withdraw(address indexed user, uint256 tokenId);
    event DepositBatch(address indexed user, uint256[] tokenId);
    event WithdrawBatch(address indexed user, uint256[] tokenId);
    event WithdrawAndHarvest(
        address indexed user,
        uint256 tokenId,
        uint256 amount
    );
    event WithdrawAndHarvestBatch(
        address indexed user,
        uint256[] tokenId,
        uint256 amount
    );
    event Harvest(address indexed user, uint256 amount);

    event LogUpdatePool(
        uint64 lastRewardBlock,
        uint256 lpSupply,
        uint256 accRewardPerShare
    );

    event LogRewardPerBlock(
        uint256 rewardPerBlock,
        uint256 indexed currentEpoch,
        uint256 amount
    );

    /// @param _rewardToken The REWARD token contract address.
    constructor(IERC20 _rewardToken) {
        REWARD_TOKEN = _rewardToken;
    }

    /// @notice Returns if token id deposited by user.
    /// @param _user depositer address
    /// @param _tokenId deposited token id
    function isTokenDeposited(
        address _user,
        uint256 _tokenId
    ) external view returns (bool) {
        if (userTokenAmount[_user][_tokenId] != 0) {
            return true;
        }
        return false;
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerBlock The amount of reward token to be distributed per block number.
    /// @param _amount The amount of reward token to be deposit in dexLpFarmin.
    /// @param _user address from which reward is to be distributed.
    function setRewardPerBlock(
        uint256 _rewardPerBlock,
        uint256 _amount,
        address _user
    ) external onlyOwner {
        PoolInfo memory _pool = pool;
        _pool.rewardPerBlock = _rewardPerBlock;
        ++_pool.currentEpoch;
        pool = _pool;

        REWARD_TOKEN.safeTransferFrom(_user, address(this), _amount);

        emit LogRewardPerBlock(_rewardPerBlock, _pool.currentEpoch, _amount);
    }

    function _pendingReward(
        address _user,
        uint256 _lpSupply
    ) internal view returns (uint256 _pending) {
        PoolInfo memory _pool = pool;
        UserInfo memory user = userInfo[_user];
        uint256 _accRewardPerShare = _pool.accRewardPerShare;
        if (block.number > _pool.lastRewardBlock && _lpSupply != 0) {
            uint256 _blocks = block.number - (_pool.lastRewardBlock);
            uint256 _rewardAmount = (_blocks * _pool.rewardPerBlock);
            _accRewardPerShare += (_calAccPerShare(_rewardAmount, _lpSupply));
        }
        _pending = uint256(
            int256(_calAccumulatedReward(user.amount, _accRewardPerShare)) -
                user.rewardDebt
        );
    }

    function _harvest(uint256 _accRewardPerShare, address _to) internal {
        UserInfo memory _user = userInfo[msg.sender];
        int256 accumulatedReward = int256(
            _calAccumulatedReward(_user.amount, _accRewardPerShare)
        );
        uint256 _pendingRewardAmount = uint256(
            accumulatedReward - _user.rewardDebt
        );

        // Effects
        _user.rewardDebt = accumulatedReward;
        userInfo[msg.sender] = _user;
        // Interactions
        if (_pendingRewardAmount != 0) {
            REWARD_TOKEN.safeTransfer(_to, _pendingRewardAmount);
        }

        emit Harvest(msg.sender, _pendingRewardAmount);
    }

    function _withdrawAndHarvest(
        uint256 _tokenId,
        uint256 _liquidity,
        uint256 _accRewardPerShare,
        UserInfo memory _user,
        address _to
    ) internal returns (uint256) {
        int256 accumulatedReward = int256(
            _calAccumulatedReward(_user.amount, _accRewardPerShare)
        );
        uint256 _pendingRewardAmount = uint256(
            accumulatedReward - _user.rewardDebt
        );

        // Effects
        _user.amount -= _liquidity;
        _user.rewardDebt =
            accumulatedReward -
            int256(_calAccumulatedReward(_liquidity, _accRewardPerShare));

        userInfo[msg.sender] = _user;
        userTokenAmount[msg.sender][_tokenId] = 0;

        // Interactions
        REWARD_TOKEN.safeTransfer(_to, _pendingRewardAmount);
        return _pendingRewardAmount;
    }

    function _updatePool(
        uint256 _lpSupply
    ) internal returns (PoolInfo memory _pool) {
        _pool = pool;
        if (block.number > pool.lastRewardBlock) {
            if (_lpSupply > 0) {
                uint256 _blocks = block.number - pool.lastRewardBlock;
                uint256 _rewardAmount = (_blocks * _pool.rewardPerBlock);
                _pool.accRewardPerShare += uint128(
                    _calAccPerShare(_rewardAmount, _lpSupply)
                );
            }
            _pool.lastRewardBlock = uint64(block.number);
            pool = _pool;
            emit LogUpdatePool(
                _pool.lastRewardBlock,
                _lpSupply,
                _pool.accRewardPerShare
            );
        }
    }

    function _depositLiquidity(
        uint256 _tokenId,
        uint256 _tokenAmount,
        int256 _liquidity,
        uint256 _accRewardPerShare,
        UserInfo memory _user
    ) internal {
        require(_liquidity != 0, "Farming: no liquidity");

        _liquidity < 0
            ? _user.amount -= uint256(_liquidity)
            : _user.amount += uint256(_liquidity);

        _user.rewardDebt +=
            (_liquidity * int256(_accRewardPerShare)) /
            int256(ACC_REWARD_PRECISION);

        userInfo[msg.sender] = _user;
        userTokenAmount[msg.sender][_tokenId] += _tokenAmount;
    }

    function _withdrawLiquidity(
        uint256 _tokenId,
        uint256 _liquidity,
        uint256 _accRewardPerShare,
        UserInfo memory _user
    ) internal {
        _user.rewardDebt -= int256(
            _calAccumulatedReward(_liquidity, _accRewardPerShare)
        );

        _user.amount -= _liquidity;

        userInfo[msg.sender] = _user;
        userTokenAmount[msg.sender][_tokenId] = 0; // withdraw all its token from farming
    }

    function _calAccumulatedReward(
        uint256 _amount,
        uint256 _accRewardPerShare
    ) internal pure returns (uint256) {
        return (_amount * _accRewardPerShare) / ACC_REWARD_PRECISION;
    }

    function _calAccPerShare(
        uint256 _rewardAmount,
        uint256 _lpSupply
    ) internal pure returns (uint256) {
        return (_rewardAmount * ACC_REWARD_PRECISION) / _lpSupply;
    }
}
