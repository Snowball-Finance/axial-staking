import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";
// import { parseEther } from "ethers/lib/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;

    const {deployer} = await getNamedAccounts();

    // Fuji
    const governance = "0x44A4b9E2A69d86BA382a511f845CbF2E31286770";
    const axialToken = "0x0708F10F657b16ABE18954361E96a641b217648B";
    const sAxial = "0xb7819A8714fCa85239E4b881291819A79Aa703E4";
    const veAxial = "0xeD8583AD6e9A266f38866a1E8058436a4b742D57";

    // const governance = "0xfdCcf6D49A29f435E509DFFAAFDecB0ADD93f8C0";
    // const axialToken = "0xcF8419A615c57511807236751c0AF38Db4ba3351";

    const deployedContract = await deploy('GaugeProxy', {
        from: deployer,
        contract: "GaugeProxy",
        args: [governance, axialToken, sAxial, veAxial ],
    });

    console.log("Deployed contract at", deployedContract.address);
};
export default func;
func.tags = ['GaugeProxy'];