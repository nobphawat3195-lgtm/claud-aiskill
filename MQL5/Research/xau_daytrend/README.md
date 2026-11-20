# XAUUSD research: session setups vs. D1 day-trend

Tick-level research behind `MQL5/Experts/XAU_DayTrend_EA_v3.00.mq5`.

## Data

- Dukascopy XAUUSD M1 bid/ask candles, 2023-11-01 to 2026-11-13 (`dlc.py`, loaded by `m1.py` as 4 pseudo-ticks per minute)
- Dukascopy XAUUSD real ticks for verification (`dl.py` → `build.py` → `days/*.npz`)
- Data files are not committed. Run the downloaders into this folder first.

## Engine

- `bt.py`: M5 bid bars built from ticks; entry at the first tick after the signal bar closes, at ask (buy) or bid (sell); SL/TP/time exit checked on every tick with real bid/ask spread
- `setups.py`: the six session setups tested first
- Years: Y1 = 2023-11..2024-10, Y2 = 2024-11..2025-10, Y3 = 2025-11..2026-11

## Results (sum of R per year, M1 bid/ask)

Session setups (`run_m1.py`, `years.py`), best exit per setup. None is positive in all three years:

| Setup | Y1 | Y2 | Y3 |
|---|---|---|---|
| ASIA_PB, hold to 20:30 | -108.0 | -67.4 | +57.7 |
| LON_BRK, TP 1R | +7.5 | -6.4 | +13.6 |
| NY_PB, TP 1R | +0.1 | -13.7 | -3.8 |
| NY_ORB, hold | -15.6 | +29.0 | -24.7 |

Day-trend (`daytrend.py`): enter 01:00 UTC in the direction of D1 close vs EMA50 (days end 22:00 UTC), SL 0.3 × ADR(14), no TP, exit 20:30 UTC (19:30 in US DST):

| | Y1 | Y2 | Y3 |
|---|---|---|---|
| Sum R | +18.8 | +18.8 | +18.3 |

- 770 trades, mean +0.073R, win rate 39%, t-stat 1.25 over 3 years (a small edge, not statistically strong)
- Sensitivity (`sens.py`): entries 00:30, 01:00 and 01:30 with exits 17:00, 19:00 and 20:30 are positive in all three years (9 of 9); entries from 02:00 on decay
- Real-tick check (`tickcheck.py`) on 2026-10-01..2026-11-13: same direction on 100% of days, median difference 0.015R per trade, ticks +11.4R vs M1 +9.9R

## Risk for a $300 Cent account (`risk.py`)

1-year block bootstrap, 5000 runs, with DD scaling (half risk at 25% DD, quarter at 40%) and a halt at 45%:

| Risk per trade | Median end | 10th pct | 90th pct | P(halt) | Median max DD | P(loss) |
|---|---|---|---|---|---|---|
| 1% | $339 | $242 | $466 | 0% | 20% | 32% |
| 1.5% | $341 | $223 | $571 | 0% | 28% | 38% |
| 2% | $343 | $210 | $670 | 3% | 33% | 39% |
| 3% | $328 | $186 | $827 | 25% | 41% | 44% |

The median stops improving beyond about 2%; higher risk only widens the spread of outcomes and the chance of a halt.

## $300 Standard account, last year only (2025-11-01..2026-11-13)

Train 2025-11..2026-06, test 2026-07..2026-11. Standard account: 0.01 lot minimum, $1 per $1 move.

**M5 scalps** (`scalp.py`, `scalp_mid.py`): 168 configs (trend filter D1/H1/none × pullback/breakout/fade × Asia/London/NY/all × TP 1/1.5/2R × max hold 1h/2h), SL 1 × ATR(M5) ($4–8, i.e. 1.3–2.7% of $300 at 0.01 lot):

| Spread | Positive in train | Positive in train and test |
|---|---|---|
| Dukascopy real (~$0.66) | 0 / 168 | 0 |
| $0.30 | 18 / 168 | 0 |
| 0 (mid price) | 48 / 168 | 28 |

The best scalps have a gross edge of about +0.06–0.07R per trade; the spread costs 0.07–0.13R per trade.

**D1 trend, smaller stops** (`trend_re.py`): one 01:00 UTC entry, SL 0.15 or 0.20 × ADR, is positive in train and test (+30.3/+18.0R and +38.7/+15.5R); re-entries on M5 pullbacks lose in every variant.

