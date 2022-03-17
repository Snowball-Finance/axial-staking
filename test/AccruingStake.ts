import { solidity } from "ethereum-waffle"

// eslint-disable-next-line node/no-missing-import
import { AccruingStake, ERC20TokenMock } from "../typechain"
import chai from "chai"
import { ethers } from "hardhat"
import { BigNumber, Signer } from "ethers"

chai.use(solidity)
const { expect } = chai

async function increaseTimestamp(amount: number) {
  await ethers.provider.send('evm_increaseTime', [amount]);
  await ethers.provider.send('evm_mine', []);
}

async function getCostOfAVAXPerGas() {
    let etherscanProvider = await new ethers.providers.JsonRpcProvider("https://api.avax.network/ext/bc/C/rpc")
    return (await etherscanProvider.getGasPrice()).toNumber() * 1/1e18
}

async function gasCostToBlockLimit(gasCost: number) {
    const gasLimit : number = 8000000 // AVAX Gas Limit is set to 8m Gas Cost
    return gasLimit / gasCost
}

async function gasCostToAvax(gasCost:number) {
    let etherscanProvider = await new ethers.providers.JsonRpcProvider("https://api.avax.network/ext/bc/C/rpc")
    let nAVAXPerGas1e18 = (await etherscanProvider.getGasPrice()).toNumber()
    return gasCost * nAVAXPerGas1e18 * 1/1e18;
}

