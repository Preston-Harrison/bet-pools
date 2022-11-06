import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber } from "ethers";
import { ethers } from "hardhat";
import { TestToken, TestToken__factory } from "../../typechain-types";
import { $FeeDistribution } from "../../typechain-types/contracts-exposed/BettingPool/FeeDistribution.sol/$FeeDistribution";
import { $FeeDistribution__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/FeeDistribution.sol/$FeeDistribution__factory";
import { bn, FeeType } from "../utils";

describe("FeeDistribution.sol", () => {
    let DEPOSIT_WITHDRAW_FEE: BigNumber;
    let BET_FEE: BigNumber;
    let LP_FEE: BigNumber;
    let ADMIN_FEE: BigNumber;

    let admin: SignerWithAddress;
    let deployer: SignerWithAddress;
    let Token: TestToken;
    let FeeDistribution: $FeeDistribution;

    beforeEach(async () => {
        [deployer, admin] = await ethers.getSigners();
        Token = await new TestToken__factory(deployer).deploy();
        FeeDistribution = await new $FeeDistribution__factory(deployer).deploy(
            Token.address,
            admin.address,
            admin.address
        );
        [
            DEPOSIT_WITHDRAW_FEE,
            BET_FEE,
            LP_FEE,
            ADMIN_FEE
        ] = await Promise.all([
            FeeDistribution.DEPOSIT_WITHDRAW_FEE(),
            FeeDistribution.BET_FEE(),
            FeeDistribution.LP_FEE(),
            FeeDistribution.ADMIN_FEE(),
        ]);
    });

    it("should transfer deposit/withdraw fees to the deployer", async () => {
        await Token.mint(FeeDistribution.address, bn(10));
        expect(await Token.balanceOf(deployer.address)).to.eq(0);

        await FeeDistribution.$collectFees(bn(10), FeeType.Deposit);
        expect(await Token.balanceOf(deployer.address)).to.eq(
            bn(10).mul(DEPOSIT_WITHDRAW_FEE).div(bn(1))
        );
        expect(await Token.balanceOf(FeeDistribution.address)).to.eq(
            bn(10).sub(bn(10).mul(DEPOSIT_WITHDRAW_FEE).div(bn(1)))
        );
        await Token.burn(deployer.address, Token.balanceOf(deployer.address));

        await FeeDistribution.$collectFees(bn(10), FeeType.Withdraw);
        expect(await Token.balanceOf(deployer.address)).to.eq(
            bn(10).mul(DEPOSIT_WITHDRAW_FEE).div(bn(1))
        );
        expect(await Token.balanceOf(FeeDistribution.address)).to.eq(
            // .mul(2) as fees were already taken in the previous test
            bn(10).sub(bn(10).mul(DEPOSIT_WITHDRAW_FEE).div(bn(1)).mul(2))
        );
    });

    it("should split bet fees between the admin and the liquidity providers", async () => {
        await Token.mint(FeeDistribution.address, bn(10));
        expect(await Token.balanceOf(admin.address)).to.eq(0);

        await FeeDistribution.$collectFees(bn(10), FeeType.Bet);
        const expectedAmountToAdmin = bn(10).mul(BET_FEE).mul(ADMIN_FEE).div(bn(1)).div(bn(1));
        // when fees are distributed to lps, the fees just stay in the pool
        const expectedPoolAmount = bn(10).sub(expectedAmountToAdmin);

        expect(await Token.balanceOf(FeeDistribution.address)).to.eq(
            expectedPoolAmount
        );
        expect(await Token.balanceOf(admin.address)).to.eq(expectedAmountToAdmin)
    });
});