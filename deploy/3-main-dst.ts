import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseEther } from 'ethers/lib/utils';

const deployFn: DeployFunction = async function(hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer, relayer } = await getNamedAccounts();
    const p = await deployments.get('Parameters');

    await deploy('MainTestDst', {
        from: deployer,
        args: [1, p.address, '0x0000000000000000000000000000000000001001'],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};

export default deployFn;
deployFn.tags = ['Parameters'];
deployFn.skip = hre => Promise.resolve(hre.network.name != 'localhost' && hre.network.name != 'hardhat' && hre.network.name != 'goerli' && hre.network.name != 'mumbai');