import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

import "solidity-coverage";
import "hardhat-gas-reporter";
import "hardhat-deploy";


const config: HardhatUserConfig = {
  solidity: "0.8.17",
  gasReporter: {
    enabled: Boolean(process.env.REPORT_GAS)
  }
};

export default config;
