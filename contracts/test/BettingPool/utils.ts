import { ContractTransaction, Signer } from "ethers";
import { MockToken__factory } from "../../typechain-types";
import { BettingFactory__factory, LiquidityToken__factory } from "../../typechain-types/factories/contracts";

export const deploy = async (signer: Signer) => {
    const MockToken = await new MockToken__factory(signer).deploy();
    const BettingFactory = await new BettingFactory__factory(signer).deploy(MockToken.address);
    const LiquidityToken = LiquidityToken__factory.connect(await BettingFactory.liquidityToken(), signer);

    return {
        BettingFactory,
        MockToken,
        LiquidityToken
    }
}

export const getNewBettingPoolFromTx = async (tx: Promise<ContractTransaction>): Promise<string> => {
    const rc = await (await tx).wait(1);
    const event = rc.events?.find(event => event.event === "CreateBettingPool");
    if (!event?.args) throw new Error("No CreateBettingPool event");
    return event.args[0];
}