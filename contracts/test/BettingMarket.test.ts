import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import hre, { ethers } from 'hardhat';
import { expect } from 'chai';
import { 
    BettingPool, 
    BettingPool__factory, 
    ERC20, ERC20__factory, 
    MockToken, 
    MockToken__factory 
} from '../typechain-types';
import { BytesLike } from 'ethers';

type Context = {
    signers: SignerWithAddress[];
    bettingPool: BettingPool;
    token: MockToken;
    lpToken: ERC20;
}

const { utils, constants } = ethers;

const r32 = () => utils.randomBytes(32);
const hx = (v: BytesLike) => utils.hexlify(v);

describe("BettingMarket.sol", () => {
    let context: Context;

    beforeEach(async () => {
        const [deployer] = await ethers.getSigners();
        const token = await new MockToken__factory(deployer).deploy();
        const bettingPool = await new BettingPool__factory(deployer).deploy(token.address);
        const lpToken = ERC20__factory.connect(await bettingPool.liquidityToken(), deployer); 
        context = {
            signers: await ethers.getSigners(),
            bettingPool,
            token,
            lpToken
        }
    });

    it("should create a market with valid conditions", async () => {
        const market = r32();
        const sides = [r32(), r32()];
        const initialOdds = [10, 10];
        await expect(
            context.bettingPool.createMarket(market, sides, initialOdds, constants.MaxUint256)
        ).emit(context.bettingPool, "CreateMarket").withArgs(
            hx(market), 
            sides.map((s) => hx(s)), 
            initialOdds, 
            constants.MaxUint256
        );
    });

    it("should not create a market with invalid conditions", async () => {
        const sides = [r32(), r32()];
        const initialOdds = [10, 10];
        await expect(
            context.bettingPool.createMarket(constants.HashZero, sides, initialOdds, constants.MaxUint256)
        ).to.be.revertedWith("Market id cannot be zero");
        await expect(
            context.bettingPool.createMarket(r32(), [], [], constants.MaxUint256)
        ).to.be.revertedWith("Must have at least 2 sides");
        await expect(
            context.bettingPool.createMarket(
                r32(), 
                new Array(256).fill(r32()), 
                new Array(256).fill(10), 
                constants.MaxUint256
            )
        ).to.be.revertedWith("Must be less than 256 sides");
        await expect(
            context.bettingPool.createMarket(r32(), sides, [10,10,10], constants.MaxUint256)
        ).to.be.revertedWith("Array lengths must be the same");
        await expect(
            context.bettingPool.createMarket(r32(), sides, initialOdds, 0)
        ).to.be.revertedWith("Betting must end in the future");
        await expect(
            context.bettingPool.createMarket(r32(), [r32(), constants.HashZero], initialOdds, constants.MaxUint256)
        ).to.be.revertedWith("Side ID cannot be zero");
        await expect(
            context.bettingPool.createMarket(r32(), sides, [10, 0], constants.MaxUint256)
        ).to.be.revertedWith("Initial size cannot be zero");
    });

    it("should allow a user to place a bet", async () => {
        const user = context.signers[1];
        const market = r32();
        const sides = [r32(), r32()];
        const initialOdds = [10, 10];
        const five = ethers.utils.parseEther("5");
        const expectedPayout = five.add(five.mul(10).div(five.add(10)));
        await context.token.mint(user.address, five);
        await context.bettingPool.createMarket(market, sides, initialOdds, constants.MaxUint256);
        const betKey = r32();
        await context.token.connect(user).transfer(context.bettingPool.address, five);
        const tx = context.bettingPool.connect(user).bet(market, sides[0], betKey, user.address);
        await expect(tx).to.emit(context.bettingPool, "PlaceBet").withArgs(
            hx(market),
            user.address,
            hx(sides[0]),
            hx(betKey),
            five,
            expectedPayout
        );
        const bet = await context.bettingPool.getBet(market, betKey);
        expect({
            better: bet.better,
            amount: bet.amount,
            payout: bet.payout,
            side: bet.side
        }).to.eql({
            better: user.address,
            amount: five,
            payout: expectedPayout,
            side: hx(sides[0])
        });
    });

    it("should allow a user to claim their payout", async () => {
        const user = context.signers[1];
        const market = r32();
        const sides = [r32(), r32()];
        const initialOdds = [10, 10];
        const five = ethers.utils.parseEther("5");
        const expectedPayout = five.add(five.mul(10).div(five.add(10)));
        
        await context.token.mint(user.address, five);
        const { timestamp } = await ethers.provider.getBlock("latest");
        await context.bettingPool.createMarket(market, sides, initialOdds, timestamp + 100);
        const betKey = r32();
        await context.token.connect(user).transfer(context.bettingPool.address, five);
        await context.bettingPool.connect(user).bet(market, sides[0], betKey, user.address);
        
        expect(await context.token.balanceOf(user.address)).to.eq(0);
        await hre.network.provider.send("evm_setNextBlockTimestamp", [timestamp + 101])
        await context.token.mint(context.bettingPool.address, five);
        await context.bettingPool.setWinningSide(market, sides[0]);
        await context.bettingPool.connect(user).claim(market, betKey);
        expect(await context.token.balanceOf(user.address)).to.eq(expectedPayout);
    });
});