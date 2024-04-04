// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../libraries/Math.sol";
import "../interfaces/IVotingEscrow.sol";
import "../libraries/TransferHelper.sol";

contract VeYieldDistributor is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for ERC20;

    /* ========== STATE VARIABLES ========== */

    // Constant for price precision
    uint256 private constant PRICE_PRECISION = 1e6;

    // Instances
    IVotingEscrow private ve;
    ERC20 public emittedToken;

    // Addresses
    address public emittedTokenAddress;

    // Admin addresses
    address public timelockAddress;


    // Yield and period related
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public yieldRate;
    uint256 public yieldDuration = 604800; // 7 * 86400  (7 days)
    mapping(address => bool) public rewardNotifiers;

    // Yield tracking
    uint256 public yieldPerVeStored = 0;
    mapping(address => uint256) public userYieldPerTokenPaid;
    mapping(address => uint256) public yields;

    // ve tracking
    uint256 public totalVeParticipating = 0;
    uint256 public totalVeSupplyStored = 0;
    mapping(address => bool) public userIsInitialized;
    mapping(address => uint256) public userVeCheckpointed;
    mapping(address => uint256) public userVeEndpointCheckpointed;
    mapping(address => uint256) private lastRewardClaimTime; // staker addr -> timestamp

    // Greylists
    mapping(address => bool) public greylist;

    // Admin booleans for emergencies
    bool public yieldCollectionPaused = false; // For emergencies

    /* ========== MODIFIERS ========== */

    modifier onlyByOwnGov() {
        require( msg.sender == owner() || msg.sender == timelockAddress, "Not owner or timelock");
        _;
    }

    modifier notYieldCollectionPaused() {
        require(yieldCollectionPaused == false, "Yield collection is paused");
        _;
    }

    modifier checkpointUser(address account) {
        _checkpointUser(account);
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor (
        address _owner,
        address _emittedToken,
        address _timelockAddress,
        address _ve
    ) Ownable(_owner) {
        emittedTokenAddress = _emittedToken;
        emittedToken = ERC20(_emittedToken);

        ve = IVotingEscrow(_ve);
        lastUpdateTime = block.timestamp;
        timelockAddress = _timelockAddress;

        rewardNotifiers[_owner] = true;
    }

    /* ========== VIEWS ========== */

    function fractionParticipating() external view returns (uint256) {
        return (totalVeParticipating * PRICE_PRECISION) / (totalVeSupplyStored);
    }

    // Only positions with locked ve can accrue yield. Otherwise, expired-locked ve
    function eligibleCurrentVe(address account) public view returns (uint256 eligibleVeBal, uint256 storedEndingTimestamp) {
        uint256 currVeBal = ve.balanceOf(account);
        
        // Stored is used to prevent abuse
        storedEndingTimestamp = userVeEndpointCheckpointed[account];

        // Only unexpired ve should be eligible
        if (storedEndingTimestamp != 0 && (block.timestamp >= storedEndingTimestamp)){
            eligibleVeBal = 0;
        }
        else if (block.timestamp >= storedEndingTimestamp){
            eligibleVeBal = 0;
        }
        else {
            eligibleVeBal = currVeBal;
        }
    }

    function lastTimeYieldApplicable() public view returns (uint256) {
        return Math.min(block.timestamp, periodFinish);
    }

    function yieldPerVe() public view returns (uint256) {
        if (totalVeSupplyStored == 0) {
            return yieldPerVeStored;
        } else {
            return (
                yieldPerVeStored + (
                    (((lastTimeYieldApplicable() - lastUpdateTime) * (yieldRate)) * 1e18) / (totalVeSupplyStored)
                )
            );
        }
    }

    function earned(address account) public view returns (uint256) {
        // Uninitialized users should not earn anything yet
        if (!userIsInitialized[account]) return 0;

        // Get eligible ve balances
        (uint256 eligibleCurrentve, uint256 endingTimestamp) = eligibleCurrentVe(account);

        // If your ve is unlocked
        uint256 eligibleTimeFraction = PRICE_PRECISION;
        if (eligibleCurrentve == 0){
            // And you already claimed after expiration
            if (lastRewardClaimTime[account] >= endingTimestamp) {
                // You get NOTHING. You LOSE. Good DAY ser!
                return 0;
            }
            // You haven't claimed yet
            else {
                uint256 eligibleTime = (endingTimestamp) - (lastRewardClaimTime[account]);
                uint256 totalTime = (block.timestamp) - (lastRewardClaimTime[account]);
                eligibleTimeFraction = (PRICE_PRECISION * (eligibleTime)) / (totalTime);
            }
        }

        // If the amount of ve increased, only pay off based on the old balance
        // Otherwise, take the midpoint
        uint256 veBalanceToUse;
        {
            uint256 oldVeBalance = userVeCheckpointed[account];
            if (eligibleCurrentve > oldVeBalance){
                veBalanceToUse = oldVeBalance;
            }
            else {
                veBalanceToUse = (eligibleCurrentve + oldVeBalance) / (2); 
            }
        }

        return (
            (((veBalanceToUse * (yieldPerVe() - (userYieldPerTokenPaid[account]))) * eligibleTimeFraction) / 1e18 * PRICE_PRECISION) + yields[account]
        );
    }

    function getYieldForDuration() external view returns (uint256) {
        return (yieldRate * yieldDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function _checkpointUser(address account) internal {
        // Need to retro-adjust some things if the period hasn't been renewed, then start a new one
        sync();

        // Calculate the earnings first
        _syncEarned(account);

        // Get the old and the new ve balances
        uint256 oldVeBalance = userVeCheckpointed[account];
        uint256 newVeBalance = ve.balanceOf(account);

        // Update the user's stored ve balance
        userVeCheckpointed[account] = newVeBalance;

        // Update the user's stored ending timestamp
        IVotingEscrow.LockedBalance memory currLockedBalPack = ve.locked(account);
        userVeEndpointCheckpointed[account] = currLockedBalPack.end;

        // Update the total amount participating
        if (newVeBalance >= oldVeBalance) {
            uint256 weightDiff = newVeBalance - oldVeBalance;
            totalVeParticipating = totalVeParticipating + weightDiff;
        } else {
            uint256 weightDiff = oldVeBalance - newVeBalance;
            totalVeParticipating = totalVeParticipating - weightDiff;
        }

        // Mark the user as initialized
        if (!userIsInitialized[account]) {
            userIsInitialized[account] = true;
            lastRewardClaimTime[account] = block.timestamp;
        }
    }

    function _syncEarned(address account) internal {
        if (account != address(0)) {
            uint256 earned0 = earned(account);
            yields[account] = earned0;
            userYieldPerTokenPaid[account] = yieldPerVeStored;
        }
    }

    // Anyone can checkpoint another user
    function checkpointOtherUser(address user_addr) external {
        _checkpointUser(user_addr);
    }

    // Checkpoints the user
    function checkpoint() external {
        _checkpointUser(msg.sender);
    }

    function getYield() external nonReentrant notYieldCollectionPaused checkpointUser(msg.sender) returns (uint256 yield0) {
        require(greylist[msg.sender] == false, "Address has been greylisted");

        yield0 = yields[msg.sender];
        if (yield0 > 0) {
            yields[msg.sender] = 0;
            TransferHelper.safeTransfer(
                emittedTokenAddress,
                msg.sender,
                yield0
            );
            emit YieldCollected(msg.sender, yield0, emittedTokenAddress);
        }

        lastRewardClaimTime[msg.sender] = block.timestamp;
    }


    function sync() public {
        // Update the total ve supply
        yieldPerVeStored = yieldPerVe();
        totalVeSupplyStored = ve.totalSupply();
        lastUpdateTime = lastTimeYieldApplicable();
    }

    function notifyRewardAmount(uint256 amount) external {
        // Only whitelisted addresses can notify rewards
        require(rewardNotifiers[msg.sender], "Sender not whitelisted");

        // Handle the transfer of emission tokens via `transferFrom` to reduce the number
        // of transactions required and ensure correctness of the smission amount
        emittedToken.safeTransferFrom(msg.sender, address(this), amount);

        // Update some values beforehand
        sync();

        // Update the new yieldRate
        if (block.timestamp >= periodFinish) {
            yieldRate = amount / yieldDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * yieldRate;
            yieldRate = (amount + leftover) / yieldDuration;
        }
        
        // Update duration-related info
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + yieldDuration;

        emit RewardAdded(amount, yieldRate);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Added to support recovering LP Yield and other mistaken tokens from other systems to be distributed to holders
    function recoverERC20(address tokenAddress, uint256 tokenAmount) external onlyByOwnGov {
        // Only the owner address can ever receive the recovery withdrawal
        TransferHelper.safeTransfer(tokenAddress, owner(), tokenAmount);
        emit RecoveredERC20(tokenAddress, tokenAmount);
    }

    function setYieldDuration(uint256 _yieldDuration) external onlyByOwnGov {
        require( periodFinish == 0 || block.timestamp > periodFinish, "Previous yield period must be complete before changing the duration for the new period");
        yieldDuration = _yieldDuration;
        emit YieldDurationUpdated(yieldDuration);
    }

    function greylistAddress(address _address) external onlyByOwnGov {
        greylist[_address] = !(greylist[_address]);
    }

    function toggleRewardNotifier(address notifier_addr) external onlyByOwnGov {
        rewardNotifiers[notifier_addr] = !rewardNotifiers[notifier_addr];
    }

    function setPauses(bool _yieldCollectionPaused) external onlyByOwnGov {
        yieldCollectionPaused = _yieldCollectionPaused;
    }

    function setYieldRate(uint256 _new_rate0, bool sync_too) external onlyByOwnGov {
        yieldRate = _new_rate0;

        if (sync_too) {
            sync();
        }
    }

    function setTimelock(address _timelockAddress) external onlyByOwnGov {
        timelockAddress = _timelockAddress;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward, uint256 yieldRate);
    event OldYieldCollected(address indexed user, uint256 yield, address token_address);
    event YieldCollected(address indexed user, uint256 yield, address token_address);
    event YieldDurationUpdated(uint256 newDuration);
    event RecoveredERC20(address token, uint256 amount);
    event YieldPeriodRenewed(address token, uint256 yieldRate);
    event DefaultInitialization();
}
