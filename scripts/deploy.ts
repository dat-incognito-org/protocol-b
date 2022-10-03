import { ethers } from "hardhat";

async function main() {
    const C = await ethers.getContractFactory("Main");
    const c = await C.deploy();

    await c.deployed();

    console.log(`Contract deployed to ${c.address}`);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
