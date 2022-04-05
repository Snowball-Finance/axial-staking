import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";
// import { parseEther } from "ethers/lib/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;

    const {deployer} = await getNamedAccounts();

    // Fuji
    const governance = "0x44A4b9E2A69d86BA382a511f845CbF2E31286770";
    const axialToken = "0x57b8a194230ef402584130B1eD31d2C4682d7a71";

    // const governance = "0xfdCcf6D49A29f435E509DFFAAFDecB0ADD93f8C0";
    // const axialToken = "0xcF8419A615c57511807236751c0AF38Db4ba3351";

    const deployedContract = await deploy('veAxial', {
        from: deployer,
        contract: "AccruingStake",
        args: [axialToken, "veAxial", "veAXIAL", governance ],
    });

    console.log("Deployed contract at", deployedContract.address);
};
export default func;
func.tags = ['veAxial'];