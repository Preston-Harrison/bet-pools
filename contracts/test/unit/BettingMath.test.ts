import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { $BettingMath } from "../../typechain-types/contracts-exposed/BettingPool/BettingMath.sol/$BettingMath";
import { $BettingMath__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/BettingMath.sol/$BettingMath__factory";
import { bn } from "../utils";

type BettingMathIO = {
    amount: BigNumber;
    odds: BigNumber;
    maxPayout: BigNumber;
    sidePayout: BigNumber;
    freeLiquidity: BigNumber;
    output: BigNumber;
}

describe("BettingMath.sol", () => {
    let BettingMath: $BettingMath;

    before(async () => {
        const [deployer] = await ethers.getSigners();
        BettingMath = await new $BettingMath__factory(deployer).deploy();
    });

    it("should return the correct linear output", async () => {
        for (const v of linearValues) {
            // assert that this is only linear
            expect(v.amount.mul(v.odds).div(bn(1))).to.be.lt(v.maxPayout);
            const actual = await BettingMath.$calculatePayout(
                v.amount,
                v.odds,
                v.maxPayout,
                v.sidePayout,
                v.freeLiquidity
            );
            expect(v.output).to.eq(actual);
        }
    });

    it("should return the correct scaled output", async () => {
        for (const v of scaledValues) {
            // assert that this is only scaled
            expect(v.sidePayout).to.be.gte(v.maxPayout);
            const actual = await BettingMath.$calculatePayout(
                v.amount,
                v.odds,
                v.maxPayout,
                v.sidePayout,
                v.freeLiquidity
            );
            expect(v.output).to.be
                .greaterThan(actual.mul(999).div(1000))
                .and.lessThan(actual.mul(1001).div(1000));
        }
    });

    it("should return the correct linear+scaled output", async () => {
        for (const v of linearAndScaledValues) {
            const actual = await BettingMath.$calculatePayout(
                v.amount,
                v.odds,
                v.maxPayout,
                v.sidePayout,
                v.freeLiquidity
            );
            expect(v.output).to.be
                .greaterThan(actual.mul(999).div(1000))
                .and.lessThan(actual.mul(1001).div(1000));
        }
    });
});

const linearValues: BettingMathIO[] = [
    {
        amount: bn(10),
        odds: bn(2),
        maxPayout: bn(200),
        sidePayout: bn(100),
        freeLiquidity: bn(1000),
        output: bn(20)
    },
    {
        amount: bn(20),
        odds: bn(5),
        maxPayout: bn(200),
        sidePayout: bn(100),
        freeLiquidity: bn(1000),
        output: bn(100)
    },
    {
        amount: bn(20),
        odds: bn(2.5),
        maxPayout: bn(150),
        sidePayout: bn(100),
        freeLiquidity: bn(0),
        output: bn(50)
    },
    {
        amount: bn(0),
        odds: bn(2.5),
        maxPayout: bn(150),
        sidePayout: bn(100),
        freeLiquidity: bn(240),
        output: bn(0)
    }
];

const scaledValues: BettingMathIO[] = [
    {
        amount: bn(10),
        odds: bn(2),
        maxPayout: bn(100),
        sidePayout: bn(100),
        freeLiquidity: bn(1000),
        output: bn(19.419)
    },
    {
        amount: bn(100),
        odds: bn(4),
        maxPayout: bn(100),
        sidePayout: bn(100),
        freeLiquidity: bn(200),
        output: bn(110.557)
    },
    {
        amount: bn("9999999999999999999999999"),
        odds: bn(10),
        maxPayout: bn(100),
        sidePayout: bn(100),
        freeLiquidity: bn(1000),
        output: bn(999)
    }
];

const linearAndScaledValues: BettingMathIO[] = [
    {
        amount: bn(10),
        odds: bn(10),
        maxPayout: bn(100),
        sidePayout: bn(50),
        freeLiquidity: bn(1000),
        output: bn(96.537)
    },
    {
        amount: bn(100),
        odds: bn(1.6),
        maxPayout: bn(250),
        sidePayout: bn(200),
        freeLiquidity: bn(30),
        output: bn(69.608)
    },
    {
        amount: bn(25876),
        odds: bn(7.5),
        maxPayout: bn(400),
        sidePayout: bn(200),
        freeLiquidity: bn(59849823),
        output: bn(193193.06)
    },
]