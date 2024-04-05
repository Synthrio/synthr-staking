// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

import "./interfaces/ISmartWalletChecker.sol";

contract VotingEscrow is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant DEPOSIT_FOR_TYPE = 0;
    uint256 public constant CREATE_LOCK_TYPE = 1;
    uint256 public constant INCREASE_LOCK_AMOUNT = 2;
    uint256 public constant INCREASE_UNLOCK_TIME = 3;
    uint256 public constant INCREASE_UNLOCK_TIME_AND_LOCK_AMOUNT = 4;

    uint256 public constant WEEK = 7 * 86400; // all future times are rounded by week
    uint256 public constant MAXTIME = 4 * 365 * 86400; // 4 years
    uint256 public constant MULTIPLIER = 10 ** 18;

    bytes32 public constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");

    struct Point {
        int256 bias;
        int256 slope;
        uint256 timeStamp;
        uint256 blockNumber;
    }

    struct LockedBalance {
        int256 amount;
        uint256 end;
    }

    string public name;
    string public symbol;
    string public version;

    uint256 public decimals;
    uint256 public supply;
    uint256 public epoch;

    address public futureSmartWalletChecker;
    address public smartWalletChecker;

    address public admin;
    address public futureAdmin;

    address public token;
    address public controller;

    bool public transfersEnabled;

    Point[100000000000000000000000000000] public pointHistory;

    mapping(address => LockedBalance) public locked;
    mapping(address => uint256) public createLockTs;
    mapping(address => Point[1000000000]) public userPointHistory;
    mapping(address => uint256) public userPointEpoch;
    mapping(uint256 => uint256) public slopeChanges;

    event OwnershipCommited(address admin);
    event OwnershipApplied(address admin);
    event WalletCommited(address newSmartWalletChecker);
    event ControllerChanged(address indexed prevController, address indexed newController);
    event Deposited(address indexed provider, uint256 value, uint256 indexed locktime, uint256 _type, uint256 ts);
    event Withdrew(address indexed provider, uint256 value, uint256 timeStamp);
    event Supply(uint256 prevSupply, uint256 supply);

    constructor(
        address _tokenAddr,
        string memory _name,
        string memory _symbol,
        string memory _version
    ) {
        admin = msg.sender;
        token = _tokenAddr;
        pointHistory[0].blockNumber = block.number;
        pointHistory[0].timeStamp = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;

        uint256 _decimals = ERC20(_tokenAddr).decimals();
        require(_decimals <= 255);
        decimals = _decimals;

        name = _name;
        symbol = _symbol;
        version = _version;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, msg.sender);
    }

    function getLastUserSlope(address _user) external view returns (int256) {
        uint256 uepoch = userPointEpoch[_user];
        return userPointHistory[_user][uepoch].slope;
    }

    function userPointHistoryTs(address _user, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_user][_idx].timeStamp;
    }

    function lockedEnd(address _user) external view returns (uint256) {
        return locked[_user].end;
    }

    function balanceOf(address _user) external view returns (uint256) {
        return _balanceOf(_user, block.timestamp);
    }

    function balanceOf(address _user, uint256 _t) external view returns (uint256) {
        return _balanceOf(_user, _t);
    }

    function _balanceOf(address _user, uint256 _t) internal view returns (uint256) {
        uint256 _epoch = userPointEpoch[_user];
        if (_epoch == 0) {
            return 0;
        } else {
            Point memory lastPoint = userPointHistory[_user][_epoch];
            lastPoint.bias -= lastPoint.slope * int256(_t - lastPoint.timeStamp);
            if (lastPoint.bias < 0) {
                lastPoint.bias = 0;
            }
            return uint256(int256(lastPoint.bias));
        }
    }

    function balanceOfAt(address _user, uint256 _block) external view returns (uint256) {
        require(_block <= block.number, "VotingEscrow: Wrong condition");
        uint256 _min;
        uint256 _max = userPointEpoch[_user];
        for (uint256 i; i < 128; ++i) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[_user][_mid].blockNumber <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        Point memory upoint = userPointHistory[_user][_min];
        uint256 maxEpoch = epoch;
        uint256 _epoch = _findBlockEpoch(_block, maxEpoch);
        Point memory point0 = pointHistory[_epoch];
        uint256 blockDifference;
        uint256 timeStampDiffrence;
        if (_epoch < maxEpoch) {
            Point memory point1 = pointHistory[_epoch + 1];
            blockDifference = point1.blockNumber - point0.blockNumber;
            timeStampDiffrence = point1.timeStamp - point0.timeStamp;
        } else {
            blockDifference = block.number - point0.blockNumber;
            timeStampDiffrence = block.timestamp - point0.timeStamp;
        }

        uint256 blockTime = point0.timeStamp;
        if (blockDifference != 0) {
            blockTime += (timeStampDiffrence * (_block - point0.blockNumber)) / blockDifference;
        }
        upoint.bias -= upoint.slope * int128(int256(blockTime - upoint.timeStamp));
        if (upoint.bias >= 0) {
            return uint256(int256(upoint.bias));
        } else {
            return 0;
        }
    }

    /***
     *@notice Calculate total voting power
     *@dev Adheres to the ERC20 `totalSupply` interface for Aragon compatibility
     *@return Total voting power
     */
    function totalSupply() external view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory _last_point = pointHistory[_epoch];

        return _supplyAt(_last_point, block.timestamp);
    }

    function totalSupply(uint256 _t) external view returns (uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[_epoch];
        return _supplyAt(lastPoint, _t);
    }

    function totalSupplyAt(uint256 _block) external view returns (uint256) {
        require(_block <= block.number, "VotingEscrow: Invalid Block Number");
        uint256 _epoch = epoch;
        uint256 targetEpoch = _findBlockEpoch(_block, _epoch);
        Point memory point = pointHistory[targetEpoch];
        uint256 timeStampDiffrence;
        if (targetEpoch < _epoch) {
            Point memory pointNext = pointHistory[targetEpoch + 1];
            if (point.blockNumber != pointNext.blockNumber) {
                timeStampDiffrence = ((_block - point.blockNumber) * (pointNext.timeStamp - point.timeStamp))
                    / (pointNext.blockNumber - point.blockNumber);
            }
        } else {
            if (point.blockNumber != block.number) {
                timeStampDiffrence = timeStampDiffrence = (
                    (_block - point.blockNumber) * (block.timestamp - point.timeStamp)
                ) / (block.number - point.blockNumber);
            }
        }
        return _supplyAt(point, point.timeStamp + timeStampDiffrence);
    }

    function changeController(address _newController) external {
        require(hasRole(CONTROLLER_ROLE, msg.sender), "VotingEscrow: Invalid Caller");
        _revokeRole(CONTROLLER_ROLE, msg.sender);
        _grantRole(CONTROLLER_ROLE, _newController);
        controller = _newController;

        emit ControllerChanged(msg.sender, _newController);
    }

    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    function commitTransferOwnership(address _user) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VotingEscrow: admin only");
        futureAdmin = _user;
        emit OwnershipCommited(_user);
    }

    function applyTransferOwnership() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VotingEscrow: admin only");
        address _admin = futureAdmin;
        require(_admin != address(0), "VotingEscrow: Admin not set");
        admin = _admin;
        emit OwnershipApplied(_admin);
    }

    function commitSmartWalletChecker(address _user) external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VotingEscrow: admin only");
        futureSmartWalletChecker = _user;
        emit WalletCommited(_user);
    }

    function applySmartWalletChecker() external {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "VotingEscrow: admin only");
        smartWalletChecker = futureSmartWalletChecker;
        emit WalletCommited(futureSmartWalletChecker);
    }

    function depositFor(address _user, uint256 _value) external nonReentrant {
        LockedBalance memory _locked = locked[_user];

        require(_value > 0, "VotingEscrow: Need non-zero value");
        require(_locked.amount > 0, "VotingEscrow: No existing lock found");
        require(_locked.end > block.timestamp, "VotingEscrow: Cannot add to an expired lock. Withdraw");

        _depositFor(_user, _value, 0, locked[_user], DEPOSIT_FOR_TYPE);
    }

    function createLock(uint256 _value, uint256 _unlockTime) external nonReentrant {
        _assertNotContract(msg.sender);
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK;
        LockedBalance storage _locked = locked[msg.sender];

        require(_value > 0, "VotingEscrow: need non-zero value");
        require(_locked.amount == 0, "VotingEscrow: Withdraw old tokens first");
        require(unlockTime > block.timestamp, "VotingEscrow: Can only lock until a time in the future");
        require(unlockTime <= MAXTIME + block.timestamp, "VotingEscrow: Voting lock can be 4 years max");
        createLockTs[msg.sender] = block.timestamp;
        _depositFor(msg.sender, _value, unlockTime, _locked, CREATE_LOCK_TYPE);
    }

    function increaseAmount(uint256 _value) external nonReentrant {
        _assertNotContract(msg.sender);
        LockedBalance storage _locked = locked[msg.sender];

        require(_value > 0, "VotingEscrow: need non-zero value");
        require(_locked.amount > 0, "VotingEscrow: No existing lock found");
        require(_locked.end > block.timestamp, "VotingEscrow: Cannot add to an expired lock. Withdraw");

        _depositFor(msg.sender, _value, 0, _locked, INCREASE_LOCK_AMOUNT);
    }

    function increaseAmountAndUnlockTime(uint256 _value, uint256 _unlockTime) external nonReentrant {
        _assertNotContract(msg.sender);
        LockedBalance storage _locked = locked[msg.sender];
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK;

        require(_value > 0, "VotingEscrow: need non-zero value");
        require(_locked.amount > 0, "VotingEscrow: No existing lock found");
        require(_locked.end > block.timestamp, "VotingEscrow: Cannot add to an expired lock. Withdraw");
        require(unlockTime > _locked.end, "VotingEscrow: Can only increase lock duration");
        require(unlockTime <= block.timestamp + MAXTIME, "VotingEscrow: Voting lock can be 4 years max");

        _depositFor(msg.sender, _value, unlockTime, _locked, INCREASE_UNLOCK_TIME_AND_LOCK_AMOUNT);
    }

    function withdraw() external nonReentrant {
        LockedBalance storage _locked = locked[msg.sender];
        require(block.timestamp >= _locked.end, "VotingEscrow: The lock didn't expire");
        uint256 _value = uint256(int256(_locked.amount));
        LockedBalance storage oldLocked = _locked;
        _locked.end = 0;
        _locked.amount = 0;
        supply -= _value;

        _checkpoint(msg.sender, oldLocked, _locked);
        IERC20(token).safeTransfer(msg.sender, _value);
        delete createLockTs[msg.sender];
        emit Withdrew(msg.sender, _value, block.timestamp);
        emit Supply(supply + _value, supply);
    }

    function increaseUnlockTime(uint256 _unlockTime) external nonReentrant {
        _assertNotContract(msg.sender);
        LockedBalance storage _locked = locked[msg.sender];
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK;
        require(_locked.end > block.timestamp, "VotingEscrow: Lock expired");
        require(_locked.amount > 0, "VotingEscrow: Nothing is locked");
        require(unlockTime > _locked.end, "VotingEscrow: Can only increase lock duration");
        require(unlockTime <= block.timestamp + MAXTIME, "VotingEscrow: Voting lock can be 4 years max");

        _depositFor(msg.sender, 0, unlockTime, _locked, INCREASE_UNLOCK_TIME);
    }

    function _findBlockEpoch(uint256 _block, uint256 _maxEpoch) internal view returns (uint256) {
        uint256 _min = 0;
        uint256 _max = _maxEpoch;
        for (uint256 i = 0; i < 128; i++) {
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (pointHistory[_mid].blockNumber <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        return _min;
    }

    function _supplyAt(Point memory _point, uint256 _time) internal view returns (uint256) {
        Point memory lastPoint = _point;
        uint256 timeInterval = (lastPoint.timeStamp / WEEK) * WEEK;
        for (uint256 i; i < 255; ++i) {
            timeInterval += WEEK;
            int128 dSlope;
            if (timeInterval > _time) {
                timeInterval = _time;
            } else {
                dSlope = int128(int256(slopeChanges[timeInterval]));
            }
            lastPoint.bias -= lastPoint.slope * int256(timeInterval - lastPoint.timeStamp);
            if (timeInterval == _time) {
                break;
            }
            lastPoint.slope += dSlope;
            lastPoint.timeStamp = timeInterval;
        }
        if (lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(int256(lastPoint.bias));
    }

    function _assertNotContract(address _user) internal {
        if (_user != tx.origin) {
            address checker = smartWalletChecker;
            if (checker != address(0)) {
                if (ISmartWalletChecker(checker).check(_user)) {
                    return;
                }
            }
            revert("VotingEscrow: Smart contract depositors not allowed");
        }
    }

    function _checkpoint(address _user, LockedBalance memory _oldLocked, LockedBalance memory _newLocked) internal {
        Point memory _uOld;
        Point memory _uNew;
        int256 _oldDslope = 0;
        int256 _newDslope = 0;
        uint256 _epoch = epoch;

        if (_user != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_oldLocked.end > block.timestamp && _oldLocked.amount > 0) {
                unchecked {
                    _uOld.slope = _oldLocked.amount / int256(MAXTIME);
                }
                _uOld.bias = _uOld.slope * int256(_oldLocked.end - block.timestamp);
            }
            if (_newLocked.end > block.timestamp && _newLocked.amount > 0) {
                unchecked {
                    _uNew.slope = _newLocked.amount / int256(MAXTIME);
                }
                _uNew.bias = _uNew.slope * int256(_newLocked.end - block.timestamp);
            }

            // Read values of scheduled changes in the slope
            // _oldLocked.end can be in the past and in the future
            // _newLocked.end can ONLY by in the FUTURE unless everything expired than zeros
            _oldDslope = int256(slopeChanges[_oldLocked.end]);
            if (_newLocked.end != 0) {
                if (_newLocked.end == _oldLocked.end) {
                    _newDslope = _oldDslope;
                } else {
                    _newDslope = int256(slopeChanges[_newLocked.end]);
                }
            }
        }
        Point memory _lastPoint = Point({bias: 0, slope: 0, timeStamp: block.timestamp, blockNumber: block.number});
        if (_epoch > 0) {
            _lastPoint = pointHistory[_epoch];
        }
        uint256 _lastCheckpoint = _lastPoint.timeStamp;
        // _initial_lastPoint is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory _initialLastPoint = _lastPoint;
        uint256 _blockSlope = 0; // dblock/dt
        if (block.timestamp > _lastPoint.timeStamp) {
            _blockSlope =
                (MULTIPLIER * (block.number - _lastPoint.blockNumber)) / (block.timestamp - _lastPoint.timeStamp);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        uint256 _timeInterval;
        unchecked {
            _timeInterval = (_lastCheckpoint / WEEK) * WEEK;
        }
        for (uint256 i; i < 255;) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            _timeInterval += WEEK;
            int256 d_slope = 0;
            if (_timeInterval > block.timestamp) {
                _timeInterval = block.timestamp;
            } else {
                d_slope = int256(slopeChanges[_timeInterval]);
            }
            _lastPoint.bias = _lastPoint.bias - _lastPoint.slope * int256(_timeInterval - _lastCheckpoint);
            _lastPoint.slope += d_slope;
            if (_lastPoint.bias < 0) {
                // This can happen
                _lastPoint.bias = 0;
            }
            if (_lastPoint.slope < 0) {
                // This cannot happen - just in case
                _lastPoint.slope = 0;
            }
            _lastCheckpoint = _timeInterval;
            _lastPoint.timeStamp = _timeInterval;
            _lastPoint.blockNumber = _initialLastPoint.blockNumber
                + ((_blockSlope * (_timeInterval - _initialLastPoint.timeStamp)) / MULTIPLIER);
            _epoch += 1;
            if (_timeInterval == block.timestamp) {
                _lastPoint.blockNumber = block.number;
                break;
            } else {
                pointHistory[_epoch] = _lastPoint;
            }
            unchecked {
                ++i;
            }
        }
        epoch = _epoch;
        // Now pointHistory is filled until t=now

        if (_user != address(0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            _lastPoint.slope += _uNew.slope - _uOld.slope;
            _lastPoint.bias += _uNew.bias - _uOld.bias;
            if (_lastPoint.slope < 0) {
                _lastPoint.slope = 0;
            }
            if (_lastPoint.bias < 0) {
                _lastPoint.bias = 0;
            }
        }
        // Record the changed point into history
        pointHistory[_epoch] = _lastPoint;

        address _user2 = _user; //To avoid being "Stack Too Deep"

        if (_user2 != address(0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_newLocked.end]
            // and add old_user_slope to [_oldLocked.end]
            if (_oldLocked.end > block.timestamp) {
                // _oldDslope was <something> - _uOld.slope, so we cancel that
                _oldDslope += _uOld.slope;
                if (_newLocked.end == _oldLocked.end) {
                    _oldDslope -= _uNew.slope; // It was a new deposit, not extension
                }
                slopeChanges[_oldLocked.end] = uint256(_oldDslope);
            }
            if (_newLocked.end > block.timestamp) {
                if (_newLocked.end > _oldLocked.end) {
                    _newDslope -= _uNew.slope; // old slope disappeared at this point
                    slopeChanges[_newLocked.end] = uint256(_newDslope);
                }
                // else we recorded it already in _oldDslope
            }

            // Now handle user history
            uint256 _user_epoch;
            unchecked {
                _user_epoch = userPointEpoch[_user2] + 1;
            }

            userPointEpoch[_user2] = _user_epoch;
            _uNew.timeStamp = block.timestamp;
            _uNew.blockNumber = block.number;
            userPointHistory[_user2][_user_epoch] = _uNew;
        }
    }

    function _depositFor(
        address _user,
        uint256 _value,
        uint256 _unlockTime,
        LockedBalance memory lockedBalance,
        uint256 _type
    ) internal {
        LockedBalance memory _locked = lockedBalance;
        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;
        LockedBalance memory oldLocked = _locked;
        _locked.amount += int128(uint128(_value));
        if (_unlockTime != 0) {
            _locked.end = _unlockTime;
        }
        locked[_user] = _locked;
        _checkpoint(_user, oldLocked, _locked);
        if (_value != 0) {
            IERC20(token).safeTransferFrom(_user, address(this), _value);
        }
        emit Deposited(_user, _value, _locked.end, _type, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }
}
