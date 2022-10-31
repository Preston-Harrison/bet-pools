import { BigNumber, Signer } from "ethers";
import { MockToken__factory } from "../../typechain-types";
import { BettingFactory__factory, BettingPool__factory } from "../../typechain-types/factories/contracts";

export const deploy = async (sides: string[], initialSizes: BigNumber[], bettingPeriodEnd: BigNumber, signer: Signer) => {
    const MockToken = await new MockToken__factory(signer).deploy();
    const BettingFactory = await new BettingFactory__factory(signer).deploy(MockToken.address);
    const tx = await BettingFactory.createBettingPool(sides, initialSizes, bettingPeriodEnd);
    const rc = await tx.wait(1);
    const event = rc.events?.find(event => event.event === "CreateBettingPool");
    if (!event?.args) throw new Error("No CreateBettingPool event");
    const [pool] = event.args;
    const BettingPool = BettingPool__factory.connect(pool, signer);

    return {
        BettingFactory,
        BettingPool,
        MockToken
    }
}