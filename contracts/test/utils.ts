import { BigNumberish, BytesLike, ethers } from "ethers";

export const bn = (b: BigNumberish, units = 18) => ethers.utils.parseUnits(b.toString(), units);
export const r32 = () => ethers.utils.randomBytes(32);
export const hex = ethers.utils.hexlify;
export const rAddress = () => ethers.Wallet.createRandom().address;

export const FeeType = {
    Deposit: 0,
    Withdraw: 1,
    Bet: 2
};