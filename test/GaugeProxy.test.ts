/* eslint-disable node/no-missing-import */
/* eslint-disable camelcase */
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumberish, Signer, Contract } from "ethers";
import { ethers, hardhatArguments, network } from "hardhat";
import {increaseTime} from "./utils";
import {
  ERC20TokenMock,
  ERC20TokenMock__factory,
  GaugeProxy,
  GaugeProxy__factory,
  Gauge,
  StakedAxialToken,
  StakedAxialToken__factory,
  AccruingStake,
  AccruingStake__factory,
  IMasterChef,
} from "../typechain";
import { SECONDS_IN_A_DAY, SECONDS_IN_A_YEAR } from "./constants";

let masterChef: Contract;
let gaugeProxy: GaugeProxy;
let axial: ERC20TokenMock;
let sAxial: StakedAxialToken;
let veAxial: AccruingStake;
let testToken: ERC20TokenMock;
const masterChefaddr = "0x3fae9b2637dbeb6cc570784ba886145fa5f2c0f6";
let poolID = 0;

let deployer: SignerWithAddress;
let alice: SignerWithAddress;
let bob: SignerWithAddress;
let carol: SignerWithAddress;
let dave: SignerWithAddress;

const ALLOCATED_FOR_USERS = 5000000;
const SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7;

let testTokenAddress: string;

let masterChefABI = [{"inputs":[{"internalType":"contract AxialToken","name":"_axial","type":"address"},{"internalType":"address","name":"_devAddr","type":"address"},{"internalType":"address","name":"_treasuryAddr","type":"address"},{"internalType":"address","name":"_investorAddr","type":"address"},{"internalType":"uint256","name":"_axialPerSec","type":"uint256"},{"internalType":"uint256","name":"_startTimestamp","type":"uint256"},{"internalType":"uint256","name":"_devPercent","type":"uint256"},{"internalType":"uint256","name":"_treasuryPercent","type":"uint256"},{"internalType":"uint256","name":"_investorPercent","type":"uint256"}],"stateMutability":"nonpayable","type":"constructor"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"allocPoint","type":"uint256"},{"indexed":true,"internalType":"contract IERC20","name":"lpToken","type":"address"},{"indexed":true,"internalType":"contract IRewarder","name":"rewarder","type":"address"}],"name":"Add","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Deposit","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"EmergencyWithdraw","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Harvest","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"previousOwner","type":"address"},{"indexed":true,"internalType":"address","name":"newOwner","type":"address"}],"name":"OwnershipTransferred","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"allocPoint","type":"uint256"},{"indexed":true,"internalType":"contract IRewarder","name":"rewarder","type":"address"},{"indexed":false,"internalType":"bool","name":"overwrite","type":"bool"}],"name":"Set","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"oldAddress","type":"address"},{"indexed":true,"internalType":"address","name":"newAddress","type":"address"}],"name":"SetDevAddress","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":false,"internalType":"uint256","name":"_axialPerSec","type":"uint256"}],"name":"UpdateEmissionRate","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"lastRewardTimestamp","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"lpSupply","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"accAxialPerShare","type":"uint256"}],"name":"UpdatePool","type":"event"},{"anonymous":false,"inputs":[{"indexed":true,"internalType":"address","name":"user","type":"address"},{"indexed":true,"internalType":"uint256","name":"pid","type":"uint256"},{"indexed":false,"internalType":"uint256","name":"amount","type":"uint256"}],"name":"Withdraw","type":"event"},{"inputs":[{"internalType":"uint256","name":"_allocPoint","type":"uint256"},{"internalType":"contract IERC20","name":"_lpToken","type":"address"},{"internalType":"contract IRewarder","name":"_rewarder","type":"address"}],"name":"add","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"axial","outputs":[{"internalType":"contract AxialToken","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"axialPerSec","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"deposit","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_devAddr","type":"address"}],"name":"dev","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"devAddr","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"devPercent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"}],"name":"emergencyWithdraw","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"investorAddr","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"investorPercent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"massUpdatePools","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"owner","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"},{"internalType":"address","name":"_user","type":"address"}],"name":"pendingTokens","outputs":[{"internalType":"uint256","name":"pendingAxial","type":"uint256"},{"internalType":"address","name":"bonusTokenAddress","type":"address"},{"internalType":"string","name":"bonusTokenSymbol","type":"string"},{"internalType":"uint256","name":"pendingBonusToken","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"}],"name":"poolInfo","outputs":[{"internalType":"contract IERC20","name":"lpToken","type":"address"},{"internalType":"uint256","name":"allocPoint","type":"uint256"},{"internalType":"uint256","name":"lastRewardTimestamp","type":"uint256"},{"internalType":"uint256","name":"accAxialPerShare","type":"uint256"},{"internalType":"contract IRewarder","name":"rewarder","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"poolLength","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"renounceOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"}],"name":"rewarderBonusTokenInfo","outputs":[{"internalType":"address","name":"bonusTokenAddress","type":"address"},{"internalType":"string","name":"bonusTokenSymbol","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"},{"internalType":"uint256","name":"_allocPoint","type":"uint256"},{"internalType":"contract IRewarder","name":"_rewarder","type":"address"},{"internalType":"bool","name":"overwrite","type":"bool"}],"name":"set","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_newDevPercent","type":"uint256"}],"name":"setDevPercent","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_investorAddr","type":"address"}],"name":"setInvestorAddr","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_newInvestorPercent","type":"uint256"}],"name":"setInvestorPercent","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"address","name":"_treasuryAddr","type":"address"}],"name":"setTreasuryAddr","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_newTreasuryPercent","type":"uint256"}],"name":"setTreasuryPercent","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"startTimestamp","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"totalAllocPoint","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"address","name":"newOwner","type":"address"}],"name":"transferOwnership","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[],"name":"treasuryAddr","outputs":[{"internalType":"address","name":"","type":"address"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"treasuryPercent","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_axialPerSec","type":"uint256"}],"name":"updateEmissionRate","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"}],"name":"updatePool","outputs":[],"stateMutability":"nonpayable","type":"function"},{"inputs":[{"internalType":"uint256","name":"","type":"uint256"},{"internalType":"address","name":"","type":"address"}],"name":"userInfo","outputs":[{"internalType":"uint256","name":"amount","type":"uint256"},{"internalType":"uint256","name":"rewardDebt","type":"uint256"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint256","name":"_pid","type":"uint256"},{"internalType":"uint256","name":"_amount","type":"uint256"}],"name":"withdraw","outputs":[],"stateMutability":"nonpayable","type":"function"}];

