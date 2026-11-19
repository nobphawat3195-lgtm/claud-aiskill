# EA research toolkit

Installed automatically in new sessions by the `claud-aiskill` environment setup script (`requirements.txt`).

| Tool | What it does | When to use |
|---|---|---|
| `../xau_daytrend/bt.py` | Tick-level backtest engine: M5 bars from ticks, entry at ask/bid after bar close, SL/TP/time exit on every tick with real spread | Every strategy test (data from `dl.py` real ticks, `dlc.py` M1) |
| `../xau_daytrend/rand_base.py` | Random-direction baseline: same entries/stops/exits, direction shuffled 10,000× | Before trusting any profit: is it the signal or just gold's drift? |
| `pbo.py` | Probability of Backtest Overfitting (CSCV) and Deflated Sharpe Ratio | After choosing the best of several configs |
| `compare_demo.py` | Compare a demo/live trade log (the CSV the EAs write in `MQL5/Files`) with backtest assumptions: slippage, spread, trades/month, entry hours | After the demo, before real money |
| `report.py` | Monthly P/L table + quantstats HTML tearsheet from a trade list (`close_time,pnl`) | Presenting results |

## Workflow for a new EA

1. Backtest the latest year on real ticks with pre-registered settings (no tuning yet)
2. Random-direction baseline: real result should beat ≥ 95% of shuffles
3. If several configs were tried: PBO < 0.2 and Deflated Sharpe > 0.95 for the chosen one
4. `report.py` for the monthly table and tearsheet
5. MT5 Strategy Tester (real ticks) on the broker account, then 4–8 weeks demo

## First results with the tools (XMS modules, latest year, real ticks)

- PBO of picking the best SL setting across all 30 module/SL configs: **0.57** (choosing by in-sample is no better than a coin flip → keep the original v4.10 SLs)
- PBO within DM_A's 16 configs: 0.29; within ORB_A's 5 configs: 0.56
- Deflated Sharpe (30 trials, daily R) for single modules: ORB_A 0.89–0.92, DM_A 0.86–0.91, below 0.95 on one module and one year alone
- Taking every XMS signal at a fixed 0.01 lot on $300 (no min-lot cap) drives the balance to −$679 by Dec 2025: the 5.5%/2% caps are essential

`dukascopy-node` (npm) also works on a local PC; in this cloud environment it needs `jetta.dukascopy.com`, which is not allowed, so the Python downloaders are used instead.

## Demo checklist (before real money)

1. Open a demo account on the same broker and account type as the real one (Exness Standard USD, $300), symbol with the same suffix
2. Server time check: the first entry in the log should be at the strategy's UTC time plus the server GMT offset (`compare_demo.py` prints entry hours)
3. Run 2-4 weeks (4-8 for more trades); do not touch inputs
4. Copy the EA log from `MQL5/Files` (e.g. `xau_dma_trades.csv`) and run `python compare_demo.py <log> --bt-spread 0.60 --bt-trades-month <n>`
5. Red flags to resolve first: spread median > 1.5x backtest, mean slippage > 0.15 USD/oz, trades/month < half of expected
