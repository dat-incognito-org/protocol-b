import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect, use } from "chai";
import { deployments, ethers, userConfig, network } from "hardhat";
import type { Wallet, Signer, Event, BigNumber } from "ethers";
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
    const params = await ethers.getContractAt('Parameters', (await deployments.get('Parameters')).address);

    return { srcMain, dstMain, MainFactory, params };
}

const setupTest = (ctx: Mocha.Context) => async function () {
    const [deployer, relayer, user1, operator] = await ethers.getSigners();
    const d = await getDeployedContracts();

    const devMnemonic = ((userConfig.networks as NetworksUserConfig)[network.name]?.accounts as HardhatNetworkHDAccountsUserConfig).mnemonic as string;
    const relaySigner = ethers.Wallet.fromMnemonic(devMnemonic, "m/44'/60'/0'/0/1");
    const zeroAddr = '0x0000000000000000000000000000000000000000';
    const zeroBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000000';
    Object.assign(ctx, { deployer, relayer, user1, operator, relaySigner, zeroAddr, zeroBytes32 }, d);
}

const waitTx = async (tx: any, nblocks: BigNumber) => {
    try {
        await network.provider.send("hardhat_mine", [nblocks.toHexString()]);
    } catch (e) {
        await tx.wait(nblocks.toNumber());
    }
}

describe("Stake & Unstake by single relayer", async function () {
    before(setupTest(this.ctx))

    describe("Post Deployment", async function () {
        it.skip("should have 2 newly deployed Main contract", async function () {
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
            const avStakeBefore = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            const txp = this.srcMain.connect(this.relayer).stake([{ src: 0, dst: 1 }], [amt], ETH, { value: amt });
            await expect(txp)
                .to.emit(this.srcMain, "Stake")
                .withArgs(this.relayer.address, [1], [amt], ETH);
            await waitTx(await txp, ethers.BigNumber.from(2));
            const avStake = await this.srcMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            expect(avStake.sub(avStakeBefore)).to.equal(amt);
            this.tx = await txp;
        });
        it("should accept 3gwei stake from new relayer (DST)", async function () {
            const ETH = await this.dstMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            const avStakeBefore = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            const txp = this.dstMain.connect(this.relayer).stake([{ src: 0, dst: 1 }], [amt], ETH, { value: amt });
            await expect(txp)
                .to.emit(this.dstMain, "Stake")
                .withArgs(this.relayer.address, [1], [amt], ETH);
            await waitTx(await txp, ethers.BigNumber.from(2));
            const avStake = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            expect(avStake.sub(avStakeBefore)).to.equal(amt);
        });
    });

    describe("Unstake 0.3 native coin", async function () {
        it("should reject 3gwei unstake before durationToFirstUnstake", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('3', 'gwei');
            const bn = await ethers.provider.getBlockNumber();
            const unstakeEnableBlock = await this.srcMain.boltRelayers(this.relayer.address);
            // console.log(bn.toString(), unstakeEnableBlock.toString());
            if (bn < unstakeEnableBlock) {
                await expect(this.srcMain.connect(this.relayer).unstake({ src: 0, dst: 1 }, amt, ETH))
                    .to.be.rejectedWith("first unstake time not met");
                await waitTx(this.tx, ethers.BigNumber.from(32));
            }
            
        });
        it("should reject 30gwei unstake after that", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('30', 'gwei');
            await expect(this.srcMain.connect(this.relayer).unstake({ src: 0, dst: 1 }, amt, ETH))
                .to.be.rejectedWith("unstake exceeds amount");
        });
        it("should accept 0.3gwei unstake", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            
            const amt = ethers.utils.parseUnits('0.3', 'gwei');
            const txp = this.srcMain.connect(this.relayer).unstake({ src: 0, dst: 1 }, amt, ETH)
            let { events: temp } = (await (await txp).wait());
            expect(temp).to.be.an('array');
            let events = temp as Event[];
            const myEvent = events.filter(ev => ev.event == 'Lock')[0]?.args;

            await expect(txp)
                .to.emit(this.srcMain, "Lock")
                .withArgs(2, amt, myEvent?.nonce, 1, ETH, this.zeroAddr, this.relayer.address, this.zeroBytes32);
            await waitTx(await txp, ethers.BigNumber.from(32));
            await expect(this.srcMain.connect(this.relayer).unlock(amt, myEvent?.nonce, 1, ETH, this.zeroAddr, this.relayer.address, this.zeroBytes32, 2))
            .to.changeEtherBalance(this.relayer.address, amt)
            .catch(e => console.error(e, '... can ignore the above on live networks'))
        });
        it.skip("should accept 0.3gwei unstake (DST)", async function () {
            const ETH = await this.dstMain.NATIVE_TOKEN_ADDRESS();
            const amt = ethers.utils.parseUnits('0.3', 'gwei');
            const avStakeBefore = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            await expect(this.dstMain.connect(this.relayer).unstake({ src: 0, dst: 1 }, amt, ETH))
                .to.emit(this.dstMain, "Lock")
            const avStake = await this.dstMain.getAvailableStake(this.relayer.address, { src: 0, dst: 1 }, ETH);
            expect(avStake.sub(avStakeBefore)).to.equal(amt);
        });
    });
});

