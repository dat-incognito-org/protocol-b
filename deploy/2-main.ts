import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const deployFn: DeployFunction = async function(hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer, relayer } = await getNamedAccounts();
    const p = await deployments.get('Parameters');

    await deploy('Main', {
        from: deployer,
        args: [0, p.address, '0x0000000000000000000000000000000000001000'],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};

export default deployFn;
deployFn.tags = ['Parameters'];