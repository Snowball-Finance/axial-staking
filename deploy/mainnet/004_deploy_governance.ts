import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";
// import { parseEther } from "ethers/lib/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;

    const {deployer} = await getNamedAccounts();

    // Fuji
    const sAxial = "0xb7819A8714fCa85239E4b881291819A79Aa703E4";

    // const governance = "0xfdCcf6D49A29f435E509DFFAAFDecB0ADD93f8C0";
    // const axialToken = "0xcF8419A615c57511807236751c0AF38Db4ba3351";

    const deployedContract = await deploy('Governance', {
        from: deployer,
        contract: "Governance",
        args: [sAxial ],
    });

    console.log("Deployed contract at", deployedContract.address);
};
export default func;
func.tags = ['Governance'];