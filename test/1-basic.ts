import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect, use } from "chai";
import { deployments, ethers, userConfig, network } from "hardhat";
import type { Wallet, Signer, Event } from "ethers";
import exp from "constants";
import { Main__factory } from "../typechain-types";
import { NetworksUserConfig, HardhatNetworkHDAccountsUserConfig } from "hardhat/types";
// import { Main } from "../typechain-types";

const signRelay = (signer: Wallet, swapID: string, boltOperator: string) => {
    let data = ethers.utils.solidityKeccak256(["string", "bytes32", "address"], ["\x19Bolt Signed Relay Message:\n64", swapID, boltOperator]);
    let signatureObj = signer._signingKey().signDigest(ethers.utils.arrayify(data));
    const signature = ethers.utils.splitSignature(signatureObj);
    const encoded = ethers.utils.hexlify(ethers.utils.concat([
        signature.r,
        signature.s,
        (signature.recoveryParam ? "0x1c" : "0x1b")
    ]));
    return { encoded, ...signatureObj }
}

const getDeployedContracts = async () => {
    let deployed = await deployments.get('Main');
    const MainFactory = await ethers.getContractFactory('Main');
    const srcMain = MainFactory.attach(deployed.address);
    deployed = await deployments.get('MainTestDst');
    const dstMain = await ethers.getContractAt('MainTestDst', deployed.address);

    return { srcMain, dstMain, MainFactory };
}

const setupTest = (ctx: Mocha.Context) => async function () {
    const [deployer, relayer, user1, operator] = await ethers.getSigners();
    const d = await getDeployedContracts();

    const devMnemonic = ((userConfig.networks as NetworksUserConfig)[network.name]?.accounts as HardhatNetworkHDAccountsUserConfig).mnemonic as string;
    const relaySigner = ethers.Wallet.fromMnemonic(devMnemonic, "m/44'/60'/0'/0/1");
    Object.assign(ctx, { deployer, relayer, user1, operator, relaySigner}, d);
}


describe("Stake & Unstake by single relayer", async function () {
    before(setupTest(this.ctx))

    describe("Post Deployment", async function () {
        it("should have 2 newly deployed Main contract", async function () {
            expect(await ethers.provider.getBalance(this.srcMain.address)).to.equal(0);
            expect(await ethers.provider.getBalance(this.dstMain.address)).to.equal(0);
        });

        it("should have relayer's signing key loaded", async function () {
            expect(this.relaySigner.address).to.equal(this.relayer.address);
        });
    });

    describe("Stake 3 native coin", async function () {
        it("should reject 3gwei stake to invalid route", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            await expect(this.srcMain.connect(this.relayer).stake([{ src: 1, dst: 2 }], [amt], ETH, { value: amt }))
                .to.be.rejectedWith("route must contain current net");
        });
        it("should accept 3gwei stake from new relayer", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            await expect(this.srcMain.connect(this.relayer).stake([{ src: 0, dst: 1 }], [amt], ETH, { value: amt }))
                .to.emit(this.srcMain, "Stake")
                .withArgs(this.relayer.address, [1], [amt], ETH);
            const avStake = await this.srcMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            expect(avStake).to.equal(amt);
        });
        it("should accept 3gwei stake from new relayer (DST)", async function () {
            const ETH = await this.dstMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            await expect(this.dstMain.connect(this.relayer).stake([{ src: 0, dst: 1 }], [amt], ETH, { value: amt }))
                .to.emit(this.dstMain, "Stake")
                .withArgs(this.relayer.address, [1], [amt], ETH);
            const avStake = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            expect(avStake).to.equal(amt);
        });
    });

    describe("Swap 1 native coin", async function () {
        let h: string;
        it("should send swap request of 1gwei", async function () {
            const amtSwap = ethers.utils.parseUnits('1', 'gwei');
            const lockAmt = await this.srcMain.getLockAmount(amtSwap);
            const ETH = await this.dstMain.NATIVE_TOKEN_ADDRESS();
            expect(await this.srcMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH))
                .to.gte(lockAmt);
            expect(await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH))
                .to.gte(lockAmt);

            const srcMsg = { tokenIn: ETH, tokenOut: ETH, callData: "0x", callAddress: ETH };
            const dstMsg = { tokenIn: ETH, tokenOut: ETH, callData: "0x", callAddress: this.user1.address };

            const txp = this.srcMain.connect(this.user1).swap(amtSwap, this.relayer.address, { src: 0, dst: 1 }, srcMsg, dstMsg, { value: amtSwap });
            let { events: temp } = (await (await txp).wait());
            expect(temp).to.be.an('array');
            let events = temp as Event[];
            h = events[0]?.args?.swapID;
            expect(h).to.be.a('string');
            await expect(txp)
                .to.emit(this.srcMain, 'Swap')
                .withArgs(this.user1.address, this.relayer.address, 1, h);
            // console.log('read event', 'Swap', this.user1.address, this.relayer.address, 1, h);
        });

        it("should send fulfill h & relay (h,o,sig) from separate accs", async function () {
            const swapData = await this.srcMain.swaps(h);
            // console.log('read swap data', swapData);
            await expect(this.dstMain.connect(this.operator).fulfill(swapData, this.operator.address, { value: swapData.crossAmount }))
                .to.emit(this.dstMain, 'Fulfill')
                .withArgs(this.operator.address, this.relayer.address, 1, h);
            // console.log('read event', 'Fulfill', this.operator.address, this.relayer.address, 1, h);

            const signature = signRelay(this.relaySigner, h, this.operator.address);
            // console.log(signature);
            await expect(this.dstMain.connect(this.relayer).relay(h, this.operator.address, this.relayer.address, signature.encoded))
                .to.changeEtherBalance(this.user1.address, swapData.crossAmount);
            // console.log('observe u receive', swapData.crossAmount.toString());
        });
    })
});
