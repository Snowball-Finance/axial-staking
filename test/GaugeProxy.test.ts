/* eslint-disable node/no-missing-import */
/* eslint-disable camelcase */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20TokenMock,
  ERC20TokenMock__factory,
  GaugeProxy,
  GaugeProxy__factory,
  StakedAxialToken,
  StakedAxialToken__factory,
} from "../typechain";
import { SECONDS_IN_A_YEAR } from "./constants";

let gaugeProxy: GaugeProxy;
let axial: ERC20TokenMock;
let sAxial: StakedAxialToken;
let veAxial: ERC20TokenMock;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;

let testTokenAddress: string;

// GOAL: Test that allows user to stake sAxial

describe.only("Gauge Proxy Tests", function () {
  beforeEach(async function () {
    await setupTest();
  });

  it("Should allow user to vote using sAxial power", async function () {
    const userBalanceBeforeStake = await axial.balanceOf(alice.address);
    expect(userBalanceBeforeStake).to.eq(await axial.maxSupply());

    // Approve max spend of users axial
    await axial.connect(alice).approve(sAxial.address, await axial.maxSupply());

    // Stake axial
    const powerBeforeStake = await sAxial.getPower(alice.address);
    expect(powerBeforeStake).to.eq(0);

    await sAxial.connect(alice).stake(SECONDS_IN_A_YEAR, 100, false);

    const userBalanceAfterStake = await axial.balanceOf(alice.address);
    expect(userBalanceAfterStake).to.eq(userBalanceBeforeStake.sub(100));

    // Check user has some voting power
    const powerAfterStake = await sAxial.getPower(alice.address);
    expect(powerAfterStake).to.gt(0);

    const tokenWeightBeforeVote = await gaugeProxy.weights(testTokenAddress);
    expect(tokenWeightBeforeVote).to.eq(0);

    const userTokenVotesBefore = await gaugeProxy.votes(
      alice.address,
      testTokenAddress
    );
    expect(userTokenVotesBefore).to.eq(0);

    // Vote on gauge proxy for test token
    await gaugeProxy.connect(alice).vote([testTokenAddress], [100]);

    const tokenWeightAfterVote = await gaugeProxy.weights(testTokenAddress);
    expect(tokenWeightAfterVote).to.gt(0);

    const userTokenVotesAfter = await gaugeProxy.votes(
      alice.address,
      testTokenAddress
    );
    expect(userTokenVotesAfter).to.gt(0);
  });

  it("Should not allow user without sAxial to vote", async function () {
    const bobAxialBalance = await axial.balanceOf(bob.address);
    expect(bobAxialBalance).to.eq(0);

    // Check user has zero voting power
    const bobVotingPower = await sAxial.getPower(bob.address);
    expect(bobVotingPower).to.eq(0);

    const tokenWeightBeforeVote = await gaugeProxy.weights(testTokenAddress);
    expect(tokenWeightBeforeVote).to.eq(0);

    const userTokenVotesBefore = await gaugeProxy.votes(
      bob.address,
      testTokenAddress
    );
    expect(userTokenVotesBefore).to.eq(0);

    // Vote on gauge proxy for test token
    await gaugeProxy.connect(bob).vote([testTokenAddress], [100]);

    const tokenWeightAfterVote = await gaugeProxy.weights(testTokenAddress);
    expect(tokenWeightAfterVote).to.eq(0);

    const userTokenVotesAfter = await gaugeProxy.votes(
      bob.address,
      testTokenAddress
    );
    expect(userTokenVotesAfter).to.eq(0);
  });
});

async function setupTest() {
  [deployer, alice, bob] = await ethers.getSigners();

  // Deploy Axial
  axial = await new ERC20TokenMock__factory(deployer).deploy("Axial", "AXIAL");

  // Deploy sAxial
  sAxial = await new StakedAxialToken__factory(deployer).deploy(axial.address);

  // Deploy veAxial
  veAxial = await new ERC20TokenMock__factory(deployer).deploy(
    "veAxial",
    "veAxial"
  );

  // Deploy gauge proxy
  gaugeProxy = await new GaugeProxy__factory(deployer).deploy(
    deployer.address,
    axial.address,
    sAxial.address,
    veAxial.address
  );

  // Get random fake LP token
  testTokenAddress = ethers.Wallet.createRandom().address;

  // Add gauge for fake token
  await gaugeProxy.connect(deployer).addGauge(testTokenAddress);

  // Mint axial
  await axial.connect(deployer).mint(alice.address, await axial.maxSupply());
}
