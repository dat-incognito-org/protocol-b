import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { deployments, ethers } from "hardhat";
// import { Route } from "../typechain-types";

const signRelay = (signer: any, swapID: string, boltOperator: string) => {
    let data = ethers.utils.solidityKeccak256(["string", "bytes32", "address"], ["\x19Bolt Signed Relay Message:\n64", swapID, boltOperator]);
    let signatureObj = signer._signingKey().signDigest(ethers.utils.arrayify(data));
    const signature = ethers.utils.splitSignature(signatureObj);
    const encoded = ethers.utils.hexlify(ethers.utils.concat([
         signature.r,
         signature.s,
         (signature.recoveryParam ? "0x1c": "0x1b")
    ]));
    return { encoded, ...signatureObj }
}

const devMnemonic = '...';

const getDeployedContracts = async () => {
    let deployed = await deployments.get('Main');
    const factory = await ethers.getContractFactory('Main');
    const srcMain = factory.attach(deployed.address);
    deployed = await deployments.get('MainTestDst');
    const dstMain = await ethers.getContractAt('MainTestDst', deployed.address);
    
    return {srcMain, dstMain, factory};
}

describe("Stake & Unstake by single relayer", function() {
    // before(setupTest())

    describe("Deployment", function() {
        it("should have 2 newly deployed Main contract", async function() {
            const { srcMain, dstMain } = await getDeployedContracts();

            expect(await ethers.provider.getBalance(srcMain.address)).to.equal(0);
            expect(await ethers.provider.getBalance(dstMain.address)).to.equal(0);
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

    describe("Stake 3 native coin", async function() {
        it("(SRC) accept 3 ETH stake from new relayer", async function() {
            const { srcMain } = await getDeployedContracts();
            const [deployer, rel] = await ethers.getSigners();
            const ETH = await srcMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            await expect(srcMain.connect(rel).stake([[0, 1]], [amt], ETH, { value: amt }))
            .to.emit(srcMain, "Stake")
            .withArgs(rel.address, [1], [amt], ETH);
            const avStake = await srcMain.getAvailableStake(rel.address, [0, 1], ETH);
            expect(avStake).to.equal(amt);
        });
        it("(DST) accept 3 ETH stake from new relayer", async function() {
            const { dstMain } = await getDeployedContracts();
            const [deployer, rel] = await ethers.getSigners();
            const ETH = await dstMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            await expect(dstMain.connect(rel).stake([[0, 1]], [amt], ETH, { value: amt }))
            .to.emit(dstMain, "Stake")
            .withArgs(rel.address, [1], [amt], ETH);
            const avStake = await dstMain.getAvailableStake(rel.address, [0, 1], ETH);
            expect(avStake).to.equal(amt);
        });
    });

    describe("Swap 1 native coin", async function () {       
        let h: string;
        
        it("should send swap request", async function() {
            const { srcMain, dstMain } = await getDeployedContracts();
            const [deployer, rel, u1, op] = await ethers.getSigners();
            const amtSwap = ethers.utils.parseUnits('1', 'gwei');
            const lockAmt = await srcMain.getLockAmount(amtSwap);
            const ETH = await dstMain.NATIVE_TOKEN_ADDRESS();
            expect(await srcMain.getAvailableStake(rel.address, [0, 1], ETH))
            .to.gte(lockAmt);
            expect(await dstMain.getAvailableStake(rel.address, [0, 1], ETH))
            .to.gte(lockAmt);

            const srcMsg = { tokenIn: ETH, tokenOut: ETH, callData: "0x", callAddress: ETH};
            const dstMsg = { tokenIn: ETH, tokenOut: ETH, callData: "0x", callAddress: u1.address};

            const txp = srcMain.connect(u1).swap(amtSwap, rel.address, [0, 1], srcMsg, dstMsg, { value: amtSwap });
            const receipt = await (await txp).wait();
            h = receipt.events[0].args.swapID;
            await expect(txp)
            .to.emit(srcMain, 'Swap')
            .withArgs(u1.address, rel.address, 1, h);
            console.log('read event', 'Swap', u1.address, rel.address, 1, h);
        });

        it("should send fulfill h (from operator) & relay (h,o,sig) (from relayer)", async function() {
            const { srcMain, dstMain } = await getDeployedContracts();
            const [deployer, rel, u1, op] = await ethers.getSigners();
            const swapData = await srcMain.swaps(h);
            console.log('read swap data', swapData);
            await expect(dstMain.connect(op).fulfill(swapData, op.address, { value : swapData.crossAmount }))
            .to.emit(dstMain, 'Fulfill')
            .withArgs(op.address, rel.address, 1, h);
            console.log('read event', 'Fulfill', op.address, rel.address, 1, h);

            const w = ethers.Wallet.fromMnemonic(devMnemonic, "m/44'/60'/0'/0/1");
            const signature = signRelay(w, h, op.address);
            // console.log(signature);
            await expect(dstMain.connect(rel).relay(h, op.address, rel.address, signature.encoded))
            .to.changeEtherBalance(u1.address, swapData.crossAmount);
            console.log('observe u receive', swapData.crossAmount.toString());
        });
    })
});
