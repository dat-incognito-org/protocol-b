import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseEther } from 'ethers/lib/utils';

const devSystemParameters = [[0, 5000, 1000], [0, 1000, 20000], ['1000000', '1000000', '1000000'], [500, 600, 700], [25, 20, 10, 5, 5]];

const deployFn: DeployFunction = async function(hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer, relayer } = await getNamedAccounts();

    await deploy('Parameters', {
        from: deployer,
        args: devSystemParameters,
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};

export default deployFn;
deployFn.tags = ['Parameters'];