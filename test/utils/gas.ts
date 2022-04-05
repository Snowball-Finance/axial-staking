import { ethers } from "hardhat"

export async function getCostOfAVAXPerGas() {
    let etherscanProvider = await new ethers.providers.JsonRpcProvider("https://api.avax.network/ext/bc/C/rpc")
    return (await etherscanProvider.getGasPrice()).toNumber() * 1/1e18
}

export async function gasCostToBlockLimit(gasCost: number) {
    const gasLimit : number = 8000000 // AVAX Gas Limit is set to 8m Gas Cost
    return gasLimit / gasCost
}

export async function gasCostToAvax(gasCost:number) {
    let etherscanProvider = await new ethers.providers.JsonRpcProvider("https://api.avax.network/ext/bc/C/rpc")
    let nAVAXPerGas1e18 = (await etherscanProvider.getGasPrice()).toNumber()
    return gasCost * nAVAXPerGas1e18 * 1/1e18;
}

export async function gasCostToUSD(gasCost:number, USDPerAVAX:number) {
    let avaxCost = await gasCostToAvax(gasCost)
    return avaxCost * USDPerAVAX
}