import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { ERC20, ERC20__factory, TestToken, TestToken__factory } from "../../typechain-types";
import { $LiquidityPool } from "../../typechain-types/contracts-exposed/BettingPool/LiquidityPool.sol/$LiquidityPool";
import { $LiquidityPool__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/LiquidityPool.sol/$LiquidityPool__factory";
import { bn } from "../utils";

describe("LiquidityPool.sol", () => {
    let LiquidityPool: $LiquidityPool;
    let PoolToken: TestToken;
    let LiquidityToken: ERC20;
    let deployer: SignerWithAddress;

    beforeEach(async () => {
        [deployer] = await ethers.getSigners();
        PoolToken = await new TestToken__factory(deployer).deploy();
        LiquidityPool = await new $LiquidityPool__factory(deployer).deploy(
            PoolToken.address, 
            deployer.address, 
            deployer.address
        );
        LiquidityToken = ERC20__factory.connect(
            await LiquidityPool.liquidityToken(),
            deployer
        );
    });

    it("should increase and decrease reserved amounts", async () => {
        const tx1 = LiquidityPool.$increaseReservedAmount(bn(10));
        await expect(tx1).to.emit(LiquidityPool, "IncreaseReservedAmount").withArgs(bn(10));

        const tx2 = LiquidityPool.$decreaseReservedAmount(bn(10));
        await expect(tx2).to.emit(LiquidityPool, "DecreaseReservedAmount").withArgs(bn(10));

        const tx3 = LiquidityPool.$decreaseReservedAmount(bn(10));
        await expect(tx3).to.be.revertedWithPanic("0x11");
    });

    it("should calculate the free liquidity in the contract", async () => {
        await PoolToken.mint(LiquidityPool.address, bn(10));
        expect(await LiquidityPool.$getFreeBalance()).to.eq(bn(10));
        
        await LiquidityPool.$increaseReservedAmount(bn(5));
        expect(await LiquidityPool.$getFreeBalance()).to.eq(bn(5));

        await LiquidityPool.$decreaseReservedAmount(bn(5));
        expect(await LiquidityPool.$getFreeBalance()).to.eq(bn(10));

        await LiquidityPool.$increaseReservedAmount(bn(10));
        expect(await LiquidityPool.$getFreeBalance()).to.eq(bn(0));
    });

    it("should transfer the correct amount for deposits", async () => {
        const DEPOSIT_WITHDRAW_FEE = await LiquidityPool.DEPOSIT_WITHDRAW_FEE();
    });
});