**$300 Standard simulation** (`std2.py`): with the 0.01 lot floor these stops risk 3–10% of the account per trade. Every variant hits the 45% DD halt on the actual last-year sequence; block-bootstrap halt probability is 71–100%.

## Any timeframe, $300 Standard, last year (`anytf.py`, `h4sim.py`)

162 configs: M15/H1/H4 × pullback/breakout/band-reversion × trend from own EMA50 or D1 × fixed SL $6/$9/$12 × TP 1/2/3R; max hold 48 bars, flat Friday 20:00 UTC.

| Timeframe | Share positive in train and test |
|---|---|
| M15 | 0% |
| H1 | 2% |
| H4 | 13% |

Chosen for `XAU_H4Trend_EA_v4.00.mq5`: H4 EMA20 pullback in the D1 trend, SL $12, TP 2R. 152 trades (~0.6/day), win 39%, +0.16R per trade; train +20.8R, test +3.4R.

$300 Standard at 3% risk (0.01 lot floor): actual path $590 with 41% max DD; week-block bootstrap (2000 runs) median $557, 10th pct $178, 90th pct $887, P(loss) 28%, P(45% halt) 29%. Chosen as the best of 162, so expect live results below the backtest.

## Out-of-sample check of XAU Growth EA v4.10 modules (`grok_rep.py`, `grok_sim.py`, `grok_tick.py`)

v4.10 (built with Grok Bot) tuned its modules on 2026-05-12..2026-11-11. The five core modules were replicated at v4.10 parameters on Exness-style UTC days and run on the 2.5 years before that window. Sum R (trades):

| Module | Nov 23–Oct 24 | Nov 24–Oct 25 | Nov 25–May 26 | Grok DEV | Grok HO |
|---|---|---|---|---|---|
| DM_A | +35.9 (106) | +53.2 (117) | +22.1 (71) | +22.0 (49) | +5.7 (17) |
| ORB_A | +5.4 (201) | +23.3 (264) | +7.6 (132) | +34.6 (104) | +3.0 (35) |
| DM_L | −6.7 (201) | +28.6 (260) | −9.4 (135) | +23.5 (102) | +7.5 (32) |
| ASIA_B | −4.0 (39) | +23.0 (77) | −7.2 (43) | +18.4 (30) | +10.7 (10) |
| LON_A | −13.9 (98) | +9.1 (113) | −9.4 (41) | +13.1 (37) | +4.9 (10) |

Replication check on Grok's DEV window: ORB_A 34.6R vs Grok 35.6R, DM_A 22.0R vs 27.4R, DM_L 23.5R vs 26.1R. Real ticks 2026-04-23..2026-11-13 vs M1: DM_A +38.9R vs +40.9R (72 trades).

$300 Standard, DM_A only, 3% risk, skip when 0.01 lot risks more than 5%: $300 start each year → $521 / $986 / $929, max DD 29–37%, no halt; week-block bootstrap median $639, P(loss) 25%, P(45% halt) 26%. Adding ORB_A (median SL ~$17) makes the $300 account worse. Implemented as `XAU_DMA_EA_v5.00.mq5`.

## Full-year real-tick verification (2025-11-02..2026-11-13)

Dukascopy real ticks (6 of ~6,500 hourly files failed to download) vs M1 bid/ask pseudo-ticks, same signals:

| Strategy | Trades | Sum R, real ticks | Sum R, M1 |
|---|---|---|---|
| DayTrend v3.00 (DT_0100) | 266 | +30.5 | +17.9 |
| DM_A (v5.00) | 136 | +57.4 | +49.8 |
| ORB_A | 270 | +52.5 | +46.3 |
| DM_L | 266 | +31.4 | +22.7 |
| ASIA_B | 83 | +26.3 | +21.9 |
| LON_A | 88 | +13.0 | +8.6 |

Direction matches on every DayTrend day; median per-trade difference 0.004R. Real ticks come out higher because M1 pseudo-ticks fill stops at the bar extreme. The M1 results across three years are therefore a slightly conservative estimate.

## More trades from DM_A? (`dm_grid.py`, `dm_port.py`, `dm_cent.py`)

Grid over entry hour 01:00–06:00 UTC × ADX cap 20/25/30/35/none × SL 0.75/1.0/1.25 ATR(H1), three years:

