import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

import fs from "fs";

const remappings = fs
  .readFileSync("remappings.txt", "utf8")
  .split("\n")
  .filter(Boolean)
  .map((line) => line.trim().split("="));

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.26", // Adjust to your required version
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      viaIR: true, // Enable Intermediate Representation (IR)
    },
  },
  paths: {
    sources: "./src",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  preprocess: {
    eachLine: async (hre, source) => {
      remappings.forEach(([key, value]) => {
        source = source.replace(new RegExp(`import ["']${key}(.*?)["'];`, "g"), `import "${value}$1";`);
      });
      return source;
    },
  },
};

export default config;
