// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Time} from "./libraries/Time.sol";

/// @title Voter
contract Voter is IVoter, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 internal constant MIN_MAXVOTINGNUM = 10;
    address public ve;

    address public governor;

    address public emergencyCouncil;

    uint256 public totalWeight;

    uint256 public maxVotingNum;

    // last added pool index
    uint256 public index;

    // pool => total weight
    mapping(uint256 => uint256) public weights;

    // user => pool => weight
    mapping(address => mapping(uint256 => uint256)) public votes;

    /// @dev address of user => List of pools voted for by user
    mapping(address => uint256[]) public poolVote;

    mapping(address => uint256) public usedWeights;

    mapping(address => uint256) public lastVoted;

    mapping(address => bool) public isWhitelistedUser;

    mapping(uint256 => bool) public isAlive;

    mapping(address => bool) public voted;

    constructor(address _forwarder, address _ve) ERC2771Context(_forwarder) {
        ve = _ve;

        address _sender = _msgSender();
        governor = _sender;

        emergencyCouncil = _sender;
        maxVotingNum = 30;
    }

    modifier onlyNewEpoch(address _user) {
        // ensure new epoch since last vote
        if (Time.epochStart(block.timestamp) <= lastVoted[_user])
            revert AlreadyVotedOrDeposited();
        if (block.timestamp <= Time.epochVoteStart(block.timestamp))
            revert DistributeWindow();
        _;
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return Time.epochStart(_timestamp);
    }

    function epochNext(uint256 _timestamp) external pure returns (uint256) {
        return Time.epochNext(_timestamp);
    }

    function epochVoteStart(
        uint256 _timestamp
    ) external pure returns (uint256) {
        return Time.epochVoteStart(_timestamp);
    }

    function epochVoteEnd(uint256 _timestamp) external pure returns (uint256) {
        return Time.epochVoteEnd(_timestamp);
    }

    function setVe(address _ve) external {
        if (_msgSender() != governor) revert NotGovernor();
        ve = _ve;
        emit VotingEscrowChanged(_ve);
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
        if (_maxVotingNum < MIN_MAXVOTINGNUM)
            revert MaximumVotingNumberTooLow();
        if (_maxVotingNum == maxVotingNum) revert SameValue();
        maxVotingNum = _maxVotingNum;
    }

    function reset() external onlyNewEpoch(msg.sender) nonReentrant {
        _reset(msg.sender);
    }

    function vote(
        uint256[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(msg.sender) nonReentrant {
        address _sender = _msgSender();
        uint256 _weight = IVotingEscrow(ve).balanceOf(_sender, block.timestamp);
        require(_weight != 0, "Voter: no voting power");

        if (_poolVote.length != _weights.length) revert UnequalLengths();
        if (_poolVote.length > maxVotingNum) revert TooManyPools();

        uint256 _timestamp = block.timestamp;
        if (
            (_timestamp > Time.epochVoteEnd(_timestamp)) &&
            !isWhitelistedUser[msg.sender]
        ) revert NotWhitelistedUser();
        lastVoted[msg.sender] = _timestamp;

        _vote(_sender, _weight, _poolVote, _weights);
    }

    function whitelistUser(
        address[] memory _user,
        bool[] memory _bool
    ) external {
        address _sender = _msgSender();
        if (_sender != governor) {
            revert NotGovernor();
        }

        if (_user.length != _bool.length) revert UnequalLengths();

        for (uint256 i; i < _user.length; ++i) {
            isWhitelistedUser[_user[i]] = _bool[i];
        }
        emit WhitelistUser(_sender, _user, _bool);
    }

    function addPool(uint256 _poolCount) external nonReentrant {
        address sender = _msgSender();
        if (sender != governor) revert NotGovernor();

        uint256 _index = index + 1;
        for (uint256 i; i < _poolCount; ++i) {
            isAlive[_index + i] = true;
        }

        index = _index + _poolCount - 1;

        emit PoolSet(_index + _poolCount - 1, sender);
    }

    function killPool(uint256 _pool) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (!isAlive[_pool]) revert PoolAlreadyKilled();

        isAlive[_pool] = false;
        emit PoolKilled(_pool);
    }

    function revivePool(uint256 _pool) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        if (isAlive[_pool]) revert PoolAlreadyRevived();
        isAlive[_pool] = true;
        emit PoolRevived(_pool);
    }

    function poke() external nonReentrant {
        if (block.timestamp <= Time.epochVoteStart(block.timestamp))
            revert DistributeWindow();
        uint256 _weight = IVotingEscrow(ve).balanceOf(
            msg.sender,
            block.timestamp
        );
        _poke(msg.sender, _weight);
    }

    function _poke(address _user, uint256 _weight) internal {
        uint256[] memory _poolVote = poolVote[_user];
        uint256 _poolCnt = _poolVote.length;
        uint256[] memory _weights = new uint256[](_poolCnt);

        for (uint256 i = 0; i < _poolCnt; i++) {
            _weights[i] = votes[_user][_poolVote[i]];
        }
        _vote(_user, _weight, _poolVote, _weights);
    }

    function _reset(address _user) internal {
        uint256[] storage _poolVote = poolVote[_user];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            uint256 _pool = _poolVote[i];
            uint256 _votes = votes[_user][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                delete votes[_user][_pool];

                _totalWeight += _votes;
                emit Abstained(
                    _msgSender(),
                    _pool,
                    _user,
                    _votes,
                    weights[_pool],
                    block.timestamp
                );
            }
        }
        voted[_user] = false;

        totalWeight -= _totalWeight;
        usedWeights[_user] = 0;
        delete poolVote[_user];
    }

    function _vote(
        address _user,
        uint256 _weight,
        uint256[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(_user);

        uint256 _poolCnt = _poolVote.length;
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        for (uint256 i = 0; i < _poolCnt; i++) {
            uint256 _pool = _poolVote[i];
            if (!isAlive[_pool]) revert PoolNotAlive(_pool);

            uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;
            if (votes[_user][_pool] != 0) revert NonZeroVotes();
            if (_poolWeight == 0) revert ZeroBalance();

            poolVote[_user].push(_pool);

            weights[_pool] += _poolWeight;
            votes[_user][_pool] += _poolWeight;

            _usedWeight += _poolWeight;
            _totalWeight += _poolWeight;

            emit Voted(
                _msgSender(),
                _pool,
                _user,
                _poolWeight,
                weights[_pool],
                block.timestamp
            );
        }
        if (_usedWeight > 0) voted[_user] = true;
        totalWeight += _totalWeight;
        usedWeights[_user] = _usedWeight;
    }
}