async function impersonate(
  account: string
): Promise<Signer> {
  await network.provider.send('hardhat_impersonateAccount', [account]);
  return ethers.provider.getSigner(account);
}

async function setBalance(
  account: string,
  balance: string
): Promise<void> {
  await network.provider.send('hardhat_setBalance', [account, balance]);
}

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

    it.only("Rewards should be distributed to users based on their weights", async function() {
      let aliceBalance = axial.balanceOf(alice.address);

      await stakeAndVote(alice, 100);
      await stakeAndVote(bob, 100);
      await gaugeProxy.connect(deployer).preDistribute();
      let numGauges = await gaugeProxy.connect(deployer).length();
      await gaugeProxy.connect(deployer).distribute(0, numGauges);

      let tokens = await gaugeProxy.connect(alice).tokens();

      let rewardToken1 = await new ERC20TokenMock__factory(dave).deploy("rewardToken1", "REWARD1");
      let rewardToken2 = await new ERC20TokenMock__factory(dave).deploy("rewardToken2", "REWARD2");
      let rewardToken3 = await new ERC20TokenMock__factory(dave).deploy("rewardToken3", "REWARD3");
      let rewardToken4 = await new ERC20TokenMock__factory(dave).deploy("rewardToken4", "REWARD4");
      await rewardToken1.connect(dave).mint(dave.address, ALLOCATED_FOR_USERS);
      await rewardToken2.connect(dave).mint(dave.address, ALLOCATED_FOR_USERS);
      await rewardToken3.connect(dave).mint(dave.address, ALLOCATED_FOR_USERS);
      await rewardToken4.connect(dave).mint(dave.address, ALLOCATED_FOR_USERS);

      for (let i = 0; i < numGauges.toNumber(); ++i) {
        let indexArray = [];
        let gaugeAddr = await gaugeProxy.getGauge(tokens[i]);
        let gauge = await ethers.getContractAt("Gauge", gaugeAddr, dave);
        console.log("gaugeAddr=", gaugeAddr);

        // Alice is gonna deposit some LP tokens into the gauge
        await testToken.connect(alice).approve(gaugeAddr, ALLOCATED_FOR_USERS);
        await gauge.connect(alice).depositAll();

        await gauge.connect(deployer).addRewardToken(rewardToken1.address, dave.address);
        await gauge.connect(deployer).addRewardToken(rewardToken2.address, dave.address);
        await gauge.connect(deployer).addRewardToken(rewardToken3.address, dave.address);
        await gauge.connect(deployer).addRewardToken(rewardToken4.address, dave.address);

        await rewardToken1.connect(dave).approve(gaugeAddr, ALLOCATED_FOR_USERS);
        await rewardToken2.connect(dave).approve(gaugeAddr, ALLOCATED_FOR_USERS);
        await rewardToken3.connect(dave).approve(gaugeAddr, ALLOCATED_FOR_USERS);
        await rewardToken4.connect(dave).approve(gaugeAddr, ALLOCATED_FOR_USERS);

        await gauge.connect(dave).partnerDepositRewardTokens(rewardToken1.address, SECONDS_IN_A_WEEK, 1);
        await gauge.connect(dave).partnerDepositRewardTokens(rewardToken2.address, SECONDS_IN_A_WEEK, 1);
        await gauge.connect(dave).partnerDepositRewardTokens(rewardToken3.address, SECONDS_IN_A_WEEK, 1);
        await gauge.connect(dave).partnerDepositRewardTokens(rewardToken4.address, SECONDS_IN_A_WEEK, 1);

        let rewardTokens = await gauge.connect(alice).getNumRewardTokens();
        console.log("rewardTokens=", rewardTokens.toNumber());

      await testToken.connect(alice).approve(gaugeAddr, ALLOCATED_FOR_USERS);
      //await gauge.connect(alice).depositAll();

      for (let i = 0; i < 6; ++i) {
        await increaseTime(SECONDS_IN_A_DAY);
        await gauge.connect(alice).getAllRewards();

        let balances = [await rewardToken1.balanceOf(alice.address),
          await rewardToken2.balanceOf(alice.address),
          await rewardToken3.balanceOf(alice.address),
          await rewardToken4.balanceOf(alice.address)];
          console.log(balances);
      }

      await increaseTime(SECONDS_IN_A_YEAR);

      await gaugeProxy.connect(deployer).preDistribute();
      await gaugeProxy.connect(deployer).distribute(0, numGauges);

      for (let i = 0; i < rewardTokens.toNumber(); ++i) {
        indexArray.push(i);
      }

      await gauge.connect(alice).getAllRewards();

      let balances = [await rewardToken1.balanceOf(alice.address),
                      await rewardToken2.balanceOf(alice.address),
                      await rewardToken3.balanceOf(alice.address),
                      await rewardToken4.balanceOf(alice.address)];
      console.log(rewardToken1.address);
      console.log(rewardToken2.address);
      console.log(rewardToken3.address);
      console.log(rewardToken4.address);
      console.log(balances);

      await increaseTime(SECONDS_IN_A_YEAR);
      //await gaugeProxy.connect(deployer).preDistribute();
      //await gaugeProxy.connect(deployer).distribute(0, numGauges);
      await gauge.connect(alice).getAllRewards();
      balances = [await rewardToken1.balanceOf(alice.address),
        await rewardToken2.balanceOf(alice.address),
        await rewardToken3.balanceOf(alice.address),
        await rewardToken4.balanceOf(alice.address)];

      console.log(balances);

    }

    });
  });
});

