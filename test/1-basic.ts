import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Stake & Unstake by single relayer", function() {
    async function deployFixture() {
        const [deployer, otherAccount] = await ethers.getSigners();

        const MainContract = await ethers.getContractFactory("Main");
        const mainContract = await MainContract.deploy();

        return { mainContract, deployer, otherAccount };
    }

    describe("Deployment", function() {
        it("Should set the right unmainContractTime", async function() {
            const { mainContract } = await loadFixture(deployFixture);

            expect(await ethers.provider.getBalance(mainContract.address)).to.equal(0);
        });

        // it("Should fail if the unmainContractTime is not in the future", async function () {
        //   // We don't use the fixture here because we want a different deployment
        //   const latestTime = await time.latest();
        //   const MainContract = await ethers.getContractFactory("MainContract");
        //   await expect(MainContract.deploy(latestTime, { value: 1 })).to.be.revertedWith(
        //     "UnmainContract time should be in the future"
        //   );
        // });
    });

    describe("Stake", function() {
        it("Should accept stake from new relayer", async function() {
            const { mainContract } = await loadFixture(deployFixture);
            const amt = ethers.utils.parseUnits('3', 'ether');
            await expect(mainContract.stake({ value: amt }))
            .to.emit(mainContract, "Stake")
            .withArgs(amt);
        });
    });
});
