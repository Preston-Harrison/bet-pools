import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { $BetToken } from "../../typechain-types/contracts-exposed/BettingPool/BetToken.sol/$BetToken";
import { $BetToken__factory } from "../../typechain-types/factories/contracts-exposed/BettingPool/BetToken.sol/$BetToken__factory";
import { bn, hex, r32 } from "../utils";

describe("BetToken.sol", () => {
    let BetToken: $BetToken;
    let deployer: SignerWithAddress;

    beforeEach(async () => {
        [deployer] = await ethers.getSigners();
        BetToken = await new $BetToken__factory(deployer).deploy();
    });

    it("should mint a bet and save its details", async () => {
        await expect(BetToken.getBet(1)).to.be.revertedWith("Bet does not exist");
        const market = r32();
        const side = r32();
        await BetToken.$mintBet(deployer.address, market, bn(10), bn(20), side);

        const bet = await BetToken.getBet(1);
        expect(bet.market).to.eq(hex(market));
        expect(bet.side).to.eq(hex(side));
        expect(bet.payout).to.eq(bn(20));
        expect(bet.size).to.eq(bn(10));
        expect(await BetToken.ownerOf(1)).to.eq(deployer.address);
    });

    it("should burn a bet and delete its details", async () => {
        const market = r32();
        const side = r32();
        await BetToken.$mintBet(deployer.address, market, bn(10), bn(20), side);
        await BetToken.$burnBet(1);
        await expect(BetToken.getBet(1)).to.be.revertedWith("Bet does not exist");
    });
});