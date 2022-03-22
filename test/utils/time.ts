import { network } from "hardhat";

export async function increaseTime(sec: number) {
  await network.provider.send("evm_increaseTime", [sec]);
  await network.provider.send("evm_mine");
}

export async function increaseBlock(block: number) {
  for (let i = 1; i <= block; i++) {
    await network.provider.send("evm_mine");
  }
}

export async function fastForwardAWeek() {
  let i = 0;
  do {
    await increaseTime(60 * 60 * 24);
    await increaseBlock(60 * 60);
    i++;
  } while (i < 8);
}
