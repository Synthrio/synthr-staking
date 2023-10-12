// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {TimeLibrary} from "./liberaries/TimeLibrary.sol";

import {IDexLpFarming} from "./interfaces/IDexLpFarming.sol";

/// @title Voter
contract Voter is IVoter, ERC2771Context, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MIN_MAXVOTINGNUM = 10;

    bool public isAlive;

    address public immutable ve;
    address public gauge;
    address public governor;
    address public emergencyCouncil;
    uint256 public totalWeight;
    uint256 public maxVotingNum;

    address[] public pools;

    mapping(address => uint256) public weights;

    mapping(uint256 => mapping(address => uint256)) public votes;

    mapping(uint256 => address[]) public poolVote;

    mapping(uint256 => uint256) public usedWeights;

    mapping(uint256 => uint256) public lastVoted;

    mapping(uint256 => bool) public isWhitelistedNFT;

    mapping(uint256 => bool) public voted;

    mapping(uint256 => uint256) public voteOnTokenId;

    constructor(
        address _forwarder,
        address _ve,
        address _gauge
    ) ERC2771Context(_forwarder) {
        ve = _ve;
        gauge = _gauge;
        address _sender = _msgSender();
        governor = _sender;
        emergencyCouncil = _sender;
        maxVotingNum = 30;
    }

    modifier onlyNewEpoch(uint256 _tokenId) {
        // ensure new epoch since last vote
        if (TimeLibrary.epochStart(block.timestamp) <= lastVoted[_tokenId])
            revert AlreadyVotedOrDeposited();
        if (block.timestamp <= TimeLibrary.epochVoteStart(block.timestamp))
            revert DistributeWindow();
        _;
    }

    function epochStart(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochStart(_timestamp);
    }

    function epochNext(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochNext(_timestamp);
    }

    function epochVoteStart(
        uint256 _timestamp
    ) external pure returns (uint256) {
        return TimeLibrary.epochVoteStart(_timestamp);
    }

    function epochVoteEnd(uint256 _timestamp) external pure returns (uint256) {
        return TimeLibrary.epochVoteEnd(_timestamp);
    }

    function setGovernor(address _governor) public {
        if (_msgSender() != governor) revert NotGovernor();
        if (_governor == address(0)) revert ZeroAddress();
        governor = _governor;
    }

    function setGauge(address _newGauge) public {
        if (_msgSender() != governor) revert NotGovernor();
        if (_newGauge == address(0)) revert ZeroAddress();
        gauge = _newGauge;
        emit GaugeSet(_newGauge, governor);
    }

    function setEmergencyCouncil(address _council) public {
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

    function reset(
        uint256 _tokenId
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        require(
            IDexLpFarming(gauge).isTokenDeposited(msg.sender, _tokenId),
            "Voter: not deposited"
        );

        _reset(_tokenId);
    }


    function _vote(
        uint256 _tokenId,
        uint256 _weight,
        address[] memory _poolVote,
        uint256[] memory _weights
    ) internal {
        _reset(_tokenId);
        uint256 _poolCnt = _poolVote.length;
        uint256 _totalVoteWeight = 0;
        uint256 _totalWeight = 0;
        uint256 _usedWeight = 0;

        if (!isAlive) revert GaugeNotAlive();
        for (uint256 i = 0; i < _poolCnt; i++) {
            _totalVoteWeight += _weights[i];
        }

        require(
            IVotingEscrow(ve).balanceOf(msg.sender, block.timestamp) >=
                _totalVoteWeight,
            "Voter: not enough weight"
        );

        for (uint256 i = 0; i < _poolCnt; i++) {
            address _pool = _poolVote[i];
            if (gauge == address(0)) revert GaugeDoesNotExist();

            uint256 _poolWeight = (_weights[i] * _weight) / _totalVoteWeight;
            if (votes[_tokenId][_pool] != 0) revert NonZeroVotes();
            if (_poolWeight == 0) revert ZeroBalance();

            poolVote[_tokenId].push(_pool);

            weights[_pool] += _poolWeight;
            votes[_tokenId][_pool] += _poolWeight;

            voteOnTokenId[_tokenId] += _poolWeight;

            _usedWeight += _poolWeight;
            _totalWeight += _poolWeight;
            emit Voted(
                _msgSender(),
                _pool,
                _tokenId,
                _poolWeight,
                weights[_pool],
                block.timestamp
            );
        }
        if (_usedWeight > 0) voted[_tokenId] = true;
        totalWeight += _totalWeight;
        usedWeights[_tokenId] = _usedWeight;
    }

    function vote(
        uint256 _tokenId,
        address[] calldata _poolVote,
        uint256[] calldata _weights
    ) external onlyNewEpoch(_tokenId) nonReentrant {
        address _sender = _msgSender();

        require(
            IDexLpFarming(gauge).isTokenDeposited(_sender, _tokenId),
            "Voter: not deposited"
        );

        if (_poolVote.length != _weights.length) revert UnequalLengths();
        if (_poolVote.length > maxVotingNum) revert TooManyPools();

        uint256 _timestamp = block.timestamp;
        if (
            (_timestamp > TimeLibrary.epochVoteEnd(_timestamp)) &&
            !isWhitelistedNFT[_tokenId]
        ) revert NotWhitelistedNFT();
        lastVoted[_tokenId] = _timestamp;

        uint256 _weight = voteOnTokenId[_tokenId];

        _vote(_tokenId, _weight, _poolVote, _weights);
    }

    function whitelistNFT(uint256 _tokenId, bool _bool) external {
        address _sender = _msgSender();
        if (_sender != governor) revert NotGovernor();
        isWhitelistedNFT[_tokenId] = _bool;
        emit WhitelistNFT(_sender, _tokenId, _bool);
    }

    function setPool(address _pool) external nonReentrant returns (address) {
        address sender = _msgSender();

        if (sender != governor) revert NotGovernor();
        pools.push(_pool);

        emit PoolSet(_pool, sender);
        return _pool;
    }

    function setAlive(bool _set) external {
        if (_msgSender() != emergencyCouncil) revert NotEmergencyCouncil();
        isAlive = _set;
    }

    function length() external view returns (uint256) {
        return pools.length;
    }
    
    function _reset(uint256 _tokenId) internal {
        address[] storage _poolVote = poolVote[_tokenId];
        uint256 _poolVoteCnt = _poolVote.length;
        uint256 _totalWeight = 0;

        for (uint256 i = 0; i < _poolVoteCnt; i++) {
            address _pool = _poolVote[i];
            uint256 _votes = votes[_tokenId][_pool];

            if (_votes != 0) {
                weights[_pool] -= _votes;
                delete votes[_tokenId][_pool];

                voteOnTokenId[_tokenId] -= _votes;

                _totalWeight += _votes;
                emit Abstained(
                    _msgSender(),
                    _pool,
                    _tokenId,
                    _votes,
                    weights[_pool],
                    block.timestamp
                );
            }
        }
        voted[_tokenId] = false;

        totalWeight -= _totalWeight;
        usedWeights[_tokenId] = 0;
        delete poolVote[_tokenId];
    }
}
