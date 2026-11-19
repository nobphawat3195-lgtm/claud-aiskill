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
- Account: **USD 300 Standard** (0.01 lot = USD 1 per USD 1 move), Exness server **GMT+0**, M5 chart.
- Goals: trade often, fastest growth, **max drawdown ≤ 50%**.
- Keep answers short; tables over prose; money in USD per month.
- Cracked EAs (`_fix`, Telegram/FXProSystems, .ex5 without source): do not run or decompile. Offer the official MQL5 Market demo or a re-implementation of the logic instead.

## Current answer to "which EA"

**XMS v2.90 RECENT, original settings** (Grok-built; files in the user's Google Drive folder `XMS_v2.91_USD300_CENT100_2026-11-15`).
MT5 real tick latest year: +USD 3,461, equity DD 32.5%, 471 trades. Our replica: +USD 3,367. Beats 100% of 10,000 random-direction shuffles; always-buy loses −84R.
Keep min-lot caps 5.5% (ORB_A/DM_A/DM_L) and 2% (ASIA_B/LON_A); never use the v4.10 USD300 HIGH_RISK preset (DD halt off).
Risks: the first months skip most trades (SL > cap); results depend on start date; tuned on the same year.
Lower-risk alternative: `MQL5/Experts/XAU_DMA_EA_v5.10.mq5` (DM_A only).
New candidate (2026-11-19, untested outside the latest year): `MQL5/Experts/XAU_ORB_EA_v6.10.mq5` Asia ORB (hourly ranges 00-03 UTC) + D1 trend, hold to 12:00 UTC: single range 71 trades USD 300 → 968, DD 13%; four ranges 286 trades (~23/month), USD 300 → 1,948, DD 31% (overlap risk understated). London/NY ORB have no edge.

## Resolved (2026-11-19): the XMS .set does trade on USD 300

The user's package `XMS_USD300_BEST` (v2.90 .ex5, risk 1.5%, `InpStrategyMode=1` = RECENT) has `InpMinLotMaxRiskNew=3.0`, but source v2.91 (Drive: `XMS_v2.91_profiles_USD300_CENT100.zip`, `XMS_Risk.mqh`) shows RECENT mode sizes with `RcMinLotCap()`: ORB_A/DM_A/DM_L use `InpRcMinLotCapNew=5.5` (set in the .set), legacy modules fall back to the classic cap 2.0. So the 3.0 input is not used in RECENT mode; the replica with 5.5%/2% applies (about +USD 3,450, 404 trades, DD 44%). Caveat: source read is v2.91, the .ex5 is v2.90 (v2.91 only adds default-off options). The A/B test zip in Drive (`XAU_Claude_Research_2026-11-18`) is therefore optional.

The user has **no computer** and Grok Bot's subscription ended, so MT5 Strategy Tester is not available to them. Real trading/demo needs a Windows VPS (MT5 mobile cannot run EAs).

## Tools (all in this repo)

| Path | Purpose |
|---|---|
| `MQL5/Research/xau_daytrend/dl.py` | Download Dukascopy real ticks (hourly .bi5) → `raw/`; edit `start`/`end` |
| `MQL5/Research/xau_daytrend/dlc.py` | Download Dukascopy M1 bid/ask candles → `m1raw/` (faster, 1 file/day/side) |
| `MQL5/Research/xau_daytrend/build.py` | `raw/` → `days/*.npz` tick arrays |
| `MQL5/Research/xau_daytrend/bt.py` | Engine: `load()` ticks, `bars()`, `prepare()`, `execute(t,b,a,sig,tps)` (entry at ask/bid, SL/TP/time exit per tick) |
| `MQL5/Research/xau_daytrend/m1.py` | `load_m1()` M1 candles as 4 pseudo-ticks/min (slightly pessimistic vs real ticks) |
| `MQL5/Research/xau_daytrend/grok_rep.py`, `opt_xms.py`, `xms_years.py` | XMS module replica (ORB_A, DM_A, DM_L, ASIA_B, LON_A) and its USD 300 sizing sim |
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
2. USD 300 Standard sizing: risk 2%, use 0.01 lot only if its risk ≤ cap (5.5% default), halt at 48% DD.
3. Random-direction baseline: the real R must beat ≥ 95% of shuffles; also report always-buy.
4. If several configs were compared: PBO < 0.2 and Deflated Sharpe > 0.95.
5. Report: trades/month, win rate, avg R, $ result, max DD, monthly $ table.
6. Final proof is the user's MT5 Strategy Tester (real ticks) and 4–8 weeks demo; ask for the .htm report and, after the demo, the EA's trade log CSV (`MQL5/Files`) and run `compare_demo.py` on it.

## Already tested, do not repeat (latest year unless noted)

SMC/ICT: OB, OB+FVG, discount/premium, BOS+FVG, CHoCH+OB (all ≤ 0 R); HTF Sweep CISD [WillyAlgoTrader] M1/M5/M15 all variants ≤ +0.03R, filters fail out of sample · M5/M15 scalps (spread eats ~0.1R) · re-entries on DM_A · XMS on M1 signals (worse) · gitee wg722/xauusd-backtest strategies (market_facilitation_relock −11R; three others barely trade) · Grok v7 USD 100 USD (17/30 start dates lose > 80%) · SL optimisation of XMS (PBO 0.57: keep original) · GitHub EAs: maker-tung/xauusd-trend-follow (+0.07R, triggers add nothing over EMA200+ADX filter, SL USD 23 too wide for 300 USD) and NadirAliOfficial/engulfing-zone-ea (0 trades; points-based inputs assume 2-digit gold); most other gold EAs on GitHub are SMC/scalper/grid types already covered. The user's Drive doc `00_อ่านก่อนเริ่มงานทุกครั้ง_XAUUSD_EA` lists older dead ends (grid/martingale, EMA cross, Ichimoku, etc.).