async function gasCostToUSD(gasCost:number, USDPerAVAX:number) {
    let avaxCost = await gasCostToAvax(gasCost)
    return avaxCost * USDPerAVAX
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

    let accrued = await stakingAc.connect(alice).getAccrued(aliceAddr)
    console.log("Accrued %d points", accrued)
    expect(accrued).to.eq(10 * (SECONDS_IN_A_YEAR))
  })

  it("Claiming repeatedly does not affect a different users funds, or allow user to claim more than they are owed", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, "10")
    await axialToken.connect(bob).approve(stakingAc.address, "100")

    await stakingAc.connect(alice).stake(10)
    await stakingAc.connect(bob).stake(100)

    await increaseTimestamp(SECONDS_IN_A_YEAR)

    await stakingAc.connect(alice).withdrawMyFunds()
    const inWallet = await axialToken.balanceOf(aliceAddr)
    await expect(stakingAc.connect(alice).withdrawMyFunds()).to.be.revertedWith("!funds");
    const inWalletAfterClaimingTwice = await axialToken.balanceOf(aliceAddr)
    await stakingAc.connect(bob).withdrawMyFunds()
    const inBobsWallet = await axialToken.balanceOf(bobAddr)

    expect(inWallet).to.eq(inWalletAfterClaimingTwice)
    expect(inBobsWallet).to.eq(100)
  })

  it("User can stake more tokens over time", async () => {
    for (let i = 1; i < 104; ++i) {
        await axialToken.connect(deployer).mints([aliceAddr], [10]);
        await axialToken.connect(alice).approve(stakingAc.address, '10');
        await stakingAc.connect(alice).stake(10);

        if (i > 8) {
            // Bob is late to the game but has more income
            await axialToken.connect(deployer).mints([bobAddr], [20]);
            await axialToken.connect(bob).approve(stakingAc.address, '20');
            await stakingAc.connect(bob).stake(20);
        }

        if (i > 52) {
            // Carol is even later to the game but she's a whale
            await axialToken.connect(deployer).mints([carolAddr], [100]);
            await axialToken.connect(carol).approve(stakingAc.address, '100');
            await stakingAc.connect(carol).stake(100);
        }
    
        await increaseTimestamp(SECONDS_IN_A_WEEK);
    
        let staked = await stakingAc.connect(alice).getStaked(aliceAddr);
        let accrued = await stakingAc.connect(alice).getAccrued(aliceAddr);
        let total = await stakingAc.connect(alice).getTotalAccrued();
        let share = Math.round(accrued.toNumber() * 100 / total.toNumber());
        console.log("Week %d, Staked: %d Accrued: %d, Share: %d%", i, staked, accrued, share);
    }
  })

  it("User can stake again after withdrawing", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await stakingAc.connect(alice).stake(10)
    await increaseTimestamp(SECONDS_IN_A_YEAR/2)
    let accrued = await stakingAc.connect(alice).getAccrued(aliceAddr)
    await stakingAc.connect(alice).withdrawMyFunds()
    await increaseTimestamp(SECONDS_IN_A_YEAR)

    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await stakingAc.connect(alice).stake(10)
    await increaseTimestamp(SECONDS_IN_A_YEAR/2)
    let accruedAgain = await stakingAc.connect(alice).getAccrued(aliceAddr)
    await stakingAc.connect(alice).withdrawMyFunds()

    expect(accrued).to.eq(accruedAgain)

    await increaseTimestamp(SECONDS_IN_A_YEAR)
    let inWallet = await axialToken.balanceOf(aliceAddr)

    expect(inWallet).to.eq(10)
  })

  it("Accrual cannot be manipulated by sync rate", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await axialToken.connect(bob).approve(stakingAc.address, 100)
    await stakingAc.connect(alice).stake(10)
    await increaseTimestamp(SECONDS_IN_A_YEAR)
    let accrued = await stakingAc.connect(alice).getAccrued(aliceAddr)

    await stakingAc.connect(alice).withdrawMyFunds()


    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await stakingAc.connect(alice).stake(10)
    for (let i = 0; i < 52; i++ ) {
        await increaseTimestamp(SECONDS_IN_A_WEEK)
        await stakingAc.connect(bob).stake(1)
    }
    let accruedAgain = await stakingAc.connect(alice).getAccrued(aliceAddr)
    //await increaseTimestamp(SECONDS_IN_A_YEAR/2)
    //await stakingAc.connect(alice).updateAllUsersAccrual(0)
    await stakingAc.connect(alice).withdrawMyFunds()

    // Because EVM, TS, etc add latency there will be some level of discrepancy
    // The following math rounds each accrual down to the nearest day
    let accruedDayResolution = accrued.toNumber() - (accrued.toNumber() % SECONDS_IN_A_DAY)
    let accruedAgainDayResolution = accruedAgain.toNumber() - (accruedAgain.toNumber() % SECONDS_IN_A_DAY)
    expect(accruedDayResolution).to.eq(accruedAgainDayResolution)
  })


  it("Governance cannot withdraw Staked tokens", async () => {
    await axialToken.connect(alice).approve(stakingAc.address, 10)
    await stakingAc.connect(alice).stake(10)

    await expect(stakingAc.connect(governance).ownerRemoveNonDepositToken(axialToken.address)).to.be.revertedWith("!invalid");

    let axialTokenOwnedByStaking = await axialToken.balanceOf(stakingAc.address);
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

  it("getAllUsers returns an array of all users that are currently staked", async() => {
    await axialToken.connect(alice).approve(stakingAc.address, "10")
    await axialToken.connect(bob).approve(stakingAc.address, "100")
    await axialToken.connect(carol).approve(stakingAc.address, "500")

    await stakingAc.connect(alice).stake(10)
    await stakingAc.connect(bob).stake(100)
    await stakingAc.connect(carol).stake(500)

    await increaseTimestamp(SECONDS_IN_A_YEAR + 1)

    await stakingAc.connect(bob).withdrawMyFunds()

    let users = await stakingAc.connect(alice).getAllUsers()

    console.log("Users: ", users)

    expect(users.length).to.eq(2)
  })

  it("Estimating gas", async() => {
    let AVAXPerGas = await getCostOfAVAXPerGas() 
    const USDPerAVAX : number = 73.74 // Cost of 1 AVAX in USD

    let accounts: Signer[] = await ethers.getSigners()
    let costs: number[] = []
    let average: number = 0

    for (let i = 0; i < accounts.length; ++i) {
        let addr = await accounts[i].getAddress()
        let previousGasCost = (await stakingAc.estimateGas.getAccrued(addr)).toNumber()
        await axialToken.connect(deployer).mints([ addr ], [10])
        await axialToken.connect(accounts[i]).approve(stakingAc.address, 10)
        await stakingAc.connect(accounts[i]).stake(10)
        await increaseTimestamp(SECONDS_IN_A_DAY)
        let gasCost = (await stakingAc.estimateGas.getAccrued(addr)).toNumber()
        let costDifference = gasCost - previousGasCost
        //console.log("%s: %d - %d = %d", addr, gasCost, previousGasCost, costDifference)
        costs.push(gasCost)
        average += costDifference
    }

    average /= (accounts.length)
    let baseCost = costs[0] - average
    //console.log("Base Cost of Accrual Sync is %d", baseCost.toFixed(0))
    //console.log("Each user scales cost of accrual sync by ~%d", average.toFixed(0))

    let maxUsersPerBlock = (8000000 - baseCost) / average
    //let maxUsersPerBlock = await gasCostToBlockLimit(average)
    //let maxUsersPerBlock = await gasCostToBlockLimit(total / 10)

    console.log("Accrual can be calculated in chunks of up to %d users per call", maxUsersPerBlock.toFixed(0))

    let baseCostInAVAX = baseCost * AVAXPerGas
    let perUserCostInAVAX = average * AVAXPerGas

    let syncCostPerBlockInAVAX = baseCostInAVAX + (perUserCostInAVAX * maxUsersPerBlock)
    let baseCostInUSD = baseCostInAVAX * USDPerAVAX
    let perUserCostInUSD = perUserCostInAVAX * USDPerAVAX
    let syncCostPerBlockInUSD = syncCostPerBlockInAVAX * USDPerAVAX
    console.log("Each user costs 1/%d AVAX or $%d per Sync", (1/perUserCostInAVAX).toFixed(0), perUserCostInUSD.toFixed(2))
    console.log("Sync base cost is 1/%d AVAX or $%d", (1/baseCostInAVAX).toFixed(0), baseCostInUSD.toFixed(2))
    console.log("Syncing %d users costs 1/%d AVAX or $%d", maxUsersPerBlock.toFixed(0), (1/syncCostPerBlockInAVAX).toFixed(0), syncCostPerBlockInUSD.toFixed(2))
  })

})
