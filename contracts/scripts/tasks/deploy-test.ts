import { task } from "hardhat/config";
import { getPoolAddress } from "../../test/utils";
import { BettingFactory__factory, BettingOracle__factory, TestToken__factory } from "../../typechain-types";

task("deploy-test", "deploys a testing environment")
    .setAction(async (_, hre) => {
        const [deployer] = await hre.ethers.getSigners();
        const Token = await new TestToken__factory(deployer).deploy();
        const BettingFactory = await new BettingFactory__factory(deployer).deploy();
        const BettingOracle = await new BettingOracle__factory(deployer).deploy(BettingFactory.address);
        await BettingFactory.setOracle(BettingOracle.address);
        const tx = await BettingFactory.createPool(Token.address);
        const poolAddress = getPoolAddress(await tx.wait(1), BettingFactory);
        [
            {
                name: "Token",
                contract: Token
            },
            {
                name: "BettingFactory",
                contract: BettingFactory
            },
            {
                name: "BettingOracle",
                contract : BettingOracle
            },
            {
                name: "BettingPool",
                // hacky
                contract: { address: poolAddress }
            }
        ].forEach(e => console.log(`${e.name}: ${e.contract.address}`));
    })