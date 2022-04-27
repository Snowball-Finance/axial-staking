// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

/// @title A governance contract for proposals, voting, and execution
/// @author Auroter
/// @notice Uses the StakedAxial contract to determine users voting power
/// @notice Multiple executions can be included in a single yes/no proposal
/// @notice Multiple-choice proposals are also valid and can be used to select a specific execution context

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "hardhat/console.sol";

interface IsAxial {
  function balanceOf(address _account) external view returns (uint256);
}

contract Governance is ReentrancyGuard, Ownable {

    /// @notice Lower bound for the voting period
    uint256 public minimumVotingPeriod = 3 days;
    uint256 public constant VOTING_PERIOD_MINIMUM = 1 days;
    uint256 public constant VOTING_PERIOD_MAXIMUM = 30 days;

    /// @notice Seconds since the end of the voting period before the proposal can be executed
    uint256 public executionDelay = 24 hours;
    uint256 public constant EXECUTION_DELAY_MINIMUM = 30 seconds;
    uint256 public constant EXECUTION_DELAY_MAXIMUM = 30 days;

    /// @notice Seconds since the proposal could be executed until it is considered expired
    uint256 public constant EXPIRATION_PERIOD = 14 days;

    /// @notice The required minimum number of votes in support of a proposal for it to succeed
    uint256 public quorumVotes = 300_000e18;
    uint256 public constant QUORUM_VOTES_MINIMUM = 100_000e18;
    uint256 public constant QUORUM_VOTES_MAXIMUM = 18_000_000e18;

    /// @notice The minimum number of votes required for an account to create a proposal
    uint256 public proposalThreshold = 100_000e18;
    uint256 public constant PROPOSAL_THRESHOLD_MINIMUM = 50_000e18;
    uint256 public constant PROPOSAL_THRESHOLD_MAXIMUM = 10_000_000e18;

    /// @notice The total number of proposals
    uint256 public proposalCount;

    /// @notice The record of all proposals ever proposed
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => Receipt)) public receipts;
    mapping(address => uint256) public lastProposalByAddress;

    /// @notice Non-tradeable sAXIAL used to represent votes
    IsAxial public sAXIAL;

    struct Proposal {
        string title;
        string metadata;
        address proposer;
        address executor;
        uint256 startTime;
        uint256 votingPeriod;
        uint256 quorumVotes;
        uint256 executionDelay;
        uint256[] votes;
        bool isBoolean;
        ProposalExecutionContextList executionContexts;
    }

    struct ProposalExecutionContext {
        string label; // Description of execution context
        address target; // The contract we wish to manipulate
        uint256 value; // We set this if the function requires native AVAX
        bytes data; // *encoded* function and parameters being executed at target
    }

    struct ProposalExecutionContextList {
        uint256 length;
        ProposalExecutionContext[] contexts;
    }

    struct Receipt {
        bool hasVoted; // did the user vote
        uint256 support; // what did user vote for?
        uint256 votes; // weight of the users vote
    }

    enum ProposalState {
        Active,
        Defeated,
        PendingExecution,
        ReadyForExecution,
        Executed,
        Expired
    }

    // emitted whenever a user votes
    event NewVote(
        uint256 proposalId,
        address voter,
        uint256 support,
        uint256 votes
    );

    event ProposalCreated(uint256 proposalId, address proposer, string title);
    event ProposalExecuted(uint256 proposalId, address executor);
    event MinimumVotingPeriodChanged(uint256 newMinimumVotingPeriod);
    event ExecutionDelayChanged(uint256 newExecutionDelay);
    event QuorumVotesChanges(uint256 newQuorumVotes);
    event ProposalThresholdChanged(uint256 newProposalThreshold);

    /// @notice Constructor
    /// @param _sAXIAL the address of the contract which determines each users voting power
    /// @dev This token must not be tradeable
    constructor(address _sAXIAL) {
        sAXIAL = IsAxial(_sAXIAL);
    }

    // Setters

    function setMinimumVotingPeriod(uint256 _seconds) public onlyOwner {
        require(
            _seconds >= VOTING_PERIOD_MINIMUM,
            "Governance::setMinimumVotingPeriod: TOO_SMALL"
        );
        require(
            _seconds <= VOTING_PERIOD_MAXIMUM,
            "Governance::setMinimumVotingPeriod: TOO_LARGE"
        );
        minimumVotingPeriod = _seconds;
        emit MinimumVotingPeriodChanged(_seconds);
    }

    function setExecutionDelay(uint256 _seconds) public onlyOwner {
        require(
            _seconds >= EXECUTION_DELAY_MINIMUM,
            "Governance::setExecutionDelay: TOO_SMALL"
        );
        require(
            _seconds <= EXECUTION_DELAY_MAXIMUM,
            "Governance::setExecutionDelay: TOO_LARGE"
        );
        executionDelay = _seconds;
        emit ExecutionDelayChanged(_seconds);
    }

    function setQuorumVotes(uint256 _votes) public onlyOwner {
        require(
            _votes >= QUORUM_VOTES_MINIMUM,
            "Governance::setQuorumVotes: TOO_SMALL"
        );
        require(
            _votes <= QUORUM_VOTES_MAXIMUM,
            "Governance::setQuorumVotes: TOO_LARGE"
        );
        quorumVotes = _votes;
        emit QuorumVotesChanges(_votes);
    }

    function setProposalThreshold(uint256 _votes) public onlyOwner {
        require(
            _votes >= PROPOSAL_THRESHOLD_MINIMUM,
            "Governance::setProposalThreshold: TOO_SMALL"
        );
        require(
            _votes <= PROPOSAL_THRESHOLD_MAXIMUM,
            "Governance::setProposalThreshold: TOO_LARGE"
        );
        proposalThreshold = _votes;
        emit ProposalThresholdChanged(_votes);
    }

    /// @notice View the current status of any proposal
    /// @param _proposalId the index of the proposal we wish to view the State of
    /// @return ProposalState enum representing the status of the selected proposal
    function state(uint256 _proposalId) public view returns (ProposalState) {
        require(
            _proposalId < proposalCount,
            "Governance::state: invalid proposal id"
        );

        Proposal memory proposal = proposals[_proposalId];

        // These states are each being a precondition of the next state

        // The proposal is currently allowing votes
        if (block.timestamp <= proposal.startTime + proposal.votingPeriod) {
            return ProposalState.Active;
        }

        // The proposal is no longer allowing votes and has been executed
        if (proposal.executor != address(0)) {
            return ProposalState.Executed;
        }

        // The proposal is yes/no and the yes votes did not exceed the no votes, or the yes notes did not exceed quorum
        if (proposal.isBoolean && (proposal.votes[1] <= proposal.votes[0] || proposal.votes[1] < proposal.quorumVotes)) {
            return ProposalState.Defeated;
        }

        // The proposal is multiple choice and none of the choices exceeded quorum
        if (!proposal.isBoolean) {
            bool multipleChoiceDefeated = true;
            for (uint256 i = 0; i < proposal.votes.length; ++i) {
                if (proposal.votes[i] >= proposal.quorumVotes) {
                    multipleChoiceDefeated = false;
                }
            }
            if (multipleChoiceDefeated) {
                return ProposalState.Defeated;
            }
        }

        // We are still in the execution delay window
        if (block.timestamp < proposal.startTime + proposal.votingPeriod + proposal.executionDelay) {
            return ProposalState.PendingExecution;
        }

        // We have not yet exceeded the expiration period
        if (block.timestamp < proposal.startTime + proposal.votingPeriod + proposal.executionDelay + EXPIRATION_PERIOD) {
            return ProposalState.ReadyForExecution;
        }

        // None of the previous conditions were met therefore the proposal has expired
        return ProposalState.Expired;
    }

    /// @param _proposalId the index of the proposal we wish to view the receipt for
    /// @param _voter the user we wish to view the receipt for
    /// @return Receipt A copy of the voters selection for the provided proposal
    function getReceipt(uint256 _proposalId, address _voter) public view returns (Receipt memory) {
        return receipts[_proposalId][_voter];
    }

    function constructProposalExecutionContexts(string[] calldata _labels, 
                                               address[] calldata _targets, 
                                               uint256[] calldata _values, 
                                               bytes[] calldata _data) 
                                               public pure returns (ProposalExecutionContextList memory) {
        require(_labels.length == _targets.length && _targets.length == _values.length && _values.length == _data.length, "!length");
        uint256 length = _labels.length;
        ProposalExecutionContextList memory list;
        list.length = length;
        list.contexts = new ProposalExecutionContext[](length);
            for (uint256 i = 0; i < length; ++i) {
                ProposalExecutionContext memory newProposalExecutionContext = ProposalExecutionContext({
                    label: _labels[i],
                    target: _targets[i],
                    value: _values[i],
                    data: _data[i]
                });

                list.contexts[i] = newProposalExecutionContext;
            }
        return list;
    }

    function constructProposalMetadata(string calldata _title, 
                                       string calldata _metadata, 
                                       uint256 _votingPeriod, 
                                       bool _isBoolean) 
                                       public pure returns (Proposal memory) {
        Proposal memory metaData;
        metaData.title = _title;
        metaData.metadata = _metadata;
        metaData.votingPeriod = _votingPeriod;
        metaData.isBoolean = _isBoolean;
        return metaData;
    }

    /// @notice Allows any user with sufficient priviledges to propose a new vote
    /// @param _metaData Metadata struct generated via constructProposalMetadata
    /// @param _executionContexts Execution struct generated via constructExecutionContexts
    function propose(
        Proposal memory _metaData,
        ProposalExecutionContextList memory _executionContexts
    ) public  {
        require(_executionContexts.length == _executionContexts.contexts.length,
            "Governance::propose: Malformed execution contexts list"
        );

        require(
            _metaData.votingPeriod >= minimumVotingPeriod,
            "Governance::propose: voting period too short"
        );

        require(
            _metaData.votingPeriod <= VOTING_PERIOD_MAXIMUM,
            "Governance::propose: voting period too long"
        );

        uint256 lastProposalId = lastProposalByAddress[msg.sender];

        // Prevent the same person from having concurrent proposals
        if (lastProposalId > 0) {
            ProposalState proposalState = state(lastProposalId);
            require(
                proposalState == ProposalState.Executed ||
                proposalState == ProposalState.Defeated ||
                proposalState == ProposalState.Expired,
                "Governance::propose: proposer already has a proposal in progress"
            );
        }

        uint256 votes = sAXIAL.balanceOf(msg.sender);

        // user needs to have enough voting power to be allowed to propose
        require(
            votes > proposalThreshold,
            "Governance::propose: proposer votes below proposal threshold"
        );

        // Allocate voting options
        uint256[] memory isMultipleChoice;
        if (!_metaData.isBoolean) {
            isMultipleChoice = new uint256[](_executionContexts.length);
        } else {
            isMultipleChoice = new uint256[](2); // 0: No, 1: Yes
        }

        Proposal storage newProposal = proposals[proposalCount];
        newProposal.title = _metaData.title;
        newProposal.metadata = _metaData.metadata;
        newProposal.proposer = msg.sender;
        newProposal.executor = address(0);
        newProposal.startTime = block.timestamp;
        newProposal.votingPeriod = _metaData.votingPeriod;
        newProposal.quorumVotes = quorumVotes;
        newProposal.executionDelay = executionDelay;
        newProposal.votes = isMultipleChoice;
        newProposal.isBoolean = _metaData.isBoolean;
        for (uint256 i = 0; i < _executionContexts.length; ++i) {
            newProposal.executionContexts.contexts.push(_executionContexts.contexts[i]);
        }
        newProposal.executionContexts.length = _executionContexts.length;


        //Save new proposal to state
        //proposals[proposalCount] = newProposal;
        lastProposalByAddress[msg.sender] = proposalCount;

        ++proposalCount;

        emit ProposalCreated(proposalCount, newProposal.proposer, newProposal.title);
    }

    /// @notice Vote for selected option
    /// @param _proposalId the index of the proposal the user wishes to vote for or against
    /// @param _support index of the option the user wishes to cast their vote for
    /// @dev If the proposal is binary, 0 means No and 1 means Yes
    function vote(uint256 _proposalId, uint256 _support) public nonReentrant {
        require(
            state(_proposalId) == ProposalState.Active,
            "Governance::vote: voting is closed"
        );

        // directly talk to state memory
        Proposal storage proposal = proposals[_proposalId];
        Receipt storage receipt = receipts[_proposalId][msg.sender];

        uint256 votes = sAXIAL.balanceOf(msg.sender);
        console.log("votes=", votes);

        // Remove any previous votes if the user cast them already
        if (receipt.hasVoted) {
            proposal.votes[receipt.support] -= receipt.votes;
        }

        // Increment votes for option user has now selected
        proposal.votes[_support] += votes;

        // Update users receipt
        receipt.hasVoted = true;
        receipt.support = _support;
        receipt.votes = votes;

        emit NewVote(_proposalId, msg.sender, _support, votes);
    }

    /// @notice Allow any user to execute the proposal if it is in the execution stage
    /// @param _proposalId the index of the proposal we wish to execute
    /// @return bytes array the executed function/s returned
    function execute(uint256 _proposalId) public payable nonReentrant returns (bytes[] memory) {
        require(
            state(_proposalId) == ProposalState.ReadyForExecution,
            "Governance::execute: cannot be executed"
        );

        Proposal storage proposal = proposals[_proposalId];

        ProposalExecutionContextList storage proposalExecution = proposal.executionContexts;

        bytes[] memory returnDatas;

        // If yes/no options were given, execute all
        if (proposal.isBoolean) {
            returnDatas = new bytes[](proposalExecution.length);
            for (uint256 i = 0; i < proposalExecution.length; ++i) {
                (bool success, bytes memory returnData) = proposalExecution.contexts[i].target.call{
                                                   value: proposalExecution.contexts[i].value}(
                                                          proposalExecution.contexts[i].data);
                require(
                    success,
                    "Governance::execute: transaction execution reverted."
                );
                returnDatas[i] = returnData;
            }
        } else {
            // If multiple choice, execute the option with the most votes
            returnDatas = new bytes[](1);
            uint256 contextToExecute = 0;
            uint256 maxVotes = proposal.quorumVotes;
            for (uint256 i = 0; i < proposal.votes.length; ++i) {
                if (proposal.votes[i] > maxVotes) {
                    maxVotes = proposal.votes[i];
                    contextToExecute = i;
                }
            }
            (bool success, bytes memory returnData) = proposalExecution.contexts[contextToExecute].target.call{
                                               value: proposalExecution.contexts[contextToExecute].value}(
                                                      proposalExecution.contexts[contextToExecute].data);
            require(
                success,
                "Governance::execute: transaction execution reverted."
            );
            returnDatas[0] = returnData;
        }

        proposal.executor = msg.sender;

        emit ProposalExecuted(_proposalId, proposal.executor);

        return returnDatas;
    }
}