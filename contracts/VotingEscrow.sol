// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./interfaces/ISmartWalletChecker.sol";

contract VotingEscrow is ReentrancyGuard {

    uint256 constant private DEPOSIT_FOR_TYPE = 0;
    uint256 constant private CREATE_LOCK_TYPE = 1;
    uint256 constant private INCREASE_LOCK_AMOUNT = 2;
    uint256 constant private INCREASE_UNLOCK_TIME = 3;

    uint256 constant private WEEK = 7 * 86400;    // all future times are rounded by week
    uint256 constant private MAXTIME = 4 * 365 * 86400;  // 4 years
    uint256 constant private MULTIPLIER = 10 ** 18;

    struct Point {
        int256 bias;
        int256 slope;
        uint256 ts;
        uint256 blk;
    }

    struct LockedBalance {
        int256 amount;
        uint256 end;
    }

    address public futureSmartWalletChecker;
    address public smartWalletChecker;

    address public admin;
    address public futureAdmin;

    address public token;
    address public controller;
    uint256 public supply;

    bool public transfersEnabled;
    string public name;
    string public symbol;
    string public version;
    uint256 public epoch;
    uint256 public decimals;

    Point[100000000000000000000000000000] public pointHistory;

    mapping (address => LockedBalance) public locked;
    mapping (address => Point[1000000000]) public userPointHistory;
    mapping (address => uint256) public userPointEpoch;
    mapping (uint256 => uint256) public slopeChanges;


    event CommitOwnership(address admin);
    event ApplyOwnership(address admin); 
    event commitWallet(address newSmartWalletChecker);
    event Deposit(address indexed provider, uint256 value, uint256 indexed locktime, uint256 _type, uint256 ts);
    event Withdraw(address indexed provider, uint256 value, uint256 ts);
    event Supply(uint256 prevSupply, uint256 supply);

    constructor(address _tokenAddr, string memory _name,string memory _symbol, string memory _version) {
        admin = msg.sender;
        token = _tokenAddr;
        pointHistory[0].blk = block.number;
        pointHistory[0].ts = block.timestamp;
        controller = msg.sender;
        transfersEnabled = true;

        uint256 _decimals = ERC20(_tokenAddr).decimals();
        require(_decimals <= 255);
        decimals = _decimals;

        name = _name;
        symbol = _symbol;
        version = _version;
    }

    function getLasteUserSlope(address addr) external view returns (int256) {
        uint256 uepoch = userPointEpoch[addr];
        return userPointHistory[addr][uepoch].slope;
    }

    function userPointHistoryTs(address _addr, uint256 _idx) external view returns (uint256) {
        return userPointHistory[_addr][_idx].ts;
    }

    function lockedEnd(address _addr) external view returns (uint256) {
        return locked[_addr].end;
    }

    function balanceOf(address addr, uint256 _t) external view returns (uint256) {
            uint256 _epoch = userPointEpoch[addr];
            if (_epoch == 0) {
                return 0;
            } else {
                Point memory lastPoint = userPointHistory[addr][_epoch];
                lastPoint.bias -= lastPoint.slope * int256(_t - lastPoint.ts);
                if (lastPoint.bias < 0) {
                    lastPoint.bias = 0;
                }
                return uint256(int256(lastPoint.bias));
            }
    }

    function balanceOfAt(address addr, uint256 _block) external view returns (uint256){
        require(_block <= block.number, "Wrong cond");
        uint256 _min;
        uint256 _max = userPointEpoch[addr];
        for (uint256 i; i < 128 ; ++i){
            if (_min >= _max) {
                break;
            }
            uint256 _mid = (_min + _max + 1) / 2;
            if (userPointHistory[addr][_mid].blk <= _block) {
                _min = _mid;
            } else {
                _max = _mid - 1;
            }
        }
        Point memory upoint = userPointHistory[addr][_min];
        uint256 max_epoch = epoch;
        uint256 _epoch = findBlockEpoch(_block, max_epoch);
        Point memory point_0  = pointHistory[_epoch];
        uint256 d_block;
        uint256 d_t;
        if(_epoch < max_epoch) {
            Point memory point_1 = pointHistory[_epoch + 1];
            d_block = point_1.blk - point_0.blk;
            d_t = point_1.ts - point_0.ts;
        } else {
            d_block = block.number - point_0.blk;
            d_t = block.timestamp - point_0.ts;
        }

        uint256 block_time = point_0.ts;
        if(d_block != 0) {
            block_time += d_t * (_block - point_0.blk) / d_block;
        }
        upoint.bias -= upoint.slope * int128(int256(block_time - upoint.ts));
        if (upoint.bias >= 0) {
            return uint256(int256(upoint.bias));
        }else{
            return 0;
        }
    }

    function totalSupply(uint256 t) external view returns(uint256) {
        uint256 _epoch = epoch;
        Point memory lastPoint = pointHistory[_epoch];
        return supply_at(lastPoint, t);
    }

    function totalSupplyAt(uint256 _block) external view returns(uint256) {
        require(_block <= block.number, "Invalid Block Number");
        uint256 _epoch = epoch;
        uint256 target_epoch = findBlockEpoch(_block, _epoch);
        Point memory point = pointHistory[target_epoch];
        uint256 dt;
        if(target_epoch < _epoch) {
            Point memory pointNext = pointHistory[target_epoch + 1];
            if(point.blk != pointNext.blk) {
                dt = (_block - point.blk) * (pointNext.ts - point.ts) / (pointNext.blk - point.blk);
            }
        } else {
            if(point.blk != block.number) {
                dt = dt = (_block - point.blk) * (block.timestamp - point.ts) / (block.number - point.blk);
            }
        }
        return supply_at(point, point.ts + dt);
    }

    function changeController(address _newController) external {
        require(msg.sender == controller, "Invalid Caller");
        controller = _newController;
    }

    function checkpoint() external {
        _checkpoint(address(0), LockedBalance(0, 0), LockedBalance(0, 0));
    }

    function commitTransferOwnership(address addr) external {
        require(msg.sender == admin, "admin only");
        futureAdmin = addr;
        emit CommitOwnership(addr);
    }

    function applyTransferOwnership() external  {
        require(msg.sender == admin, "admin only");
        address _admin = futureAdmin;
        require(_admin != address(0), "Admin not set");
        admin = _admin;
        emit ApplyOwnership(_admin);
    }

    function commitSmartWalletChecker(address addr) external  {
        require(msg.sender == admin, "admin only");
        futureSmartWalletChecker = addr;
        emit commitWallet(addr);
    }

    function applySmartWalletChecker() external  {
        require(msg.sender == admin, "admin only");
        smartWalletChecker = futureSmartWalletChecker;
        emit commitWallet(futureSmartWalletChecker);
    }

    function depositFor(address _addr, uint256 _value) external nonReentrant {
        LockedBalance memory _locked = locked[_addr];

        require(_value > 0, "Need non-zero value");
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to an expired lock. Withdraw");

        _depositFor(_addr, _value, 0, locked[_addr], DEPOSIT_FOR_TYPE);
    }

    function createLock(uint256 _value, uint256 _unlockTime) external nonReentrant {
        _assertNotContract(msg.sender);
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK; 
        LockedBalance storage _locked = locked[msg.sender];

        require(_value > 0, "need non-zero value");
        require(_locked.amount == 0, "Withdraw old tokens first");
        require(unlockTime > block.timestamp, "Can only lock until a time in the future");
        require(unlockTime <= MAXTIME, "Voting lock can be 4 years max");

        _depositFor(msg.sender, _value, unlockTime, _locked, CREATE_LOCK_TYPE);
    }


    function increaseAmount(uint256 _value) external nonReentrant {
        _assertNotContract(msg.sender);
        LockedBalance storage _locked = locked[msg.sender];

        require(_value > 0, "need non-zero value");
        require(_locked.amount > 0, "No existing lock found");
        require(_locked.end > block.timestamp, "Cannot add to an expired lock. Withdraw");

        _depositFor(msg.sender, _value, 0, _locked, INCREASE_LOCK_AMOUNT);
    }

    function withdraw() external nonReentrant {
        LockedBalance storage _locked = locked[msg.sender];
        require(block.timestamp >= _locked.end, "The lock didn't expire");
        uint256 _value = uint256(int256(_locked.amount));
        LockedBalance storage oldLocked = _locked;
        _locked.end = 0;
        _locked.amount = 0;
        supply -= _value;

        _checkpoint(msg.sender, oldLocked, _locked);
        require(IERC20(token).transfer(msg.sender, _value));

        emit Withdraw(msg.sender, _value, block.timestamp);
        emit Supply(supply + _value, supply);
    }

    function increaseUnlockTime(uint256 _unlockTime) external nonReentrant {
        _assertNotContract(msg.sender);
        LockedBalance storage _locked = locked[msg.sender];
        uint256 unlockTime = (_unlockTime / WEEK) * WEEK;
        require(_locked.end > block.timestamp, "Lock expired");
        require(_locked.amount > 0, "Nothing is locked");
        require(unlockTime > _locked.end, "Can only increase lock duration");
        require(unlockTime <= block.timestamp + MAXTIME, "Voting lock can be 4 years max");

        _depositFor(msg.sender, 0, unlockTime, _locked, INCREASE_UNLOCK_TIME);
    }

    function findBlockEpoch(uint256 _block, uint256 maxEpoch) internal view returns (uint256) {
            uint256 _min = 0;
            uint256 _max = maxEpoch;
            for (uint256 i = 0; i < 128; i++) {
                if (_min >= _max) {
                    break;
                }
                uint256 _mid = (_min + _max + 1) / 2;
                if (pointHistory[_mid].blk <= _block) {
                    _min = _mid;
                } else {
                    _max = _mid - 1;
                }
            }
            return _min;
    }

    function supply_at(Point memory _point, uint256 t) internal view returns (uint256) {
        Point memory lastPoint = _point;
        uint256 t_i = (lastPoint.ts / WEEK) * WEEK;
        for(uint256 i; i <= 255; ++i){
            t_i += WEEK;
            int128 d_slope;
            if(t_i > t){
                t_i = t;
            } else {
                d_slope = int128(int256(slopeChanges[t_i]));
            }
            if (t_i == t){
                break;
            }
            lastPoint.slope += d_slope;
            lastPoint.ts = t_i;
        }
        if(lastPoint.bias < 0) {
            lastPoint.bias = 0;
        }
        return uint256(int256(lastPoint.bias));
    }


    function _assertNotContract(address addr) internal {
        if (addr != tx.origin) {
            address checker = smartWalletChecker;
            if (checker != address(0)) {
                if(ISmartWalletChecker(checker).check(addr)){
                   revert("Smart contract depositors not allowed");
                }
            }
        }
    }

    function _checkpoint(
        address _addr,
        LockedBalance memory _old_locked,
        LockedBalance memory _new_locked
    ) internal {
        Point memory _u_old;
        Point memory _u_new;
        int256 _old_dslope = 0;
        int256 _new_dslope = 0;
        uint256 _epoch = epoch;

        if (_addr != address(0)) {
            // Calculate slopes and biases
            // Kept at zero when they have to
            if (_old_locked.end > block.timestamp && _old_locked.amount > 0) {
                unchecked {
                    _u_old.slope = _old_locked.amount / int256(MAXTIME);
                }
                _u_old.bias =
                    _u_old.slope *
                    int256(_old_locked.end - block.timestamp);
            }
            if (_new_locked.end > block.timestamp && _new_locked.amount > 0) {
                unchecked {
                    _u_new.slope = _new_locked.amount / int256(MAXTIME);
                }
                _u_new.bias =
                    _u_new.slope *
                    int256(_new_locked.end - block.timestamp);
            }

            // Read values of scheduled changes in the slope
            // _old_locked.end can be in the past and in the future
            // _new_locked.end can ONLY by in the FUTURE unless everything expired than zeros
            _old_dslope = int256(slopeChanges[_old_locked.end]);
            if (_new_locked.end != 0) {
                if (_new_locked.end == _old_locked.end) {
                    _new_dslope = _old_dslope;
                } else {
                    _new_dslope =int256(slopeChanges[_new_locked.end]);
                }
            }
        }
        Point memory _last_point = Point({
            bias: 0,
            slope: 0,
            ts: block.timestamp,
            blk: block.number
        });
        if (_epoch > 0) {
            _last_point = pointHistory[_epoch];
        }
        uint256 _last_checkpoint = _last_point.ts;
        // _initial_last_point is used for extrapolation to calculate block number
        // (approximately, for *At methods) and save them
        // as we cannot figure that out exactly from inside the contract
        Point memory _initial_last_point = _last_point;
        uint256 _block_slope = 0; // dblock/dt
        if (block.timestamp > _last_point.ts) {
            _block_slope =
                (MULTIPLIER * (block.number - _last_point.blk)) /
                (block.timestamp - _last_point.ts);
        }
        // If last point is already recorded in this block, slope=0
        // But that's ok b/c we know the block in such case

        // Go over weeks to fill history and calculate what the current point is
        uint256 _t_i;
        unchecked {
            _t_i = (_last_checkpoint / WEEK) * WEEK;
        }
        for (uint256 i; i < 255; ) {
            // Hopefully it won't happen that this won't get used in 5 years!
            // If it does, users will be able to withdraw but vote weight will be broken
            _t_i += WEEK;
            int256 d_slope = 0;
            if (_t_i > block.timestamp) {
                _t_i = block.timestamp;
            } else {
                d_slope = int256(slopeChanges[_t_i]);
            }
            _last_point.bias =
                _last_point.bias -
                _last_point.slope *
                int256(_t_i - _last_checkpoint);
            _last_point.slope += d_slope;
            if (_last_point.bias < 0) {
                // This can happen
                _last_point.bias = 0;
            }
            if (_last_point.slope < 0) {
                // This cannot happen - just in case
                _last_point.slope = 0;
            }
            _last_checkpoint = _t_i;
            _last_point.ts = _t_i;
            _last_point.blk =
                _initial_last_point.blk +
                ((_block_slope * (_t_i - _initial_last_point.ts)) / MULTIPLIER);
            _epoch += 1;
            if (_t_i == block.timestamp) {
                _last_point.blk = block.number;
                break;
            } else {
                pointHistory[_epoch] = _last_point;
            }
            unchecked {
                ++i;
            }
        }
        epoch = _epoch;
        // Now pointHistory is filled until t=now

        if (_addr != address(0)) {
            // If last point was in this block, the slope change has been applied already
            // But in such case we have 0 slope(s)
            _last_point.slope += _u_new.slope - _u_old.slope;
            _last_point.bias += _u_new.bias - _u_old.bias;
            if (_last_point.slope < 0) {
                _last_point.slope = 0;
            }
            if (_last_point.bias < 0) {
                _last_point.bias = 0;
            }
        }
        // Record the changed point into history
        pointHistory[_epoch] = _last_point;

        address _addr2 = _addr; //To avoid being "Stack Too Deep"

        if (_addr2 != address(0)) {
            // Schedule the slope changes (slope is going down)
            // We subtract new_user_slope from [_new_locked.end]
            // and add old_user_slope to [_old_locked.end]
            if (_old_locked.end > block.timestamp) {
                // _old_dslope was <something> - _u_old.slope, so we cancel that
                _old_dslope += _u_old.slope;
                if (_new_locked.end == _old_locked.end) {
                    _old_dslope -= _u_new.slope; // It was a new deposit, not extension
                }
                slopeChanges[_old_locked.end] = uint256(_old_dslope);
            }
            if (_new_locked.end > block.timestamp) {
                if (_new_locked.end > _old_locked.end) {
                    _new_dslope -= _u_new.slope; // old slope disappeared at this point
                    slopeChanges[_new_locked.end] = uint256(_new_dslope);
                }
                // else we recorded it already in _old_dslope
            }

            // Now handle user history
            uint256 _user_epoch;
            unchecked {
                _user_epoch = userPointEpoch[_addr2] + 1;
            }

            userPointEpoch[_addr2] = _user_epoch;
            _u_new.ts = block.timestamp;
            _u_new.blk = block.number;
            userPointHistory[_addr2][_user_epoch] = _u_new;
        }
    }

    function _depositFor(
        address _addr,
        uint256 _value,
        uint256 unlockTime,
        LockedBalance memory lockedBalance,
        uint256 _type
    ) internal {
        LockedBalance memory _locked = lockedBalance;
        uint256 supplyBefore = supply;
        supply = supplyBefore + _value;
        LockedBalance memory oldLocked = _locked;
        _locked.amount += int128(uint128(_value));
        if (unlockTime != 0) {
            _locked.end = unlockTime;
        }
        locked[_addr] = _locked;
        _checkpoint(_addr, oldLocked, _locked);
        if (_value != 0) {
            require(IERC20(token).transferFrom(_addr, address(this), _value), "Transfer failed");
        }
        emit Deposit(_addr, _value, _locked.end, _type, block.timestamp);
        emit Supply(supplyBefore, supplyBefore + _value);
    }
}   
