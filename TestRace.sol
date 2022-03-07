// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "governance/Governor.sol";
import "governance/extensions/GovernorSettings.sol";
import "governance/extensions/GovernorCountingSimple.sol";
import "governance/extensions/GovernorVotes.sol";
import "governance/extensions/GovernorVotesQuorumFraction.sol";

contract TestRace is Governor, GovernorSettings, GovernorCountingSimple, GovernorVotes, GovernorVotesQuorumFraction {
    constructor(IVotes _token)
        Governor("TestRace")
        GovernorSettings(5 /* 1 minute */, 45 /* 10 minutes */, 1e18)
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(5)
    {}

    // The following functions are overrides required by Solidity.

    function votingDelay()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingDelay();
    }

    function votingPeriod()
        public
        view
        override(IGovernor, GovernorSettings)
        returns (uint256)
    {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function getVotes(address account, uint256 blockNumber)
        public
        view
        override(IGovernor, GovernorVotes)
        returns (uint256)
    {
        return super.getVotes(account, blockNumber);
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }
}
