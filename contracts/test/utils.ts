import { BigNumberish, BytesLike, ethers } from "ethers";

export const bn = (b: BigNumberish, units = 18) => ethers.utils.parseUnits(b.toString(), units);
export const r32 = () => ethers.utils.randomBytes(32);
export const hex = ethers.utils.hexlify;