// Helper functions

async function setupTest(): Promise<void> {
  [deployer, alice, bob, carol, dave] = await ethers.getSigners();

  // Deploy Axial
  axial = await new ERC20TokenMock__factory(deployer).deploy("Axial", "AXIAL");

  // Deploy sAxial
  sAxial = await new StakedAxialToken__factory(deployer).deploy(axial.address);

  // Deploy veAxial
  veAxial = await new AccruingStake__factory(deployer).deploy(
    axial.address,
    "veAxial",
    "veAxial",
    deployer.address
  );

  // Deploy gauge proxy
  gaugeProxy = await new GaugeProxy__factory(deployer).deploy(
    deployer.address,
    axial.address,
    sAxial.address,
    veAxial.address
  );

  //await gaugeProxy.connect(deployer).setMasterChef(masterChef.address);
  await gaugeProxy.connect(deployer).setMasterChef("0x3fae9b2637dbeb6cc570784ba886145fa5f2c0f6");
  
  // Get random fake LP token
  //testTokenAddress = ethers.Wallet.createRandom().address;
  testToken = await new ERC20TokenMock__factory(deployer).deploy("testLPToken", "TESTLP");
  testTokenAddress = testToken.address;

  // Add gauge for fake token
  let deployerBalance = await testToken.balanceOf(deployer.address);
  await gaugeProxy.connect(deployer).addGauge(testTokenAddress);

  console.log("impersonating mcv2 owner");

  // impersonate owner of MCV2
  let MCV2Owner = await impersonate("0x4980ad7ccb304f7d3c5053aa1131ed1edaf48809");

  console.log("connecting to masterchef");

  // Create a new pool on MCV2
  //masterChef = new ethers.Contract(masterChefaddr, masterChefABI, deployer);
  masterChef = new ethers.Contract(masterChefaddr, masterChefABI, MCV2Owner);
  let dummyToken = await gaugeProxy.connect(deployer).axialDummyToken();
  let poolLength = await masterChef.poolLength();

  await setBalance(await MCV2Owner.getAddress(), "0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF");

  console.log("adding new pool");
  // Add a new pool and give it an allocation point
  //await masterChef.add(1, dummyToken, "0x0000000000000000000000000000000000000000");
  await masterChef.connect(MCV2Owner).add(1, dummyToken, "0x0000000000000000000000000000000000000000");
  
  // Set all pools besides the old one to have no allocation points
  for (let i = 0; i < poolLength; ++i) {
    //await masterChef.set(i, 0, "0x0000000000000000000000000000000000000000", true);
    console.log("setting old pools to 0");
    await masterChef.connect(MCV2Owner).set(i, 0, "0x0000000000000000000000000000000000000000", true);
  }

  poolID = poolLength;

  await gaugeProxy.connect(deployer).setPID(poolLength);

  // Mint axial
  await axial.connect(deployer).mint(alice.address, ALLOCATED_FOR_USERS);
  await axial.connect(deployer).mint(bob.address, ALLOCATED_FOR_USERS);
  await axial.connect(deployer).mint(carol.address, ALLOCATED_FOR_USERS);
  await axial.connect(deployer).mint(dave.address, ALLOCATED_FOR_USERS);

  // Give out some pool tokens
  await testToken.connect(deployer).mint(alice.address, ALLOCATED_FOR_USERS);
  await testToken.connect(deployer).mint(bob.address, ALLOCATED_FOR_USERS);
  await testToken.connect(deployer).mint(carol.address, ALLOCATED_FOR_USERS);
  await testToken.connect(deployer).mint(dave.address, ALLOCATED_FOR_USERS);
}

