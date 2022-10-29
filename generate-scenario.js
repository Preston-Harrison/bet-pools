function generate(runs) {
    const init = {
        red: 1000,
        black: 1000,
        blue: 1000
    };
    
    const pool = {
        ...init
    }
    
    const bets = [];
    
    function getRatio() {
        if (pool.red < pool.black) {
            return `1:${pool.black/pool.red}`;
        }
        return `${pool.red/pool.black}:1`;
    }

    function rest(side) {
        return Object.keys(pool).filter(k => k !== side).reduce((acc, curr) => {
            return acc + pool[curr];
        }, 0);
    }
    
    function registerBet(amount, side) {
        pool[side] += amount;
        bets.push({
            amount,
            side,
            poolRed: pool.red,
            poolBlack: pool.black,
            poolBlue: pool.blue
        })
    }
    
    function registerAndLogBet(amount, side) {
        registerBet(amount, side);
        const payout = amount + amount * rest(side) / pool[side];
        console.log(`$${amount} on ${side}. Potential payout is $${payout.toFixed(2)} (${getRatio()})`);
    }
    
    for (let i = 0; i < runs; i++) {
        registerAndLogBet(Math.random() * 100, Object.keys(pool)[Math.floor(Math.random() * 3)]);
    }
    
    const totalBlackPayout = bets.reduce((acc, bet) => {
        if (bet.side !== "black") {
            return acc;
        }
        return acc + bet.amount + bet.amount * (bet.poolRed + bet.poolBlue) / bet.poolBlack;
    }, 0);
    
    const poolTotal = pool.red + pool.black + pool.blue - init.red - init.black - init.blue;
    const blackLpTotal = poolTotal - totalBlackPayout;
    console.log(`Total payout if black wins is $${totalBlackPayout.toFixed(2)}. LP change: ${blackLpTotal.toFixed(2)}`);

    return blackLpTotal;
}

let n = 0;
let lpChange = 0;

for (let i = 0; i < 1000; i++) {
    const blackLpTotal = generate(100);
    n += 1;
    lpChange += blackLpTotal;
}

console.log(`Average lp change = ${lpChange / n}`)