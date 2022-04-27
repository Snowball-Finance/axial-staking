import { solidity } from "ethereum-waffle"

// eslint-disable-next-line node/no-missing-import
import { VestingStake, AccruingStake, ERC20TokenMock, Governance } from "../typechain"
import chai from "chai"
import { ethers } from "hardhat"
import { BigNumber, Signer } from "ethers"
import { getCostOfAVAXPerGas, gasCostToBlockLimit, gasCostToAvax, gasCostToUSD } from "./utils";
import { exec } from "child_process"

chai.use(solidity)
const { expect } = chai

async function increaseTimestamp(amount: number) {
  await ethers.provider.send('evm_increaseTime', [amount]);
  await ethers.provider.send('evm_mine', []);
}

describe("Governance", () => {
  let deployer: Signer
  let governance: Signer
  let alice: Signer
  let bob: Signer
  let carol: Signer

  let axialToken: ERC20TokenMock
  let stakingVe: VestingStake
  let stakingAc: AccruingStake
  let voteGovernance: Governance

  let aliceAddr: string
  let bobAddr: string
  let carolAddr: string
  let governanceAddr: string

  // 60s/min, 60m/hr, 24hr/day, 7day/wk, 52wk/yr
  const SECONDS_IN_A_YEAR = 60 * 60 * 24 * 7 * 52
  const SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7
  const SECONDS_IN_A_DAY = 60 * 60 * 24
  const NUM_VOTES_REQUIRED : BigNumber = BigNumber.from("250000000000000000000000")

  beforeEach(async () => {
    [deployer, governance, alice, bob, carol] = await ethers.getSigners()

    aliceAddr = await alice.getAddress()
    bobAddr = await bob.getAddress()
    carolAddr = await carol.getAddress()
    governanceAddr = await governance.getAddress()

    const stakingVeFactory = await ethers.getContractFactory("VestingStake");
    const stakingAcFactory = await ethers.getContractFactory("AccruingStake");

    axialToken = await (await ethers.getContractFactory("ERC20TokenMock")).deploy("Axial", "AXIAL");

    await axialToken.connect(deployer).mints([ await deployer.getAddress(), aliceAddr, bobAddr, carolAddr, ], [NUM_VOTES_REQUIRED, NUM_VOTES_REQUIRED, NUM_VOTES_REQUIRED, NUM_VOTES_REQUIRED])

    stakingVe = await stakingVeFactory.deploy(axialToken.address, "sAxial", "SAXIAL", await governance.getAddress())
    stakingAc = await stakingAcFactory.deploy(axialToken.address, "veAxial", "VEAXIAL", await governance.getAddress())

    const governanceFactory = await ethers.getContractFactory("Governance");
    voteGovernance = await governanceFactory.deploy(stakingVe.address);
  })

  // Test cases:

  it("User cannot propose if they do not have enough staked", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, 100);
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR * 2, 100, false);

    let executionContexts = await voteGovernance.connect(alice).constructProposalExecutionContexts([],[],[],[]);
    let metaData = await voteGovernance.connect(alice).constructProposalMetadata("Test title", "Test Metadata", SECONDS_IN_A_WEEK, true);
    await expect(voteGovernance.connect(alice).propose(metaData, executionContexts)).to.be.revertedWith(
                                          "Governance::propose: proposer votes below proposal threshold");
  })

  it("User can propose if they have enough staked", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, NUM_VOTES_REQUIRED)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR * 2, NUM_VOTES_REQUIRED, false);

    // Propose() :
    // string calldata _title,
    // string calldata _metadata,
    // uint256 _votingPeriod,
    // string[] calldata _executionLabels,
    // address[] calldata _targets,
    // uint256[] calldata _values,
    // bytes[] memory _data,
    // bool _isBoolean

    let actionApproveSAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingVe.address, 500]);
    let actionStakeSAXIAL = stakingVe.interface.encodeFunctionData("stake", [SECONDS_IN_A_YEAR * 2, 500, false]);
    let actionApproveVEAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingAc.address, 500]);
    let actionStakeVEAXIAL = stakingAc.interface.encodeFunctionData("stake", [500]);

    let labels = ["Governance Approve 500 for Staked Axial", 
                  "Governance Stake 500 Axial into sAxial", 
                  "Governance Approve 500 for veAxial", 
                  "Governance Stake 500 Axial into veAxial"];

    let targets = [axialToken.address, stakingVe.address, axialToken.address, stakingAc.address];
    let values = [0, 0, 0, 0];
    let data = [actionApproveSAXIAL, actionStakeSAXIAL, actionApproveVEAXIAL, actionStakeVEAXIAL];

    let executionContexts = await voteGovernance.connect(alice).constructProposalExecutionContexts(labels, targets, values, data);
    let metaData = await voteGovernance.connect(alice).constructProposalMetadata("Test Title", "Test Metadata", SECONDS_IN_A_WEEK, true);

    // console.log(executionContexts);
    // console.log(metaData);
    await voteGovernance.connect(alice).propose(metaData, executionContexts);
  })

  it("Proposal reverts when malformed arguments are provided", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, NUM_VOTES_REQUIRED);
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR * 2, NUM_VOTES_REQUIRED, false);

    let actionApproveSAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingVe.address, 500]);
    let actionStakeSAXIAL = stakingVe.interface.encodeFunctionData("stake", [SECONDS_IN_A_YEAR * 2, 500, false]);
    let actionApproveVEAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingAc.address, 500]);
    let actionStakeVEAXIAL = stakingAc.interface.encodeFunctionData("stake", [500]);

    let labels = ["Governance Approve 500 for Staked Axial", 
                  "Governance Stake 500 Axial into sAxial", 
                  //"Governance Approve 500 for veAxial", 
                  "Governance Stake 500 Axial into veAxial"];

    let targets = [axialToken.address, stakingVe.address, axialToken.address, stakingAc.address];
    let values = [0, 0, 0, 0];
    let data = [actionApproveSAXIAL, actionStakeSAXIAL, actionApproveVEAXIAL, actionStakeVEAXIAL];

    await expect(voteGovernance.connect(alice).constructProposalExecutionContexts(labels, targets, values, data)).to.be.revertedWith("!length");

    // let executionContexts = await voteGovernance.connect(alice).constructProposalExecutionContexts(labels, targets, values, data);
    // let metaData = await voteGovernance.connect(alice).constructProposalMetadata("Test title", "Test Metadata", SECONDS_IN_A_WEEK, true);
    // await expect(voteGovernance.connect(alice).propose(metaData, executionContexts)).to.be.revertedWith(
    //                                       "Governance::propose: proposer votes below proposal threshold");
  })

  it("Users can vote for yes/no proposals", async() => {
    await axialToken.connect(alice).approve(stakingVe.address, NUM_VOTES_REQUIRED)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR * 2, NUM_VOTES_REQUIRED, false);

    let actionApproveSAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingVe.address, 500]);
    let actionStakeSAXIAL = stakingVe.interface.encodeFunctionData("stake", [SECONDS_IN_A_YEAR * 2, 500, false]);
    let actionApproveVEAXIAL = axialToken.interface.encodeFunctionData("approve", [stakingAc.address, 500]);
    let actionStakeVEAXIAL = stakingAc.interface.encodeFunctionData("stake", [500]);

    let labels : string[] = [];
    let targets : string[] = [];
    let values : BigNumber[] = [];
    let data : string[] = [];

    let executionContexts = await voteGovernance.connect(alice).constructProposalExecutionContexts(labels, targets, values, data);
    let metaData = await voteGovernance.connect(alice).constructProposalMetadata("Test Title", "Test Metadata", SECONDS_IN_A_WEEK, true);

    // console.log(executionContexts);
    // console.log(metaData);
    await voteGovernance.connect(alice).propose(metaData, executionContexts);

    await voteGovernance.connect(alice).vote(0, 0);

    let receipt = await voteGovernance.getReceipt(0, aliceAddr);
    console.log(receipt);
  })

})