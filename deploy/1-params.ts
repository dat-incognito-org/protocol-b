import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { parseEther } from 'ethers/lib/utils';

const deployFn: DeployFunction = async function(hre: HardhatRuntimeEnvironment) {
    const { deployments, getNamedAccounts } = hre;
    const { deploy } = deployments;

    const { deployer, simpleERC20Beneficiary } = await getNamedAccounts();

    await deploy('ERC20', {
        from: deployer,
        args: [simpleERC20Beneficiary, parseEther('1000')],
        log: true,
        autoMine: true, // speed up deployment on local network (ganache, hardhat), no effect on live networks
    });
};

export default deployFn;
deployFn.tags = ['ERC20'];