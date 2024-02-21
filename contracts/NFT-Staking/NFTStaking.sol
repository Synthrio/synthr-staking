// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import "./interfaces/INftToken.sol";


contract NftStaking is Ownable2Step {
    using SafeERC20 for IERC20;

    /// @notice Address of reward token contract.
    IERC20 public immutable REWARD_TOKEN;

    /// @notice Info of each gauge controller user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of reward token entitled to the user.
    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    /// @notice Info of each gauge pool.
    struct NFTPoolInfo {
        uint256 epoch;
        uint64 lastRewardBlock;
        uint128 accRewardPerShare;
        uint256 rewardPerBlock;
        uint256 currentEpoch;
    }

    /// @notice Total lock amount of users in VotingEscrow
    uint256 public totalLockAmount;

    /// @notice Info of each pool.
    mapping(address => NFTPoolInfo) public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => mapping(address => UserInfo)) public userInfo;
    
    constructor(address _admin, address _rewardToken) Ownable(_admin) {
        REWARD_TOKEN = IERC20(_rewardToken);
    }

    function userRewardsDebt(
        address _pool,
        address _user
    ) external view returns (int256) {
        return userInfo[_pool][_user].rewardDebt;
    }

    /// @notice Add a new NFT pool. Can only be called by the owner.
    function addPool(
        address[] memory _pool
    ) external onlyOwner {

        for (uint256 i; i < _pool.length; i++) {
            poolInfo[_pool[i]].lastRewardBlock = uint64(block.number);
        }
    }

    // /// @notice update epoch of pool
    // /// @param _pool address of pool to be updated. Make sure to update all active pools.
    // /// @param _indexes index of rewardInfo array.
    // /// @param _rewardPerBlock array of rewardPerBlock
    // function updateEpoch(
    //     address[] memory _pool,
    //     address _user,
    //     uint256[] memory _indexes,
    //     uint256[] memory _rewardPerBlock,
    //     uint256[] memory _rewardAmount
    // ) external onlyOwner {
    //     require(
    //         _rewardAmount.length == _rewardPerBlock.length && _rewardAmount.length == _pool.length,
    //         "NftStaking: length of array doesn't mach"
    //     );

    //     RewardInfo[MAX_REWARD_TOKEN] storage _rewardInfo = reward[_pool];

    //     for (uint256 i = 0; i < _indexes.length; ++i) {
    //         _rewardInfo[_indexes[i]].rewardPerBlock = _rewardPerBlock[i];
    //         IERC20(_rewardInfo[_indexes[i]].token).safeTransferFrom(
    //             _user,
    //             address(this),
    //             _rewardAmount[i]
    //         );
    //     }

    //     poolInfo[_pool].epoch++;
    //     emit EpochUpdated(_pool, poolInfo[_pool].epoch);
    // }
}
