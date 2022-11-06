import { BigNumberish, ethers } from "ethers";

export const bn = (b: BigNumberish, units = 18) => ethers.utils.parseUnits(b.toString(), units);
