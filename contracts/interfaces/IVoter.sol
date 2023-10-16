// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IVoter {

    error AlreadyVotedOrDeposited();
    error DistributeWindow();
    error GaugeAlreadyKilled();
    error GaugeAlreadyRevived();
    error GaugeExists();
    error GaugeDoesNotExist(address _pool);
    error GaugeNotAlive(uint16 _gauge);
    error MaximumVotingNumberTooLow();
    error NonZeroVotes();
    error NotGovernor();
    error NotEmergencyCouncil();
    error NotWhitelistedUser();
    error SameValue();
    error TooManyPools();
    error UnequalLengths();
    error ZeroBalance();
    error ZeroAddress();

    event GaugeKilled(uint16 indexed gauge);
    event GaugeRevived(uint16 indexed gauge);
    event GaugeSet(uint16 indexed gauge, address indexed pool, address indexed governor);

    event Voted(
        address indexed voter,
        address indexed pool,
        address indexed user,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event Abstained(
        address indexed voter,
        address indexed pool,
        address indexed user,
        uint256 weight,
        uint256 totalWeight,
        uint256 timestamp
    );
    event WhitelistUser(address indexed whitelister, address indexed user, bool indexed _bool);
    

    /// @notice Called by users to vote for pools. Votes distributed proportionally based on weights.
    ///         Can only vote for gauges that have not been killed.
    /// @dev Weights are distributed proportional to the sum of the weights in the array.
    ///      Throws if length of _poolVote and _weights do not match.
    /// @param _poolVote    Array of pools you are voting for.
    /// @param _weights     Weights of pools.
    function vote(address[] calldata _poolVote, uint256[] calldata _weights) external;

    /// @notice Called by users to update voting balances in voting rewards contracts.
    function poke() external;

    /// @notice Called by users to reset voting state.
    ///         Cannot reset in the same epoch that you voted in.
    function reset() external;

    /// @notice Set new governor.
    /// @dev Throws if not called by governor.
    /// @param _governor .
    function setGovernor(address _governor) external;

    /// @notice Set new emergency council.
    /// @dev Throws if not called by emergency council.
    /// @param _emergencyCouncil .
    function setEmergencyCouncil(address _emergencyCouncil) external;

    /// @notice Set maximum number of gauges that can be voted for.
    /// @dev Throws if not called by governor.
    ///      Throws if _maxVotingNum is too low.
    ///      Throws if the values are the same.
    /// @param _maxVotingNum .
    function setMaxVotingNum(uint256 _maxVotingNum) external;

    /// @notice Whitelist (or unwhitelist) user for voting in last hour prior to epoch flip.
    /// @dev Throws if not called by governor.
    ///      Throws if already whitelisted.
    /// @param _user .
    /// @param _bool .
    function whitelistUser(address _user, bool _bool) external;
}
