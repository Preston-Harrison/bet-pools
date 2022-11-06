import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-exposed";
import "solidity-coverage";
import "./scripts/tasks";

const config: HardhatUserConfig = {
  networks: {
    localhost: {
      url: "http://localhost:8545",
      chainId: 31337
    }
  },
  solidity: {
    version: "0.8.16",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  gasReporter: {
    enabled: true,
    currency: "USD"
  },
  contractSizer: {
    runOnCompile: true,
    except: [":\\$"]
  }
};

export default config;