- 01:00 is positive in all three years for every SL and ADX setting; 02:00 is weaker (SL 1.0 and 1.25 pass); 03:00–06:00 fail
- Raising the ADX cap adds trades with negative contribution: e.g. 01:00 SL 0.75 sums 38.6/74.4/53.5R at ADX < 25 but 21.9/60.0/43.9R at ADX < 35

$300 portfolios (1-year week-block bootstrap):

| Account | Setup | Trades/month | Median | P(loss) | P(halt) |
|---|---|---|---|---|---|
| Standard | 01:00 SL 1.0, 3% (v5.00) | 7–10 | $697 | 24% | 25% |
| Standard | + 02:00 SL 1.25, 3% | 17–20 | $509 | 34% | 66% |
| Cent | 01:00 SL 1.0, 3% | 9–11 | $784 | 12% | 7% |
| Cent | 01:00 SL 0.75 + 02:00 SL 1.25, 2% | 18–23 | $797 | 16% | 15% |

On Standard $300 the two entries mostly share direction, so the second one stacks risk instead of diversifying it. `XAU_DMA_EA_v5.10.mq5` adds the 02:00 entry as an option (`InpUseSecond`, off by default).

## XMS v2.90 RECENT claim on $300 USD (`xms_years.py`)

Grok's MT5 real-tick run (Exness Trial, 12 Nov 2025 – 11 Nov 2026): 471 trades, +$3,461, equity DD 32.5%. Five of its six modules (all but NY_PULLBACK), sized like RECENT (1.5% risk, min-lot cap 5.5%/2%, max open risk 8%, DD 35/45% scaling, halt 48%), $300 start each year:

| Year | Result | Trades/month | Max closed DD | Halt |
|---|---|---|---|---|
| Nov 23 – Oct 24 (M1) | $156 (−$144) | ~5 | 48% | yes, Feb 2024 |
| Nov 24 – Oct 25 (M1) | $1,679 (+$1,379) | 61 | 46% | no |
| Nov 25 – Nov 26 (real ticks) | $3,667 (+$3,367) | 34 | 44% | no |

The latest year reproduces Grok's MT5 number. 1-year week-block bootstrap over all three years:

| | Median | p10 | p90 | P(loss) | P(halt) |
|---|---|---|---|---|---|
| XMS 5 modules | $289 | $156 | $2,307 | 52% | 81% |
| DM_A only (v5.00) | $723 | $187 | $2,295 | 24% | 26% |

## Grok v7 aggressive on $100 USD (`grok_rep_v.py`, `v7_starts.py`)

v7 preset: 0.01-lot trades allowed up to 40% risk per trade, DD halt off, daily loss stop 60%, max 2 min-lot positions under $1,000; modules ORB_A (SL 2.0 ATR), DM_A (1.5), DM_L, ASIA_B, LON_A. Runner trail not modelled. $100 for six months from each month start, Jan 2024 – May 2026, plus Grok's 12 May 2026 start:

- 12 May 2026 start: $100 → $3,321 (Grok's MT5: $2,110)
- 1 May 2026 start: $100 → $18 (−82%)
- 30 starts: 6 above $100, 17 lost more than 80%, median end $14

Grok's own README for this package: "USD $100 standard — NO robust config exists"; v7 from 07.01 −89%, 09.01 −90%, holdout −89.4%, earlier 6 months −88.4%.

## SMC Order Block on H1, latest year (`smc_h1.py`)

Pre-registered: fractal swings (3 bars), BOS on H1 close, OB = last opposite candle of the BOS leg, limit at the OB edge within 48 h, SL 0.1 ATR beyond the OB; real ticks 2025-11-03..2026-11-13.

| Config | Trades | Avg R | t | Train R | Test R | $300 Standard (2%, cap 6%) |
|---|---|---|---|---|---|---|
| C1 TP 2R | 255 | −0.124 | −1.42 | −7.9 | −23.8 | $208, halt |
| C2 TP 3R | 239 | −0.097 | −0.97 | −4.0 | −19.2 | $159, halt |
| C3 + FVG, TP 2R | 84 | −0.012 | −0.07 | +6.1 | −7.1 | $305, DD 34% |
| C4 + discount/premium, TP 2R | 86 | −0.273 | −1.66 | −8.4 | −15.0 | $188, halt |

## SMC S1 (BOS + FVG) and S2 (CHoCH + OB) from a TikTok system, H1 latest year (`smc_s1s2.py`)

TP 2R, limit valid 48 h, SL buffer 0.1 ATR; real ticks 2025-11-03..2026-11-13.

| Strategy | Filled | Win | Avg R | t | Train R | Test R | $300 Standard (2%, cap 6%) |
|---|---|---|---|---|---|---|---|
| S1 BOS + FVG (buy limit at FVG low edge, SL below leg swing low) | 77 | 47% | +0.093 | 0.57 | +9.6 | −2.5 | $240 (19 trades taken, median SL $29) |
| S2 CHoCH + OB (buy limit at OB top, SL below OB) | 124 | 27% | −0.249 | −2.09 | −14.7 | −16.2 | $170, halt |

## Random-direction baseline for the XMS modules, latest year (`rand_base.py`)

Same entry time, stop distance and exit; direction randomised 10,000 times. Real ticks 2025-11-03..2026-11-13.

| Module | Trades | Real R | Random mean | Random 95th | Real beats | Always buy |
|---|---|---|---|---|---|---|
| All 5 | 843 | +180.6 | +17.0 | +82.2 | 100% | −83.9 |
| ORB_A | 270 | +52.5 | −4.2 | +27.5 | 99.9% | −21.8 |
| DM_A | 136 | +57.4 | +27.1 | +60.7 | 93.1% | +1.9 |
| DM_L | 266 | +31.4 | −12.2 | +18.7 | 99.0% | −33.7 |
| ASIA_B | 83 | +26.3 | +7.5 | +30.6 | 91.1% | −4.8 |
| LON_A | 88 | +13.0 | −0.4 | +18.7 | 87.7% | −25.5 |

## gitee wg722/xauusd-backtest: market_facilitation_relock_swing (`mfi_relock.py`)

The repo's only strategy marked as passing its author's gates (its board also records the author's own MT5 run at 118 deals / −151.88). Ported 1:1 with the author's 5-year params; H4 bars from real ticks, tick count as volume, latest year:

- 12 trades, 1 winner, avg −0.92R, sum −11.0R, t −3.79 (Nov–Jun −5.0R, Jul–Nov −5.9R)
- $300 Standard (2%, cap 6%): 3 trades taken, $261 (−$39)

The repo's engine uses M1 bars with a fixed $0.30 spread; resampling labels bars by close time and fills on the next bar (no look-ahead).

## Three more gitee strategies (`gb_run.py`)

The repo's own signal code (copied unmodified: base.py, common.py and the three strategy files) with the author's params, on real-tick M1 bars (platform time GMT+2/+3, volume = tick count), executed on real ticks. Latest year:

| Strategy | Trades | Win | Avg R | Sum R | Median SL | $300 Standard |
|---|---|---|---|---|---|---|
| asia_range_expansion_continuation | 1 | 0% | −1.01 | −1.0 | $5.4 | $295 |
| inside_day_breakout (5y params) | 22 | 41% | −0.06 | −1.4 | $128 | no trade possible |
| range_expansion_failure_reversal_swing | 2 | 50% | +0.08 | +0.2 | $8.0 | $302 |

Thresholds are fixed in dollars (e.g. Asia range $3.2–13.5) and were drafted for a lower gold price, so they rarely trigger at 2026 prices.

## GitHub EAs found by search (2026-11-19), latest year, real ticks

Source read first (no DLL/WebRequest/grid/martingale in either).

**maker-tung/xauusd-trend-follow** (`tf_test.py`, license CC BY-NC): H1, long only, close > EMA200 and ADX ≥ 20, trigger MACD / Stoch / EMA9-21 cross, SL 1.25 ATR, TP 6 ATR, 60-bar exit. Author's own MT5 test: +54.8% in 2022–2026 on $10,000, PF ~1.17, win 25.8%.

| Config | Trades | Win | Avg R | t | Nov–Jun / Jul–Nov | $300 Standard (2%, cap 6%) |
|---|---|---|---|---|---|---|
| C1 default | 249 | 29% | +0.072 | 0.58 | +4.1R / +13.9R | $218, DD 50% (39 trades taken) |
| C2 TP 3 ATR | 249 | 36% | +0.085 | 0.85 | +11.3R / +9.8R | $234, DD 48% |
| C3 SL 2.0 ATR | 249 | 38% | −0.015 | −0.17 | 0 / −3.8R | no trade possible |
| Baseline: same filter, long on every 6th bar | 315 | 30% | **+0.126** | – | – | – |

The triggers add nothing over the trend filter (baseline is better); median SL $23 means 0.01 lot risks 7.7% of $300, so most signals are skipped.

**NadirAliOfficial/engulfing-zone-ea** (`ez_test.py`, M5 engulfing zone retest): defaults ported from source. 66 zones created in the year, 94 bars met trend + engulfing + swing, 28 had an active zone, 26 had left the zone, **0** had the retest engulfing candle fully inside the zone range (the code requires it) → **0 trades**. On a 3-digit gold symbol (Exness) `InpMaxSpreadPoints=50` is $0.05, below the ~$0.26–0.66 spread, so it would not trade even earlier.

## ORB Asia (00:00–01:00 UTC range) + D1 trend, hold to close — `orb_asia.py` (2026-11-19)
Latest year, real ticks, USD 300 Standard (risk 2%, min-lot cap 5.5%, halt 48%). Pre-registered 4 configs × TP {none, 2R}. Range 3–16 USD, first M5 close outside 01:05–06:00 UTC, SL = opposite range edge. Trend = prior D1 close vs EMA20.
| Config | n | avg R | sum R | Nov–Jun / Jul–Nov | beats random | USD 300 → | DD |
|---|---|---|---|---|---|---|---|
| C1 trend, edge SL, exit 12:00 | 71 | +0.67 | +47.6 | +39.3 / +8.3 | 99% | 968 | 13% |
| C2 trend, mid SL, exit 12:00 | 129 | +0.38 | +49.4 | +46.5 / +2.8 | 92% | 632 | 19% |
| C3 no trend, edge SL, exit 12:00 | 103 | +0.44 | +45.1 | +35.6 / +9.5 | 96% | 928 | 24% |
| C4 trend, edge SL, exit 20:00 | 71 | +0.75 | +53.0 | +26.1 / +26.9 | 100% | 1,031 | 30% |
2R TP variants are worse (C1 +21R, C4 +23R): hold-to-close confirmed. ~6 trades/month; losing months: C1 Jul −75 USD only. EA: `MQL5/Experts/XAU_ORB_EA_v6.00.mq5` (not compiled in cloud). Not yet run: PBO/DSR across the 8 variants, M1 vs tick check.

### More trades: other sessions and multiple ranges (`orb3.py`, `orb4.py`, 2026-11-19)
Same rules as C1 (range 1 h, D1 trend, SL opposite edge, exit 12:00 unless noted). Latest year, real ticks, USD 300, risk 2%.
| Test | n (/month) | avg R | sum R | Nov–Jun / Jul–Nov | USD 300 → | DD |
|---|---|---|---|---|---|---|
| London range 07–08, exit 16 | 101 (8) | +0.01 | +0.9 | −3.3 / +4.2 | 279 | 34% |
| NY range 13–14, exit 20 | 45 (4) | −0.07 | −3.0 | +5.3 / −8.3 | 276 | 38% |
| Asia re-entry up to 3/day | 86 (7) | +0.53 | +45.8 | +39.5 / +6.2 | 962 | 21% |
| Range 00–01 / 01–02 / 02–03 / 03–04 | 67 / 29 / 70 / 120 | +0.55 / +0.59 / +0.33 / +0.33 | +37 / +17 / +23 / +40 | all positive Nov–Jun | 759 / 481 / 589 / 782 | 16–27% |
| **Ranges 00+01+02 (overlap allowed)** | 166 (13) | +0.46 | +77.0 | +56.5 / +20.5 | 1,295 | 25% |
| **All four ranges 00–03** | 286 (23) | +0.41 | +116.6 | +95.9 / +20.7 | 1,948 | 31% |
London/NY ORB have no edge: the edge is the 00–07 UTC window. Overlapping positions are sized one after another in the sim, so real combined risk and DD are higher. EA: `XAU_ORB_EA_v6.10.mq5` (`InpRangeHours`). Not yet done: PBO/DSR, compile.

### ORB Asia: concurrent-aware sizing, PBO and DSR (`orb5.py`)
Sizing at entry uses realized equity only; DD on closed-trade equity. At USD 300 the 5.5% min-lot cap binds (SL ≈ 15 USD), so risk 1–2% gives the same result: trades run 0.01 lot at ~5% risk. 
| Ranges | USD 300 → | DD | n |
|---|---|---|---|
| 00 | 759 | 16% | 58 |
| 00+01+02 | 1,145 | 30% | 143 |
| 00–03 | 1,683 | 36% | 273 |
PBO across the 7 range combinations 0.70 (no combination can be picked as best); Deflated Sharpe (14 trials, daily R): r0 0.62, 0+1+2 0.76, 00–03 0.74, all below 0.95. Verdict: all variants positive and beat random, but not statistically proven after multiple trials; demo required.

## HTF Sweep CISD Setups [WillyAlgoTrader] v1.7.1 (TradingView) — `htf_cisd.py`, `htf_engine.py`, `htf_run.py`, `htf_opt.py` (2026-11-19)
Pine core logic ported (HTF sweep of previous / any untaken HTF high-low → LTF CISD/FVG/IFVG/breaker → limit at PD array, SL at swept extreme, BE after TP1, close at TP3, reversal, same-bar conflict skip). Latest year, real ticks (limit fills at ask/bid, exits at bid/ask).
| TF (HTF) | best of 8 variants (entry × TP) | trades | avg R |
|---|---|---|---|
| M1 (M15) | brC-Market 1/3R | 3,746 | −0.15 (all 8 −0.15 to −0.30) |
| M5 (H1) | brC-Limit 0.8/2R | 370 | −0.04 (all 8 negative) |
| M15 (H4) | brC-Limit 1/3R (default) | 127 | +0.03 (others −0.07 to 0.00) |
Outcome mix M5 default: 48% full loss, 36% break-even, 11% TP3. Spread costs ~0.13R per trade on M1 (SL ≈ 4.6 USD).
Filters (D1 EMA20 trend, 00–07 UTC, both) on M5/M15, 32 configs selected on Nov–Jun: best train M15 obOpen 00–07 1/3R +37.5R → Jul–Nov **−6.4R**; M5 all negative. M15 brC 00–07 positive in both halves but 44 trades and SL ≈ 19 USD (above the USD 300 min-lot cap); it is the known 00–07 UTC time edge, not the CISD model. Verdict: no edge; EA not written.

## 10 TradingView buy/sell indicators (`ind10.py`, `ind10_base.py`, `ind10_dsr.py`, 2026-11-20)
Author defaults; common execution: entry next tick after the signal bar, SL 1.5 ATR(14), exit/reverse on the opposite signal. Latest year, real ticks. avg R per trade (Nov–Jun / Jul–Nov):
| Indicator | M5 | M15 | H1 |
|---|---|---|---|
| UT Bot (a1, ATR10) | −0.11 | −0.07 | +0.01 (+0.05 / −0.05) |
| SuperTrend (10, 3) | −0.13 | −0.05 | −0.20 |
| Range Filter (100, 3) | −0.10 | 0.00 (−0.08 / +0.15) | −0.08 |
| Twin Range (27/1.6, 55/2) | −0.06 | −0.02 | +0.08 (+0.09 / +0.07), beats random 92% |
| Chandelier Exit (22, 3) | −0.11 | −0.02 | +0.01 |
| HalfTrend (2, 2) | −0.07 | −0.01 | +0.15 (+0.04 / +0.34), beats random 93% |
| **SSL Hybrid core (HMA 60 high/low)** | −0.08 | −0.04 | **+0.27 (+0.29 / +0.24), 341 trades, beats random 99.9%** |
| QQE MOD | −0.05 | −0.01 | +0.12, beats random 75% |
| Squeeze Momentum (exit on momentum turn) | −0.13 | +0.03 | +0.19 (+0.15 / +0.24), beats random 97% |
| Lorentzian Classification | – | 16 trades | 6 trades (port gives too few signals; not reliable) |
PBO over the 29 configs 0.095. SSL Hybrid H1: DSR 0.67 (29 trials), longs +48R and shorts +45R (always-buy only +11R), Cent 30,000 USC risk 2% → ~143,800 USC (DD 24%, 2 losing months of 13). SL median ≈ 27 USD: not tradable on Standard USD 300 (0.01 lot = 9% risk). EA: `MQL5/Experts/XAU_SSL_EA_v7.00.mq5` (not compiled in cloud). Squeeze H1 second (DSR 0.23). M5/M15 all ≤ +0.03R: spread and noise eat the edge.
SSL H1 detail (`ssl_detail.py`, `ssl_h1_equity.png`): 28 trades/month, PF 1.47, avg win +2.61R / loss −0.85R, median hold 12 h, losing months Apr −88 and Oct −142 USD (Cent USD 300). Grid HMA {40,60,80} × SL {1.0,1.5,2.0} ATR: HMA 40 fails out of sample (−0.06R), 60/80 positive in both halves; PBO 0.56 → keep the default 60 / 1.5.
