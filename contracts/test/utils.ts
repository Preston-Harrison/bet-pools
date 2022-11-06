import { BigNumber, BigNumberish, BytesLike, ContractReceipt, ethers, Signer } from "ethers";
import { BettingFactory, BettingFactory__factory } from "../typechain-types";

export const bn = (b: BigNumberish, units = 18) => ethers.utils.parseUnits(b.toString(), units);
export const r32 = () => ethers.utils.randomBytes(32);
export const hex = ethers.utils.hexlify;
export const rAddress = () => ethers.Wallet.createRandom().address;

export const FeeType = {
    Deposit: 0,
    Withdraw: 1,
    Bet: 2
};

export const getPoolAddress = (tx: ContractReceipt, factory: BettingFactory) => {
    return factory.interface.parseLog(tx.logs.at(-1)!).args.pool;
}

export const signOdds = async (
    signer: Signer, 
    odds: BigNumber, 
    market: string, 
    side: string, 
    expiry: BigNumber
): Promise<string> => {
    const message = ethers.utils.solidityPack(
        ["uint256", "bytes32", "bytes32", "uint256"],
        [odds, market, side, expiry]
    );
    const hash = ethers.utils.arrayify(
        ethers.utils.keccak256(message)
    );
    return signer.signMessage(hash);
}