import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { BettingFactory__factory, BettingPool__factory, TestToken, TestToken__factory, BettingFactory, BettingPool, LiquidityToken, LiquidityToken__factory, BettingOracle__factory } from "../../typechain-types";
import { bn, getPoolAddress } from "../utils";

describe("Liquidity", () => {
    let DEPOSIT_WITHDRAW_FEE: BigNumber;

    let deployer: SignerWithAddress;
    let user: SignerWithAddress;
    let Token: TestToken;
    let BettingFactory: BettingFactory;
    let BettingPool: BettingPool;
    let LiquidityToken: LiquidityToken;

    beforeEach(async () => {
        [deployer, user] = await ethers.getSigners();
        Token = await new TestToken__factory(deployer).deploy();
        BettingFactory = await new BettingFactory__factory(deployer).deploy();
        const BettingOracle = await new BettingOracle__factory(deployer).deploy(BettingFactory.address);
        await BettingFactory.setOracle(BettingOracle.address);
        const tx = await BettingFactory.createPool(Token.address);
        const poolAddress = getPoolAddress(await tx.wait(1), BettingFactory);
        BettingPool = BettingPool__factory.connect(poolAddress, deployer);
        LiquidityToken = LiquidityToken__factory.connect(await BettingPool.liquidityToken(), deployer);
        DEPOSIT_WITHDRAW_FEE = await BettingPool.DEPOSIT_WITHDRAW_FEE();
    });

    it("should allow a user to deposit and withdraw", async () => {
        await Token.mint(BettingPool.address, bn(10));
        const depositTx = BettingPool.connect(user).deposit();
        const lTokenOut = bn(10).mul(bn(1).sub(DEPOSIT_WITHDRAW_FEE)).div(bn(1));
        await expect(depositTx)
            .to.emit(BettingPool, "Deposit")
            .withArgs(user.address, bn(10), lTokenOut);

        expect(await LiquidityToken.balanceOf(user.address)).to.eq(lTokenOut);
        expect(await Token.balanceOf(user.address)).to.eq(0);

        const withdrawTx = BettingPool.connect(user).withdraw(lTokenOut);
        const pTokenOut = lTokenOut.mul(bn(1).sub(DEPOSIT_WITHDRAW_FEE)).div(bn(1));
        await expect(withdrawTx)
            .to.emit(BettingPool, "Withdraw")
            .withArgs(user.address, lTokenOut, pTokenOut);

        expect(await Token.balanceOf(user.address)).to.eq(pTokenOut);
        expect(await LiquidityToken.balanceOf(user.address)).to.eq(0);
    });
});