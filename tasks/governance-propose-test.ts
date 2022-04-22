import { Governance, ERC20 } from "../typechain"
import { ethers } from "ethers"

import { task, types } from "hardhat/config"
import { HardhatRuntimeEnvironment } from "hardhat/types"

task("governance-propose-test", "Creates a test proposal for Governance")
    .setAction(async (taskArgs, env: HardhatRuntimeEnvironment) => {
    const {ethers} = env; // get ethers from environment

    const governance = (await env.ethers.getContractAt("Governance", "0xe9F07E9129FB2647A7d5F44EFF58fE973446EdD8")) as Governance;
    const axial = (await env.ethers.getContractAt("ERC20", "0x0708f10f657b16abe18954361e96a641b217648b")) as ERC20;

    const signers = await ethers.getSigners();
    const executor = signers[0];
    const friend = "0xC99Ee029ebaeaf473eF69Aef6633489d9aE53385";

    const funcTransfer1AxialToFriend = axial.interface.encodeFunctionData("transfer", [friend, 1]);
    const funcTransfer10AxialToFriend = axial.interface.encodeFunctionData("transfer", [friend, 10]);

    const executionContexts = 
        await governance.connect(executor).constructProposalExecutionContexts(
            ["Send 1 Axial to friend", "Send 10 Axial to friend"],
            [axial.address, axial.address],
            [0, 0],
            [funcTransfer1AxialToFriend, funcTransfer10AxialToFriend]
        );

    const metaData =
        await governance.connect(executor).constructProposalMetadata(
            "Send some Axial to my friend",
            "This proposal is to decide if we should send 1 axial or 10 axial to our friend",
            604800,
            false
        );

    await governance.connect(executor).propose(metaData, executionContexts);

})

module.exports = {};