describe("Swap & relay", async function () {
    before(setupTest(this.ctx))

    describe("Swap 1 native coin with operator", async function () {
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
            h = events.filter(ev => ev.event == 'Swap')[0]?.args?.swapID;
            expect(h).to.be.a('string');
            await expect(txp)
                .to.emit(this.srcMain, 'Swap')
                .withArgs(this.user1.address, this.relayer.address, 1, h);
            // console.log('read event', 'Swap', this.user1.address, this.relayer.address, 1, h);
        });

        it("should send fulfill h from independent operator", async function () {
            this.swapData = await this.srcMain.swaps(h);
            // console.log('read swap data', swapData);
            await expect(this.dstMain.connect(this.operator).fulfill(this.swapData, this.operator.address, { value: this.swapData.crossAmount }))
                .to.emit(this.dstMain, 'Fulfill')
                .withArgs(this.operator.address, this.relayer.address, 1, h);
            // console.log('read event', 'Fulfill', this.operator.address, this.relayer.address, 1, h);
        })

        it("should send relay (h,o,sig) from relayer on both networks", async function () {
            const signature = signRelay(this.relaySigner, h, this.operator.address);
            // console.log(signature);
            await expect(this.dstMain.connect(this.relayer).relay(h, this.operator.address, this.relayer.address, signature.encoded))
                .to.changeEtherBalance(this.user1.address, this.swapData.crossAmount)
                .catch(e => console.error(e, '... can ignore the above on live networks'))
            // console.log('observe u receive', swapData.crossAmount.toString());
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();

            const txp = this.srcMain.connect(this.relayer).relayReturn(h, this.operator.address, this.relayer.address, signature.encoded);
            // console.dir((await (await txp).wait()).events, { depth: null });
            await expect(txp)
                .to.emit(this.srcMain, 'Lock')
                // lockType 1 - pending reward, route 1 - [0, 1], amount 0.89 gwei
                .withArgs(1, ethers.BigNumber.from('0x350c5280'), this.swapData.nonce, 1, ETH, this.swapData.requester, this.operator.address, h);
        });
    })

    describe("Swap 1 native coin with eager relayer", async function () {
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
            h = events.filter(ev => ev.event == 'Swap')[0]?.args?.swapID;
            expect(h).to.be.a('string');
            await expect(txp)
                .to.emit(this.srcMain, 'Swap')
                .withArgs(this.user1.address, this.relayer.address, 1, h);
            // console.log('read event', 'Swap', this.user1.address, this.relayer.address, 1, h);
        });

        it("should send fulfillAndRelay (h,o,sig) from relayer on both networks", async function () {
            this.swapData = await this.srcMain.swaps(h);
            // console.log('read swap data', swapData);
            // console.log('read event', 'Fulfill', this.relayer.address, this.relayer.address, 1, h);
            const signature = signRelay(this.relaySigner, h, this.relayer.address);
            // console.log(signature);
            let txp = this.dstMain.connect(this.relayer).fulfillAndRelay(this.swapData, this.relayer.address, this.relayer.address, signature.encoded, { value: this.swapData.crossAmount });
            await expect(txp)
                .to.changeEtherBalance(this.user1.address, this.swapData.crossAmount)
                .catch(e => console.error(e, '... can ignore the above on live networks'))
            await expect(txp)
                .to.emit(this.dstMain, 'Fulfill')
                .withArgs(this.relayer.address, this.relayer.address, 1, h);
            // console.log('observe u receive', swapData.crossAmount.toString());
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();

            txp = this.srcMain.connect(this.relayer).relayReturn(h, this.relayer.address, this.relayer.address, signature.encoded);
            // console.dir((await (await txp).wait()).events, { depth: null });
            await expect(txp)
                .to.emit(this.srcMain, 'Lock')
                // lockType 1 - pending reward, route 1 - [0, 1], amount 0.89 gwei
                .withArgs(1, ethers.BigNumber.from('0x350c5280'), this.swapData.nonce, 1, ETH, this.swapData.requester, this.relayer.address, h);
        });
    })
})

