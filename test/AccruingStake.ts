import { solidity } from "ethereum-waffle"

// eslint-disable-next-line node/no-missing-import
import { AccruingStake, ERC20TokenMock } from "../typechain"
import chai from "chai"
import { ethers } from "hardhat"
import { Signer } from "ethers"

chai.use(solidity)
const { expect } = chai

async function increaseTimestamp(amount: number) {
  await ethers.provider.send('evm_increaseTime', [amount]);
  await ethers.provider.send('evm_mine', []);
}

describe("AccruingStake", () => {
  let deployer: Signer
  let governance: Signer
  let alice: Signer
  let bob: Signer
  let carol: Signer

  let axialToken: ERC20TokenMock
  let stakingAc: AccruingStake

  let aliceAddr: string
  let bobAddr: string
  let carolAddr: string
  let governanceAddr: string

  // 60s/min, 60m/hr, 24hr/day, 7day/wk, 52wk/yr
  const SECONDS_IN_A_YEAR = 60 * 60 * 24 * 7 * 52
  const SECONDS_IN_A_WEEK = 60 * 60 * 24 * 7
  const SECONDS_IN_A_DAY = 60 * 60 * 24

  beforeEach(async () => {
    [deployer, governance, alice, bob, carol] = await ethers.getSigners()

    aliceAddr = await alice.getAddress()
    bobAddr = await bob.getAddress()
    carolAddr = await carol.getAddress()
    governanceAddr = await governance.getAddress()

    const stakingAcFactory = await ethers.getContractFactory("AccruingStake");
    axialToken = await (await ethers.getContractFactory("ERC20TokenMock")).deploy("Axial", "AXIAL");

    await axialToken.connect(deployer).mints([ await deployer.getAddress(), aliceAddr, bobAddr, carolAddr, ], [1000, 10, 100, 500])
    stakingAc = await stakingAcFactory.deploy(axialToken.address, "veAxial", "VEAXIAL", await governance.getAddress())
  })

  // Test cases:

  it("User cannot create lock with more tokens then they have", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, 1000)
    await expect(stakingAc.connect(alice).stake(1000)).to.be.revertedWith("!balance")
  })

  it("Locking 10 tokens results in 0 reward tokens immediately and locked balance of 10", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, "10")
    await stakingAc.connect(alice).stake(10)

    expect(await stakingAc.connect(alice).getStaked(aliceAddr)).to.eq(10)
    expect(await stakingAc.connect(alice).getAccrued(aliceAddr)).to.eq(0)
  })

  it("10 tokens locked for a year accrues ten reward tokens per second", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await stakingAc.connect(alice).stake(10)
    await increaseTimestamp(SECONDS_IN_A_YEAR)

    await stakingAc.connect(alice).updateAllUsersAccrual(0)
    let accrued = await stakingAc.connect(alice).getAccrued(aliceAddr)
    console.log("Accrued %d points", accrued)
    expect(accrued).to.eq(10 * (SECONDS_IN_A_YEAR + 1))
  })

  it("Claiming repeatedly does not affect a different users funds, or allow user to claim more than they are owed", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, "10")
    await axialToken.connect(bob).approve(stakingAc.address, "100")

    await stakingAc.connect(alice).stake(10)
    await stakingAc.connect(bob).stake(100)

    await increaseTimestamp(SECONDS_IN_A_YEAR)
    await stakingAc.connect(alice).updateAllUsersAccrual(0)

    await stakingAc.connect(alice).claimMyFunds()
    const inWallet = await axialToken.balanceOf(aliceAddr)
    await expect(stakingAc.connect(alice).claimMyFunds()).to.be.revertedWith("!funds");
    const inWalletAfterClaimingTwice = await axialToken.balanceOf(aliceAddr)
    await stakingAc.connect(bob).claimMyFunds()
    const inBobsWallet = await axialToken.balanceOf(bobAddr)

    expect(inWallet).to.eq(inWalletAfterClaimingTwice)
    expect(inBobsWallet).to.eq(100)
  })

  /*

  it("User can increase the duration of a pre-existing lock, up to the max duration of two years", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, '10');
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, '10', false);
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 0, false);
    await expect(stakingVe.connect(alice).stake(100, 0, false)).to.be.revertedWith('>2 years');
  })

  it("Balance, Power linearly decay over time and can be claimed repeatedly with lock time increasing", async () => {

    // Give alice a holiday bonus
    await axialToken.connect(deployer).mints([aliceAddr], [90]);

    await axialToken.connect(alice).approve(stakingVe.address, '100');
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, '100', false);

    let balance = await stakingVe.connect(alice).getBalance(aliceAddr);
    let power = await stakingVe.connect(alice).getPower(aliceAddr);
    let inWallet = await axialToken.balanceOf(aliceAddr);
    console.log("Day %d, Balance: %d Power: %d, Wallet: %d", 0, balance, power, inWallet);

    for (let i = 1; i < 104; ++i) {
      await (increaseTimestamp(SECONDS_IN_A_WEEK));
      balance = await stakingVe.connect(alice).getBalance(aliceAddr);
      power = await stakingVe.connect(alice).getPower(aliceAddr);
      await stakingVe.connect(alice).claimMyFunds();
      inWallet = await axialToken.balanceOf(aliceAddr);
      console.log("Week: %d, Balance: %d Power: %d, Wallet: %d", i, balance, power, inWallet);
      expect(balance.add(inWallet)).to.eq(100);

      // In 26 weeks, extend our lock by another year
      if (i == 26) {
        console.log("Extending lock by one year");
        await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 0, false);
      }
    }
  })

  it("Balance, Power linearly decay over time and can be deferred", async () => {

    // Give alice a holiday bonus
    await axialToken.connect(deployer).mints([aliceAddr], [90]);

    await axialToken.connect(alice).approve(stakingVe.address, '100');
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, '100', false);

    let balance = await stakingVe.connect(alice).getBalance(aliceAddr);
    let power = await stakingVe.connect(alice).getPower(aliceAddr);
    let inWallet = await axialToken.balanceOf(aliceAddr);
    let deferred = await stakingVe.connect(alice).getUnclaimed(aliceAddr);
    console.log("Day %d, Balance: %d Power: %d, Wallet: %d, Deferred: %d", 0, balance, power, inWallet, deferred);

    for (let i = 1; i < 104; ++i) {
      await (increaseTimestamp(SECONDS_IN_A_WEEK));
      balance = await stakingVe.connect(alice).getBalance(aliceAddr);
      power = await stakingVe.connect(alice).getPower(aliceAddr);
      inWallet = await axialToken.balanceOf(aliceAddr);
      let deferred = await stakingVe.connect(alice).getUnclaimed(aliceAddr);
      console.log("Day %d, Balance: %d Power: %d, Wallet: %d, Deferred: %d", i, balance, power, inWallet, deferred);
      expect(balance.add(inWallet).add(deferred)).to.eq(100);

      // In 26 weeks, extend our lock by another year
      if (i == 26) {
        console.log("Extending lock by one year");
        await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 0, true);
      }
    }

    await stakingVe.connect(alice).claimMyFunds();
  })

  it("User can autocompound their lock", async () => {
    // Alice's holiday bonus
    await axialToken.connect(deployer).mints([aliceAddr], [990])
    await axialToken.connect(alice).approve(stakingVe.address, 1000)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR * 2, 1000, false)

    let interest = 0;

    for (let i = 0; i < 100; ++i) {
      await increaseTimestamp(SECONDS_IN_A_DAY)

      await axialToken.connect(deployer).mints([aliceAddr], [interest])

      let dividends = await axialToken.balanceOf(aliceAddr)
      await axialToken.connect(alice).approve(stakingVe.address, dividends)
      await stakingVe.connect(alice).stake(SECONDS_IN_A_DAY, dividends, false);

      const balance = await stakingVe.connect(alice).getBalance(aliceAddr)
      const power = await stakingVe.connect(alice).getPower(aliceAddr)
      const inWallet = await axialToken.balanceOf(aliceAddr)
      interest = power.div(100).toNumber(); // Let's say we make 1% of our power in gains every day 
      console.log("Day %d, Balance: %d Power: %d, Wallet: %d, Interest: %d", i, balance, power, inWallet, interest)
    }
  })

  it("User cannot decrease their lock time by means of overflow", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, 10)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 10, false)
    await increaseTimestamp(SECONDS_IN_A_YEAR/2)

    for (let i = 0; i < 256; ++i) {
      let extension = 2 ** i;

      let lockBeforeExtension = await(stakingVe.connect(alice).getLock(aliceAddr))
      let duration = lockBeforeExtension.EndBlockTime.toNumber() - lockBeforeExtension.StartBlockTime.toNumber();
      if (duration + extension > SECONDS_IN_A_YEAR * 2) {
        await expect(stakingVe.connect(alice).stake(extension, 0, false)).to.be.reverted
      } else {
        await stakingVe.connect(alice).stake(extension, 0, false)
        let lockAfterExtension = await(stakingVe.connect(alice).getLock(aliceAddr))
        expect(lockAfterExtension.EndBlockTime.toNumber()).to.be.greaterThanOrEqual(lockBeforeExtension.EndBlockTime.toNumber())
        let years = (lockAfterExtension.EndBlockTime.toNumber() - lockAfterExtension.StartBlockTime.toNumber()) / (SECONDS_IN_A_YEAR * 2)
        //console.log("Lock may be for %d years", years)
      }
    }
  })

  it("User can withdraw any unclaimed balance after their lock has expired", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, 10)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 10, false)
    await increaseTimestamp(SECONDS_IN_A_YEAR/2)
    await stakingVe.connect(alice).claimMyFunds()
    await increaseTimestamp(SECONDS_IN_A_YEAR)
    await stakingVe.connect(alice).claimMyFunds();
    const inWallet = await axialToken.balanceOf(aliceAddr)
    expect(inWallet).to.eq(10)
  })

  it("User can create a lock after their old lock has expired", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, 10)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 10, false)
    await increaseTimestamp(SECONDS_IN_A_YEAR/2)
    await stakingVe.connect(alice).claimMyFunds()
    await increaseTimestamp(SECONDS_IN_A_YEAR)
    await stakingVe.connect(alice).claimMyFunds();
    let inWallet = await axialToken.balanceOf(aliceAddr)
    expect(inWallet).to.eq(10)
    await axialToken.connect(alice).approve(stakingVe.address, 10)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 10, false)

    let balance = await stakingVe.connect(alice).getBalance(aliceAddr);
    let power = await stakingVe.connect(alice).getPower(aliceAddr);
    inWallet = await axialToken.balanceOf(aliceAddr);
    console.log("Balance: %d Power: %d, Wallet: %d", balance, power, inWallet);
    expect(await stakingVe.connect(alice).getPower(aliceAddr)).to.eq(5);
  })

  it("Governance cannot withdraw Staked tokens", async () => {
    await axialToken.connect(alice).approve(stakingVe.address, 10)
    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, 10, false)

    await expect(stakingVe.connect(governance).ownerRemoveNonDepositToken(axialToken.address)).to.be.revertedWith("!invalid");

    let axialTokenOwnedByStaking = await axialToken.balanceOf(stakingVe.address);
    let axialTokenOwnedByGovernance = await axialToken.balanceOf(governanceAddr);
    expect(axialTokenOwnedByStaking).to.eq(10);
    expect(axialTokenOwnedByGovernance).to.eq(0);
  })

  it("Governance can withdraw tokens other than the staked one", async () => {
    let stakingVeAddr = stakingAc.address;
    let coaxialToken : ERC20TokenMock = await (await ethers.getContractFactory("ERC20TokenMock")).deploy("Coaxial", "COAX");
    await coaxialToken.connect(deployer).mints([aliceAddr], [1000])
    await coaxialToken.connect(alice).approve(aliceAddr, 1000);
    await coaxialToken.connect(alice).transferFrom(aliceAddr, stakingVeAddr, 1000);
    let coaxialOwnedByStaking = await coaxialToken.balanceOf(stakingVeAddr);
    expect(coaxialOwnedByStaking).to.eq(1000);
    await stakingAc.connect(governance).ownerRemoveNonDepositToken(coaxialToken.address);
    coaxialOwnedByStaking = await coaxialToken.balanceOf(stakingVeAddr);
    let coaxialOwnedByGovernance = await coaxialToken.balanceOf(governanceAddr);
    expect(coaxialOwnedByStaking).to.eq(0);
    expect(coaxialOwnedByGovernance).to.eq(1000);
  })

  it("getAllUsers returns an array of all users that have ever staked", async() => {
    await axialToken.connect(alice).approve(stakingVe.address, "10")
    await axialToken.connect(bob).approve(stakingVe.address, "100")
    await axialToken.connect(carol).approve(stakingVe.address, "500")

    await stakingVe.connect(alice).stake(SECONDS_IN_A_YEAR, "10", false)
    await stakingVe.connect(bob).stake(SECONDS_IN_A_YEAR, "100", false)
    await stakingVe.connect(carol).stake(SECONDS_IN_A_YEAR * 2, "500", false)

    await increaseTimestamp(SECONDS_IN_A_YEAR + 1)

    let users = await stakingVe.connect(alice).getAllUsers()

    //console.log("Users: ", users)

    expect(users.length).to.eq(3)
  })
*/

})