async function stakeAndVote(
  user: SignerWithAddress,
  weight: BigNumberish
): Promise<void> {

  const userBalanceBeforeStake = await axial.balanceOf(user.address);
  expect(userBalanceBeforeStake).to.eq(await ALLOCATED_FOR_USERS);

  // Approve max spend of users axial
  await axial.connect(user).approve(sAxial.address, await axial.maxSupply());

  // Stake axial
  const powerBeforeStake = await sAxial.getPower(user.address);
  expect(powerBeforeStake).to.eq(0);

  await sAxial.connect(user).stake(SECONDS_IN_A_YEAR, userBalanceBeforeStake, false);

  const userBalanceAfterStake = await axial.balanceOf(user.address);
  expect(userBalanceAfterStake).to.eq(userBalanceBeforeStake.sub(userBalanceBeforeStake));

  // Check user has some voting user
  const powerAfterStake = await sAxial.getPower(user.address);
  expect(powerAfterStake).to.gt(0);

  const tokenWeightBeforeVote = await gaugeProxy.weights(testTokenAddress);
  // expect(tokenWeightBeforeVote).to.eq(0);

  const userTokenVotesBefore = await gaugeProxy.votes(
    user.address,
    testTokenAddress
  );
  expect(userTokenVotesBefore).to.eq(0);

  // Vote on gauge proxy for test token
  await gaugeProxy.connect(user).vote([testTokenAddress], [weight]);

  const userTokenVotesAfter = await gaugeProxy.votes(user.address, testTokenAddress);
  expect(userTokenVotesAfter.toNumber()).to.be.greaterThan(0);
}
