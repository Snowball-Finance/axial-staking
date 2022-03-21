/* eslint-disable camelcase */
/* eslint-disable node/no-missing-import */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  ERC20TokenMock,
  ERC20TokenMock__factory,
  Gauge,
  Gauge__factory,
} from "../typechain";
import { fastForwardAWeek } from "./utils";

let deployer: SignerWithAddress;
let user: SignerWithAddress;

let veAxial: ERC20TokenMock;
let testPoolToken: ERC20TokenMock;
let testRewardToken: ERC20TokenMock;
let testGauge: Gauge;

// Things to test
// Check derived balance of gauge for user is boosted by balance of veAxial

// Mint all pool token to user
// Approve gauge to spend users pool token
// Deposit pool token in gauge
// Check derived balance for user - should not be boosted as doesn't hold veAxial
// Transfer veAxial to user
// Check derived balance for user - should be bosted as user holds veAxial

describe.only("Gauge:", function () {
  beforeEach(async function () {
    await setupTest();
  });

  it("Should add a reward token to the Gauge", async function () {
    const rewardTokensBefore = await testGauge.getNumRewardTokens();
    expect(rewardTokensBefore).to.eq(0);

    await testGauge.connect(deployer).addRewardToken(testRewardToken.address);

    const rewardTokensAfter = await testGauge.getNumRewardTokens();
    expect(rewardTokensAfter).to.eq(1);
  });

  it("Should increment total supply when user deposits", async function () {
    const totalSupplyBefore = await testGauge.totalSupply();
    expect(totalSupplyBefore).to.eq(0);

    // Get tokens
    await testPoolToken.connect(deployer).mint(user.address, 100);

    const userBalanceBefore = await testPoolToken.balanceOf(user.address);
    expect(userBalanceBefore).to.eq(100);

    // Approve gauge to spend tokens
    await testPoolToken.connect(user).approve(testGauge.address, 100);

    // Deposit tokens
    await testGauge.connect(user).deposit(100);

    const totalSupplyAfter = await testGauge.totalSupply();
    expect(totalSupplyAfter).to.eq(100);
  });

  it("Should decrement total supply when user withdraws", async function () {
    // Get tokens
    await testPoolToken.connect(deployer).mint(user.address, 100);

    const userBalanceBefore = await testPoolToken.balanceOf(user.address);
    expect(userBalanceBefore).to.eq(100);

    // Approve gauge to spend tokens
    await testPoolToken.connect(user).approve(testGauge.address, 100);

    // Deposit tokens
    await testGauge.connect(user).deposit(100);

    const totalSupplyBefore = await testGauge.totalSupply();
    expect(totalSupplyBefore).to.eq(100);

    // Withdraw tokens
    await testGauge.connect(user).withdraw(100);

    const totalSupplyAfter = await testGauge.totalSupply();
    expect(totalSupplyAfter).to.eq(0);
  });

  it.skip("Should boost users balance when holding veAxial", async function () {
    await testPoolToken.connect(deployer).mint(user.address, 100);

    // Add reward token
    await testGauge.connect(deployer).addRewardToken(testRewardToken.address);

    const userBalanceBefore = await testPoolToken.balanceOf(user.address);
    expect(userBalanceBefore).to.eq(100);

    await testPoolToken.connect(user).approve(testGauge.address, 100);

    await testGauge.connect(user).deposit(100);

    const userBalanceAfter = await testPoolToken.balanceOf(user.address);
    expect(userBalanceAfter).to.eq(0);

    await fastForwardAWeek();

    // Get gauge.earned without any veAxial
    const userEarnedBeforeBoost = await testGauge.earned(user.address, 0);
    console.log("userEarnedBeforeBoost", userEarnedBeforeBoost);

    // Transfer veAxial to user
    await veAxial.connect(deployer).transfer(user.address, 100);

    await fastForwardAWeek();

    await testGauge.connect(user).getReward(0);

    // Get gauge.earned with veAxial
    const userEarnedAfterBoost = await testGauge.earned(user.address, 0);
    console.log("userEarnedAfterBoost", userEarnedAfterBoost);
  });
});

// Helper functions
async function setupTest(): Promise<void> {
  [deployer, user] = await ethers.getSigners();

  // Deploy test pool token
  testPoolToken = await new ERC20TokenMock__factory(deployer).deploy(
    "Test Token",
    "TST"
  );

  // Deplpy veAxial
  veAxial = await new ERC20TokenMock__factory(deployer).deploy(
    "veAxial",
    "veAxial"
  );

  // Deploy test reward token
  testRewardToken = await new ERC20TokenMock__factory(deployer).deploy(
    "Reward",
    "REW"
  );

  // Deploy gauge
  testGauge = await new Gauge__factory(deployer).deploy(
    testPoolToken.address,
    deployer.address,
    veAxial.address
  );

  // Mint reward token to deployer
  await testRewardToken
    .connect(deployer)
    .mint(deployer.address, await testRewardToken.maxSupply());

  // Mint veAxial to deployer
  await veAxial
    .connect(deployer)
    .mint(deployer.address, await veAxial.maxSupply());
}
