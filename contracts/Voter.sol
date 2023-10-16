// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {TimeLibrary} from "./liberaries/TimeLibrary.sol";

/// @title Voter
contract Voter is IVoter, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    address public immutable ve;
    
    address public governor;

    
    address public emergencyCouncil;

    
    uint256 public totalWeight;
    
    uint256 public maxVotingNum;

    uint256 internal constant MIN_MAXVOTINGNUM = 10;

    /// @dev All pools viable for incentives
    address[] public pools;
    
    mapping(address => uint16) public gauges;
    
    mapping(uint16 => address) public poolForGauge;

    
    mapping(address => uint256) public weights;
    
    mapping(address => mapping(address => uint256)) public votes;
    /// @dev address of user => List of pools voted for by user

    mapping(address => address[]) public poolVote;

    
    mapping(address => uint256) public usedWeights;
    
    mapping(address => uint256) public lastVoted;
    
    mapping(uint16 => bool) public isGauge;

    
    mapping(address => bool) public isWhitelistedUser;

    
    mapping(uint16 => bool) public isAlive;



    mapping(address => uint256) public voteOnUser;
    mapping(address => bool) public voted;

    constructor(
        address _forwarder,
        address _ve
    ) ERC2771Context(_forwarder) {
        ve = _ve;

        address _sender = _msgSender();
        governor = _sender;

        emergencyCouncil = _sender;
        maxVotingNum = 30;
    }

    modifier onlyNewEpoch(address _user) {
        // ensure new epoch since last vote
        if (TimeLibrary.epochStart(block.timestamp) <= lastVoted[_user]) revert AlreadyVotedOrDeposited();
        if (block.timestamp <= TimeLibrary.epochVoteStart(block.timestamp)) revert DistributeWindow();
        _;
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochStart(_timestamp);
    }

    function epochNext(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochNext(_timestamp);
    }

    function epochVoteStart(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochVoteStart(_timestamp);
    }

    function epochVoteEnd(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochVoteEnd(_timestamp);
    }

    
    function setGovernor(address _governor) external {
        if (_msgSender() != governor) revert NotGovernor();
        if (_governor == address(0)) revert ZeroAddress();
        governor = _governor;
    }

    
    function setEmergencyCouncil(address _council) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (_council == address(0)) revert ZeroAddress();
        emergencyCouncil = _council;
    }

    
    function setMaxVotingNum(uint256 _maxVotingNum) external {
        if (_msgSender() != governor) revert NotGovernor();
        if (_maxVotingNum < MIN_MAXVOTINGNUM) revert MaximumVotingNumberTooLow();
        if (_maxVotingNum == maxVotingNum) revert SameValue();
        maxVotingNum = _maxVotingNum;
    }

    
    function reset() external onlyNewEpoch(msg.sender) nonReentrant {
        _reset(msg.sender);
    }

    function _reset(address _user) internal {
        address[] storage _poolVote = poolVote[_user];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_user][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                delete votes[_user][_pool];

                voteOnUser[_user] -= _votes;
                _totalWeight += _votes;
                emit Abstained(_msgSender(), _pool, _user, _votes, weights[_pool], block.timestamp);
            }
        }
        voted[_user] = false;

        totalWeight -= _totalWeight;
        usedWeights[_user] = 0;
        delete poolVote[_user];
    }

    function _vote(address _user,uint256 _weight, address[] memory _poolVote, uint256[] memory _weights) internal {
        _reset(_user);

        uint256 _poolCnt = _poolVote.length;
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            uint16 _gauge = gauges[_pool];
            if (_gauge == 0) revert GaugeDoesNotExist(_pool);
            if (!isAlive[_gauge]) revert GaugeNotAlive(_gauge);

            if (isGauge[_gauge]) {
                uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;
                if (votes[_user][_pool] != 0) revert NonZeroVotes();
                if (_poolWeight == 0) revert ZeroBalance();

                poolVote[_user].push(_pool);

                weights[_pool] += _poolWeight;
                votes[_user][_pool] += _poolWeight;

                voteOnUser[_user] += _poolWeight;

                _usedWeight += _poolWeight;
                _totalWeight += _poolWeight;

                emit Voted(_msgSender(), _pool, _user, _poolWeight, weights[_pool], block.timestamp);
            }
        }
        if (_usedWeight > 0) voted[_user] = true;
        totalWeight += _totalWeight;
        usedWeights[_user] = _usedWeight;
    }


    function vote(
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(msg.sender) nonReentrant {
        address _sender = _msgSender();
        uint256 _weight = IVotingEscrow(ve).balanceOf(_sender, block.timestamp);
        require(_weight != 0, "Voter: no voting power");

        if (_poolVote.length != _weights.length) revert UnequalLengths();
        if (_poolVote.length > maxVotingNum) revert TooManyPools();


        uint256 _timestamp = block.timestamp;
        if ((_timestamp > TimeLibrary.epochVoteEnd(_timestamp)) && !isWhitelistedUser[msg.sender])
            revert NotWhitelistedUser();
        lastVoted[msg.sender] = _timestamp;

        _vote(_sender, _weight, _poolVote, _weights);
    }


    function whitelistUser(address _user, bool _bool) external {
        address _sender = _msgSender();
        if (_sender != governor) revert NotGovernor();
        isWhitelistedUser[_user] = _bool;
        emit WhitelistUser(_sender, _user, _bool);
    }

    function setGauge(address _pool, uint16 _gauge) external nonReentrant returns (uint16) {
        address sender = _msgSender();
        if (sender != governor) revert NotGovernor();
        if (gauges[_pool] != 0) revert GaugeExists();

        gauges[_pool] = _gauge;
        poolForGauge[_gauge] = _pool;
        isGauge[_gauge] = true;
        isAlive[_gauge] = true;

        pools.push(_pool);

        emit GaugeSet(
            _gauge,
            _pool,
            sender
        );

        return _gauge;
    }

    
    function killGauge(uint16 _gauge) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (!isAlive[_gauge]) revert GaugeAlreadyKilled();

        isAlive[_gauge] = false;
        emit GaugeKilled(_gauge);
    }

    
    function reviveGauge(uint16 _gauge) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (isAlive[_gauge]) revert GaugeAlreadyRevived();
        isAlive[_gauge] = true;
        emit GaugeRevived(_gauge);
    }

    
    function length() external view returns (uint256) {
        return pools.length;
    }

}