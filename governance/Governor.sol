// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (governance/Governor.sol)

pragma solidity ^0.8.0;

import "../utils/cryptography/ECDSA.sol";
import "../utils/cryptography/draft-EIP712.sol";
import "../utils/introspection/ERC165.sol";
import "../utils/math/SafeCast.sol";
import "../utils/Address.sol";
import "../utils/Context.sol";
import "./IGovernor.sol";

/**
 * @dev Core of the governance system, designed to be extended though various modules.
 *
 * This contract is abstract and requires several function to be implemented in various modules:
 *
 * - A counting module must implement {quorum}, {_quorumReached}, {_voteSucceeded} and {_countVote}
 * - A voting module must implement {getVotes}
 * - Additionaly, the {votingPeriod} must also be implemented
 *
 * _Available since v4.3._
 */
abstract contract Governor is Context, ERC165, EIP712, IGovernor {
    using SafeCast for uint256;

    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");

    uint256[] public _proposalIds;

    struct ProposalCore {
        address author;
        string description;
        bool exists;
    }

    string private _name;
    bool private _canceled;
    mapping(uint256 => ProposalCore) private _proposals;
    mapping(address => bool) private _hasSubmitted;


    /**
     * @dev Restrict access of functions to the governance executor, which may be the Governor itself or a timelock
     * contract, as specified by {_executor}. This generally means that function with this modifier must be voted on and
     * executed through the governance protocol.
     */
    modifier onlyGovernance() {
        require(_msgSender() == _executor(), "Governor: onlyGovernance");
        _;
    }

    /**
     * @dev Sets the value for {name} and {version}
     */
    constructor(string memory name_) EIP712(name_, version()) {
        _name = name_;
    }

    /**
     * @dev Function to receive ETH that will be handled by the governor (disabled if executor is a third party contract)
     */
    receive() external payable virtual {
        require(_executor() == address(this));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC165) returns (bool) {
        return interfaceId == type(IGovernor).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IGovernor-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IGovernor-version}.
     */
    function version() public view virtual override returns (string memory) {
        return "1";
    }

    /**
     * @dev See {IGovernor-hashProposal}.
     *
     * The proposal id is produced by hashing the RLC encoded `targets` array, the `values` array, the `calldatas` array
     * and the descriptionHash (bytes32 which itself is the keccak256 hash of the description string). This proposal id
     * can be produced from the proposal data which is part of the {ProposalCreated} event. It can even be computed in
     * advance, before the proposal is submitted.
     *
     * Note that the chainId and the governor address are not part of the proposal id computation. Consequently, the
     * same proposal (with same operation and same description) will have the same id if submitted on multiple governors
     * accross multiple networks. This also means that in order to execute the same operation twice (on the same
     * governor) the proposer will have to change the description in order to avoid proposal id conflicts.
     */
    function hashProposal(
        string memory proposalDescription
    ) public pure virtual override returns (uint256) {
        return uint256(keccak256(abi.encode(proposalDescription)));
    }

    /**
     * @dev See {IGovernor-state}.
     */
    function state() public view virtual override returns (ContestState) {
        if (_canceled) {
            return ContestState.Canceled;
        }

        uint256 snapshot = contestSnapshot();

        if (snapshot >= block.number) {
            return ContestState.Queued;
        }

        uint256 deadline = contestDeadline();

        if (deadline >= block.number) {
            return ContestState.Active;
        }

        return ContestState.Completed;
    }
    
    /**
     * @dev Return all proposals.
     */
    function getAllProposalIds() public view virtual returns (uint256[] memory) {
        return _proposalIds;
    }

    /**
     * @dev See {IGovernor-contestStart}.
     */
    function contestStart() public view virtual override returns (uint256) {
        return 0;
    }

    /**
     * @dev See {IGovernor-contestSnapshot}.
     */
    function contestSnapshot() public view virtual override returns (uint256) {
        return contestStart() + votingDelay();
    }

    /**
     * @dev See {IGovernor-contestDeadline}.
     */
    function contestDeadline() public view virtual override returns (uint256) {
        return contestSnapshot() + votingPeriod();
    }

    /**
     * @dev Part of the Governor Bravo's interface: _"The number of votes required in order for a voter to become a proposer"_.
     */
    function proposalThreshold() public view virtual returns (uint256) {
        return 0;
    }

    /**
     * @dev Max number of proposals allowed in this contest
     */
    function maxProposalCount() public view virtual returns (uint256) {
        return 100;
    }

    /**
     * @dev Retrieve proposal data"_.
     */
    function getProposal(uint256 proposalId) public view virtual returns (ProposalCore memory) {
        return _proposals[proposalId];
    }

    /**
     * @dev Register a vote with a given support and voting weight.
     *
     * Note: Support is generic and can represent various things depending on the voting system used.
     */
    function _countVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 numVotes,
        uint256 totalVotes
    ) internal virtual;

    /**
     * @dev See {IGovernor-propose}.
     */
    function propose(
        string memory proposalDescription
    ) public virtual override returns (uint256) {
        require(state() == ContestState.Queued, "Governor: contest must be queued for proposals to be submitted");
        require(_hasSubmitted[msg.sender] != true, "Governor: the same address cannot submit more than one proposal");
        require(_proposalIds.length < maxProposalCount(), "Governor: the max number of proposals have been submitted");
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold(),
            "GovernorCompatibilityBravo: proposer votes below proposal threshold"
        );

        require(bytes(proposalDescription).length != 0, "Governor: empty proposal");

        uint256 proposalId = hashProposal(proposalDescription);
        require(!_proposals[proposalId].exists, "Governor: duplicate proposals not allowed");

        _proposalIds.push(proposalId);
        _proposals[proposalId] = ProposalCore({author: msg.sender, description: proposalDescription, exists: true});
        _hasSubmitted[msg.sender] = true;

        emit ProposalCreated(
            proposalId,
            _msgSender(),
            proposalDescription
        );

        return proposalId;
    }

    /**
     * @dev Internal cancel mechanism: locks up the proposal timer, preventing it from being re-submitted. Marks it as
     * canceled to allow distinguishing it from executed proposals.
     *
     * Emits a {IGovernor-ProposalCanceled} event.
     */
    function cancel() public virtual onlyGovernance() {
        ContestState status = state();
        
        require(
            status != ContestState.Canceled && status != ContestState.Completed,
            "Governor: contest not active"
        );

        emit ContestCanceled();
    }

    /**
     * @dev See {IGovernor-castVote}.
     */
    function castVote(uint256 proposalId, uint8 support, uint256 numVotes) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, numVotes, "");
    }

    /**
     * @dev See {IGovernor-castVoteWithReason}.
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        uint256 numVotes,
        string calldata reason
    ) public virtual override returns (uint256) {
        address voter = _msgSender();
        return _castVote(proposalId, voter, support, numVotes, reason);
    }

    /**
     * @dev See {IGovernor-castVoteBySig}.
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 numVotes,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual override returns (uint256) {
        address voter = ECDSA.recover(
            _hashTypedDataV4(keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support))),
            v,
            r,
            s
        );
        return _castVote(proposalId, voter, support, numVotes, "");
    }

    /**
     * @dev Internal vote casting mechanism: Check that the vote is pending, that it has not been cast yet, retrieve
     * voting weight using {IGovernor-getVotes} and call the {_countVote} internal function.
     *
     * Emits a {IGovernor-VoteCast} event.
     */
    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support,
        uint256 numVotes,
        string memory reason
    ) internal virtual returns (uint256) {
        require(state() == ContestState.Active, "Governor: vote not currently active");
        require(numVotes > 0, "GovernorVotingSimple: cannot vote with 0 or fewer votes");

        uint256 totalVotes = getVotes(account, contestSnapshot());
        _countVote(proposalId, account, support, numVotes, totalVotes);

        emit VoteCast(account, proposalId, support, numVotes, reason);

        return totalVotes;
    }

    /**
     * @dev Address through which the governor executes action. Will be overloaded by module that execute actions
     * through another contract such as a timelock.
     */
    function _executor() internal view virtual returns (address) {
        return address(this);
    }
}
