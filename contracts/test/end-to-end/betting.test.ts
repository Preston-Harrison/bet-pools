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
            0,
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

        expect(await BettingPool.getSidePayout(marketId, sideIds[0])).to.eq(expectedPayout);
        const [size, reserve, maxPayout] = await BettingPool.getMarket(marketId);
        expect(size).to.eq(bet.sub(fee));
        expect(reserve).to.eq(expectedPayout);
        expect(maxPayout).to.eq(expectedPayout);
        
        const bet2 = bn(30);
        const fee2 = bet2.mul(BET_FEE).div(bn(1));
        const odds2 = bn(5);
        const freeLiquidity2 = 
            (await Token.balanceOf(BettingPool.address))
            .sub(await BettingPool.getReservedAmount());
        const expectedPayout2 = await BettingMath.$calculatePayout(
            bet2.sub(fee2),
            odds2,
            expectedPayout,
            0,
            freeLiquidity2.add(bet2.sub(fee2.mul(ADMIN_FEE).div(bn(1))))
        );
        await Token.mint(user.address, bet2);
        await Token.connect(user).transfer(BettingPool.address, bet2);
        const tx2 = BettingPool.connect(user).bet(
            marketId,
            sideIds[1],
            0,
            odds2,
            expiry,
            signOdds(oddsSigner, odds2, hex(marketId), hex(sideIds[1]), bn(expiry, 0)),
        );

        await expect(tx2)
            .to.emit(BettingPool, "IncreaseReservedAmount")
            .withArgs(expectedPayout2.sub(expectedPayout))
            .and.to.emit(BettingPool, "Transfer")
            .withArgs(ethers.constants.AddressZero, user.address, 2)
            .and.to.emit(BettingPool, "FeeCollected")
            .withArgs(fee2, FeeType.Bet);
    });

    it("should allow a user to claim a bet", async () => {
        await Token.mint(BettingPool.address, bn(1000));
        await BettingPool.deposit();

        const bet = bn(20);
        const odds = bn(3);
        const expiry = bn(await timestamp() + 1000, 0);
        const sig = await signOdds(
            oddsSigner, 
            odds, 
            hex(marketId), 
            hex(sideIds[0]), 
            expiry
        );

        await Token.mint(BettingPool.address, bet);
        await BettingPool.connect(user).bet(
            marketId,
            sideIds[0],
            0,
            odds,
            expiry,
            sig
        );
        const recordedBet = await BettingPool.getBet(1);
        await increaseTime(1000);
        await BettingOracle.setMarketWinner(marketId, sideIds[0]);

        const tx = BettingPool.claimBet(1);
        await expect(tx)
            .to.emit(BettingPool, "Transfer")
            .withArgs(user.address, ethers.constants.AddressZero, 1)
            .and.to.emit(Token, "Transfer")
            .withArgs(BettingPool.address, user.address, recordedBet.payout)
            .and.to.emit(BettingPool, "DecreaseReservedAmount")
            .withArgs(recordedBet.payout);
    });
});