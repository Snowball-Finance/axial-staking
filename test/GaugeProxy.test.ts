/* eslint-disable node/no-missing-import */
/* eslint-disable camelcase */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumberish } from "ethers";
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

describe("Gauge Proxy:", function () {
  beforeEach(async function () {
    await setupTest();
  });

  describe("Voting logic: ", function () {
    it("Should allow user to vote if they have sAxial", async function () {
      await stakeAndVote(alice, 100);

      const tokenWeightAfterVote = await gaugeProxy.weights(testTokenAddress);
      expect(tokenWeightAfterVote).to.gt(0);

      const userTokenVotesAfter = await gaugeProxy.votes(
        alice.address,
        testTokenAddress
      );
      expect(userTokenVotesAfter).to.gt(0);
    });

    it("Should not allow user to vote without sAxial", async function () {
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

    it("Should reset vote of user", async function () {
      await stakeAndVote(alice, 100);

      // Check token has weights set
      const tokenWeightBefore = await gaugeProxy.weights(testTokenAddress);
      expect(tokenWeightBefore).to.gt(0);

      // Check user has votes for token
      const userTokenVotesBefore = await gaugeProxy.votes(
        alice.address,
        testTokenAddress
      );
      expect(userTokenVotesBefore).to.gt(0);

      // Reset votes
      await gaugeProxy.connect(alice).reset();

      // Check token has no weights
      const tokenWeightAfter = await gaugeProxy.weights(testTokenAddress);
      expect(tokenWeightAfter).to.eq(0);

      // Check user has no votes for token
      const userTokenVotesAfter = await gaugeProxy.votes(
        alice.address,
        testTokenAddress
      );
      expect(userTokenVotesAfter).to.eq(0);
    });
  });
});

// Helper functions

async function setupTest(): Promise<void> {
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

async function stakeAndVote(
  user: SignerWithAddress,
  weight: BigNumberish
): Promise<void> {
  const userBalanceBeforeStake = await axial.balanceOf(user.address);
  expect(userBalanceBeforeStake).to.eq(await axial.maxSupply());

  // Approve max spend of users axial
  await axial.connect(user).approve(sAxial.address, await axial.maxSupply());

  // Stake axial
  const powerBeforeStake = await sAxial.getPower(user.address);
  expect(powerBeforeStake).to.eq(0);

  await sAxial.connect(user).stake(SECONDS_IN_A_YEAR, 100, false);

  const userBalanceAfterStake = await axial.balanceOf(user.address);
  expect(userBalanceAfterStake).to.eq(userBalanceBeforeStake.sub(100));

  // Check user has some voting user
  const powerAfterStake = await sAxial.getPower(user.address);
  expect(powerAfterStake).to.gt(0);

  const tokenWeightBeforeVote = await gaugeProxy.weights(testTokenAddress);
  expect(tokenWeightBeforeVote).to.eq(0);

  const userTokenVotesBefore = await gaugeProxy.votes(
    user.address,
    testTokenAddress
  );
  expect(userTokenVotesBefore).to.eq(0);

  // Vote on gauge proxy for test token
  await gaugeProxy.connect(user).vote([testTokenAddress], [weight]);
}