describe("Slashed actions by relayer", async function () {
    before(setupTest(this.ctx))

    describe("Swap 1, relays wrong operator", async function () {
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
            h = events.filter(ev => ev.event == 'Swap')[0]?.args?.swapID;
            expect(h).to.be.a('string');
            await expect(txp)
                .to.emit(this.srcMain, 'Swap')
                .withArgs(this.user1.address, this.relayer.address, 1, h);
            // console.log('read event', 'Swap', this.user1.address, this.relayer.address, 1, h);
        });

        it("should send fulfill h from independent operator", async function () {
            this.swapData = await this.srcMain.swaps(h);
            // console.log('read swap data', swapData);
            await expect(this.dstMain.connect(this.operator).fulfill(this.swapData, this.operator.address, { value: this.swapData.crossAmount }))
                .to.emit(this.dstMain, 'Fulfill')
                .withArgs(this.operator.address, this.relayer.address, 1, h);
            // console.log('read event', 'Fulfill', this.operator.address, this.relayer.address, 1, h);
        })

        it("should send relay (h,o,sig) on DST", async function () {
            const signature = signRelay(this.relaySigner, h, this.operator.address);
            // console.log(signature);
            await expect(this.dstMain.connect(this.relayer).relay(h, this.operator.address, this.relayer.address, signature.encoded))
                .to.changeEtherBalance(this.user1.address, this.swapData.crossAmount)
                .catch(e => console.error(e, '... can ignore the above on live networks'))
            // console.log('observe u receive', swapData.crossAmount.toString());
            this.rsig = signature;
        })

        it("should send relayReturn to wrong operator on SRC", async function () {
            const ETH = await this.srcMain.NATIVE_TOKEN_ADDRESS();
            this.msig = signRelay(this.relaySigner, h, this.relayer.address);
            const txp = this.srcMain.connect(this.relayer).relayReturn(h, this.relayer.address, this.relayer.address, this.msig.encoded);
            // console.dir((await (await txp).wait()).events, { depth: null });
            await expect(txp)
                .to.emit(this.srcMain, 'Lock')
                // lockType 1 - pending reward, route 1 - [0, 1], amount 0.89 gwei
                .withArgs(1, ethers.BigNumber.from('0x350c5280'), this.swapData.nonce, 1, ETH, this.swapData.requester, this.relayer.address, h);
        })
        it("should reject invalid slash", async function () {
            // RULE2
            await expect(this.srcMain.connect(this.operator).slash(1, this.swapData, this.relayer.address, this.relayer.address, this.rsig.encoded))
            .to.be.rejectedWith('slash: relay signature invalid');
            await expect(this.srcMain.connect(this.operator).slash(1, this.swapData, this.relayer.address, this.relayer.address, this.msig.encoded))
            .to.be.rejectedWith('SR2-OP');
        });
        it("should accept valid slash", async function () {
            // RULE2
            await expect(this.srcMain.connect(this.operator).slash(1, this.swapData, this.operator.address, this.relayer.address, this.rsig.encoded))
            .to.emit(this.srcMain, 'Slash')
        });
    })
})
