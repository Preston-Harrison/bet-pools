import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Signer } from "ethers";
import { ethers, network } from "hardhat";
import { BettingFactory, BettingFactory__factory, BettingOracle, BettingOracle__factory, BettingPool, BettingPool__factory, TestToken, TestToken__factory } from "../../typechain-types";
import { $BettingMath } from "../../typechain-types/contracts-exposed/BettingPool/BettingMath.sol/$BettingMath";
import { $BettingMath__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/BettingMath.sol/$BettingMath__factory";
import { bn, FeeType, getPoolAddress, hex, r32, signOdds } from "../utils";

const timestamp = async () => (await ethers.provider.getBlock("latest")).timestamp;
const increaseTime = (n: number) => network.provider.send("evm_increaseTime", [n]);

const marketId = r32();
const sideIds = [r32(), r32()];

describe("Betting", () => {
    let DEPOSIT_WITHDRAW_FEE: BigNumber;
    let BET_FEE: BigNumber;
    let ADMIN_FEE: BigNumber;
    let LP_FEE: BigNumber;

    let oddsSigner: SignerWithAddress;
    let deployer: SignerWithAddress;
    let user: SignerWithAddress;
    let Token: TestToken;
    let BettingFactory: BettingFactory;
    let BettingPool: BettingPool;
    let BettingOracle: BettingOracle;
    let BettingMath: $BettingMath;

    beforeEach(async () => {
        [deployer, user, oddsSigner] = await ethers.getSigners();
        Token = await new TestToken__factory(deployer).deploy();
        BettingFactory = await new BettingFactory__factory(deployer).deploy();
        BettingOracle = await new BettingOracle__factory(deployer).deploy(BettingFactory.address);
        await BettingFactory.setOracle(BettingOracle.address);
        const tx = await BettingFactory.createPool(Token.address);
        const poolAddress = getPoolAddress(await tx.wait(1), BettingFactory);
        BettingPool = BettingPool__factory.connect(poolAddress, deployer);
        await BettingPool.grantRole(await BettingPool.SIGNER_ROLE(), oddsSigner.address);
        await BettingOracle.openMarket(
            marketId,
            sideIds,
            await timestamp() + 1000
        );
        [BET_FEE, ADMIN_FEE, LP_FEE, DEPOSIT_WITHDRAW_FEE] = await Promise.all([
            BettingPool.BET_FEE(),
            BettingPool.ADMIN_FEE(),
            BettingPool.LP_FEE(),
            BettingPool.DEPOSIT_WITHDRAW_FEE()
        ]);
        BettingMath = await new $BettingMath__factory(deployer).deploy();
    });

    describe("placing a bet", () => {
        it("should allow a user to place a bet", async () => {
            await Token.mint(BettingPool.address, bn(1000));
            const deposit = bn(1000).mul(bn(1).sub(DEPOSIT_WITHDRAW_FEE)).div(bn(1));
            const bet = bn(10);
            const fee = bet.mul(BET_FEE).div(bn(1));
            const adminFee = fee.mul(ADMIN_FEE).div(bn(1));

            await BettingPool.deposit();
            await Token.mint(user.address, bet);
            await Token.connect(user).transfer(BettingPool.address, bet);
            const expiry = await timestamp() + 20;
            const odds = bn(2);
            
            const freeLiquidity = deposit.add(bet).sub(adminFee);
            const expectedPayout = await BettingMath.$calculatePayout(
                bet.sub(fee),
                odds,
                0,
                0,
                freeLiquidity
            );
            const tx = BettingPool.connect(user).bet(
                marketId,
                sideIds[0],
                odds,
                expiry,
                signOdds(oddsSigner, odds, hex(marketId), hex(sideIds[0]), bn(expiry, 0)),
            );
            await expect(tx)
                .to.emit(BettingPool, "IncreaseReservedAmount")
                .withArgs(expectedPayout)
                .and.to.emit(BettingPool, "Transfer")
                .withArgs(ethers.constants.AddressZero, user.address, 1)
                .and.to.emit(BettingPool, "FeeCollected")
                .withArgs(fee, FeeType.Bet);
        });
    })
});