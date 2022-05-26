import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/dist/types";
// import { parseEther } from "ethers/lib/utils";

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
    const {deployments, getNamedAccounts} = hre;
    const {deploy} = deployments;

    const {deployer} = await getNamedAccounts();

    // Fuji
    // const sAxial = "0xb7819A8714fCa85239E4b881291819A79Aa703E4";

    //Mainnet
  const governance = "0x4980AD7cCB304f7d3c5053Aa1131eD1EDaf48809";
  const axialToken = "0xcF8419A615c57511807236751c0AF38Db4ba3351";
  const sAxial = "0xed7f93C8FD3B96B53c924F601B3948175D2820D8";
  const veAxial = "0x3f563F7efc6dC55adFc1B64BC6Bd4bC5F394c4b2";

    const deployedContract = await deploy('Governance', {
        from: deployer,
        contract: "Governance",
        args: [sAxial ],
    });

    console.log("Deployed contract at", deployedContract.address);
};
export default func;
func.tags = ['Governance'];