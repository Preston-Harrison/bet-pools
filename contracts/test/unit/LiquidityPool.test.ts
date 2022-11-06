import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import hre, { ethers } from "hardhat";
import { LiquidityToken, LiquidityToken__factory, TestToken, TestToken__factory } from "../../typechain-types";
import { $LiquidityPool } from "../../typechain-types/contracts-exposed/BettingPool/LiquidityPool.sol/$LiquidityPool";
import { $LiquidityPool__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/LiquidityPool.sol/$LiquidityPool__factory";
import { bn } from "../utils";

describe("LiquidityPool.sol", () => {
    let LiquidityPool: $LiquidityPool;
    let PoolToken: TestToken;
    let LiquidityToken: LiquidityToken;
    let deployer: SignerWithAddress;

    const mintLiquidityTokens = async (address: string, amount: BigNumber) => {
        await deployer.sendTransaction({
            to: LiquidityPool.address,
            value: bn(1)
        });
        const liquidityPool = await ethers.getSigner(LiquidityPool.address);
        return LiquidityToken.connect(liquidityPool).mint(address, amount);
    }

    beforeEach(async () => {
        [deployer] = await ethers.getSigners();
        PoolToken = await new TestToken__factory(deployer).deploy();
        LiquidityPool = await new $LiquidityPool__factory(deployer).deploy(
            PoolToken.address, 
            deployer.address, 
            deployer.address
        );
        LiquidityToken = LiquidityToken__factory.connect(
            await LiquidityPool.liquidityToken(),
            deployer
        );

        await hre.network.provider.request({
            method: "hardhat_impersonateAccount",
            params: [LiquidityPool.address],
        });
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

    it("should calculate the correct amount for deposits & withdraws", async () => {
        // 0 pool tokens, 0 liquidity tokens
        let lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(10));
        expect(lAmount).to.eq(bn(10));
        lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(1000));
        expect(lAmount).to.eq(bn(1000));

        // 10 pool tokens, 10 liquidity tokens
        await PoolToken.mint(LiquidityPool.address, bn(10));
        await mintLiquidityTokens(deployer.address, bn(10));
        lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(1000));
        let pAmount = await LiquidityPool.$calculatePoolTokenForWithdraw(bn(10));
        expect(pAmount).to.eq(bn(10))
        expect(lAmount).to.eq(bn(1000));

        // 10 pool tokens, 20 liquidity tokens
        await mintLiquidityTokens(deployer.address, bn(10));
        lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(10));
        pAmount = await LiquidityPool.$calculatePoolTokenForWithdraw(bn(10));
        expect(lAmount).to.eq(bn(20));
        expect(pAmount).to.eq(bn(5))

        // 40 pool tokens, 20 liquidity tokens
        await PoolToken.mint(LiquidityPool.address, bn(30));
        lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(10));
        pAmount = await LiquidityPool.$calculatePoolTokenForWithdraw(bn(10));
        expect(lAmount).to.eq(bn(5));
        expect(pAmount).to.eq(bn(20));

        // 40 pool tokens, 20 of which are reserved, 20 liquidity tokens
        await LiquidityPool.$increaseReservedAmount(bn(20));
        lAmount = await LiquidityPool.$calculateLiquidityTokenForDeposit(bn(10));
        pAmount = await LiquidityPool.$calculatePoolTokenForWithdraw(bn(10));
        expect(lAmount).to.eq(bn(10));
        expect(pAmount).to.eq(bn(10));
    });
});