---
name: xau-ea-research
description: >
  Backtest and validate XAUUSD (gold) EA ideas for this repo's owner on real Dukascopy ticks:
  tick-level engine, random-direction baseline, PBO / Deflated Sharpe overfitting checks and
  monthly reports. Use when the user asks to backtest, test, compare or optimise an EA or trading
  strategy (Thai: แบ็กเทส, ทดสอบ, กลยุทธ์, อีเอ, ออฟติไมซ์), shares an EA package or a strategy
  screenshot, or asks how much profit an EA makes per month.
---

# XAU EA research

Reply in Thai. The user is an MQL5 developer (gold scalping/intraday, MetaTrader 5, Exness).

## User's standing rules (do not re-ask)

- **Test only the latest year** (currently 2025-11-01 → today). Do not run multi-year tests unless asked; it wastes tokens.
- Account: **USD $300 Standard** (0.01 lot = $1 per $1 move), Exness server **GMT+0**, M5 chart.
- Goals: trade often, fastest growth, **max drawdown ≤ 50%**.
- Keep answers short; tables over prose; money in USD per month.
- Cracked EAs (`_fix`, Telegram/FXProSystems, .ex5 without source): do not run or decompile. Offer the official MQL5 Market demo or a re-implementation of the logic instead.

## Current answer to "which EA"

**XMS v2.90 RECENT, original settings** (Grok-built; files in the user's Google Drive folder `XMS_v2.91_USD300_CENT100_2026-11-15`).
MT5 real tick latest year: +$3,461, equity DD 32.5%, 471 trades. Our replica: +$3,367. Beats 100% of 10,000 random-direction shuffles; always-buy loses −84R.
Keep min-lot caps 5.5% (ORB_A/DM_A/DM_L) and 2% (ASIA_B/LON_A); never use the v4.10 USD300 HIGH_RISK preset (DD halt off).
Risks: the first months skip most trades (SL > cap); results depend on start date; tuned on the same year.
Lower-risk alternative: `MQL5/Experts/XAU_DMA_EA_v5.10.mq5` (DM_A only).

## Open item (2026-11-19): does the XMS .set actually trade on $300?

The user's package `XMS_USD300_BEST` (v2.90 .ex5, risk 1.5%) has `InpMinLotMaxRiskNew=3.0`. Replica: cap 3.0% → 0 trades, cap 5.5% → +$3,456 / 404 trades / DD 44%. Unknown whether RECENT mode really applies the input. A/B test files (original vs 5.5) are in the user's Drive folder `XAU_Claude_Research_2026-11-18` (`XMS_USD300_AB_test.zip`). The user has **no computer**; MT5 runs only through Grok Bot (usage limit resets Mon 2026-11-23 18:52). Next step: get the two .htm reports (trade count decides), compare with the replica. Real trading without a PC needs a Windows VPS (MT5 mobile cannot run EAs).

## Tools (all in this repo)

| Path | Purpose |
|---|---|
| `MQL5/Research/xau_daytrend/dl.py` | Download Dukascopy real ticks (hourly .bi5) → `raw/`; edit `start`/`end` |
| `MQL5/Research/xau_daytrend/dlc.py` | Download Dukascopy M1 bid/ask candles → `m1raw/` (faster, 1 file/day/side) |
| `MQL5/Research/xau_daytrend/build.py` | `raw/` → `days/*.npz` tick arrays |
| `MQL5/Research/xau_daytrend/bt.py` | Engine: `load()` ticks, `bars()`, `prepare()`, `execute(t,b,a,sig,tps)` (entry at ask/bid, SL/TP/time exit per tick) |
| `MQL5/Research/xau_daytrend/m1.py` | `load_m1()` M1 candles as 4 pseudo-ticks/min (slightly pessimistic vs real ticks) |
| `MQL5/Research/xau_daytrend/grok_rep.py`, `opt_xms.py`, `xms_years.py` | XMS module replica (ORB_A, DM_A, DM_L, ASIA_B, LON_A) and its $300 sizing sim |
| `MQL5/Research/xau_daytrend/rand_base.py` | Random-direction baseline (10,000 shuffles) |
| `MQL5/Research/toolkit/pbo.py` | `pbo(M)` (CSCV) and `deflated_sharpe(r, n_trials)` |
| `MQL5/Research/toolkit/report.py` | Monthly table + quantstats HTML from `close_time,pnl` CSV |
| `MQL5/Research/toolkit/compare_demo.py` | Demo/live EA log (CSV the EAs write) vs backtest: slippage, spread, trades/month, entry hours (wrong GMT offset check) |
| `MQL5/Research/xau_daytrend/README.md` | Every result so far (read before testing an idea; it may already be done) |

Python deps install automatically via the environment setup script (`MQL5/Research/toolkit/requirements.txt`).

## Data notes

- Data is not committed and the container is wiped between sessions: re-download into the scratchpad. Copy the scripts there and run them with `python3 -I`.
- Proxy throughput is ~0.4 files/s: one year of real ticks ≈ 4–5 h (run `dl.py` in the background, newest first); one year of M1 ≈ 15 min. Start M1 first if results are needed quickly, verify with ticks later.
- Allowed hosts: `datafeed.dukascopy.com`, `gitee.com`. `dukascopy-node` needs `jetta.dukascopy.com` (not allowed); use the Python downloaders.
- Node fetch needs `NODE_USE_ENV_PROXY=1`. The `$` sign in matplotlib titles renders as math: write "USD".

## Validation workflow (apply to every new strategy)

1. Pre-register ≤ 4 configs before running; latest year; real ticks; train = Nov–Jun, test = Jul–now (report both, select on train only).
2. $300 Standard sizing: risk 2%, use 0.01 lot only if its risk ≤ cap (5.5% default), halt at 48% DD.
3. Random-direction baseline: the real R must beat ≥ 95% of shuffles; also report always-buy.
4. If several configs were compared: PBO < 0.2 and Deflated Sharpe > 0.95.
5. Report: trades/month, win rate, avg R, $ result, max DD, monthly $ table.
6. Final proof is the user's MT5 Strategy Tester (real ticks) and 4–8 weeks demo; ask for the .htm report and, after the demo, the EA's trade log CSV (`MQL5/Files`) and run `compare_demo.py` on it.

## Already tested, do not repeat (latest year unless noted)

SMC/ICT: OB, OB+FVG, discount/premium, BOS+FVG, CHoCH+OB (all ≤ 0 R) · M5/M15 scalps (spread eats ~0.1R) · re-entries on DM_A · XMS on M1 signals (worse) · gitee wg722/xauusd-backtest strategies (market_facilitation_relock −11R; three others barely trade) · Grok v7 $100 USD (17/30 start dates lose > 80%) · SL optimisation of XMS (PBO 0.57: keep original). The user's Drive doc `00_อ่านก่อนเริ่มงานทุกครั้ง_XAUUSD_EA` lists older dead ends (grid/martingale, EMA cross, Ichimoku, etc.).
