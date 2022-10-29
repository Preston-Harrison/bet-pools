# PvP Betting System
A betting 'round' starts with a seed amount on all sides. This sets the initial odds the LPs want to offer. 
When a user places a bet, their payout (on top of their initial amount) is defined as:
```
payout = bet size * total bets on other sides / total bets on user side
```

At the end of the betting round, those who bet on the losing sides lose their funds. Those who bet on the winning
side get paid out first with the funds of the losing sides, then with funds in the LP if the losing sides' funds 
are not enough. Any funds left from the losers is returned to the LP.