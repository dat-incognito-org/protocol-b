import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "solidity-coverage";
import "hardhat-gas-reporter";
import "hardhat-deploy";
import "@nomiclabs/hardhat-etherscan";

const devMnemonic = '...';
const nodeApiKey = '...';
const apiKey = '...';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [{
      version: "0.8.17",
      settings: {
        optimizer: {
          enabled: true,
          runs: 200,
        }
      }
    }],
  },
  gasReporter: {
    enabled: Boolean(process.env.REPORT_GAS)
  },
  networks: {
    hardhat: {
      accounts: {
        mnemonic: devMnemonic,
        count: 4
      },
      chainId: 31337,
    },
    localhost: {
      accounts: {
          mnemonic: devMnemonic
      }
    },
    goerli: {
      url: `https://eth-goerli.g.alchemy.com/v2/${nodeApiKey}`,
      accounts: {
          mnemonic: devMnemonic
      }
    },
    mumbai: {
      url: `https://polygon-mumbai.g.alchemy.com/v2/${nodeApiKey}`,
      accounts: {
          mnemonic: devMnemonic
      },
      verify: {
        etherscan: {
          apiUrl: 'https://api-testnet.polygonscan.com/',
          apiKey: '...'
        }
      }
    }
  },
  etherscan: {
    apiKey
  },
  namedAccounts: {
    deployer: {
        default: 0
    },
    relayer: {
        default: 1
    }
  },
  mocha: {
    timeout: 300000
  },
};

export default config;
