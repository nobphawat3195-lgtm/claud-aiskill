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
"SSL Hybrid Strategy" (TradingView Pine v5, user-supplied; `ssl_strat.py`): same SSL1 entries; exits SL 1.8 ATR + 5 partial TPs (1.8/2.2/2.6/4/8 ATR) + BE after TP1. H1 latest year: +0.052R/trade (Nov–Jun +0.10 / Jul–Nov −0.02), PF 1.12, Cent USD 300 → 400, 5 losing months; with SL 1.5: +0.073R → 452. Our simple exit-on-flip: +0.266R, → 1,382. The edge is in the few large winners (avg win +2.6R); fixed TPs cut them. Keep `XAU_SSL_EA_v7.00`.

### SSL build-out: TF × HMA length × D1 trend (`ssl_grid.py`, `ssl_cand.py`, `ssl_cent.py`, 2026-11-20)
18 pre-registered configs (TF M1/M5/M15/M30/H1; HMA 60 bars or ≈60 hours capped at 960; D1 EMA20 filter on/off), exit on flip or SL 1.5 ATR. avg R (Nov–Jun / Jul–Nov):
| TF | HMA 60 | HMA 60 +D1 | HMA ≈60 h | HMA ≈60 h +D1 |
|---|---|---|---|---|
| M1 | −0.27 | −0.26 | −0.20 (960) | −0.15 |
| M5 | −0.08 | −0.03 | −0.02 (720) | **+0.24 (+0.19/+0.31), 552 tr, 45/month, SL 7.3** |
| M15 | −0.04 | +0.04 | +0.08 (240) | **+0.29 (+0.22/+0.41), 306 tr, SL 13** |
| M30 | −0.04 | +0.06 | +0.12 (120) | +0.27 (+0.18/+0.41), 226 tr |
| H1 | **+0.30 (+0.31/+0.29), 331 tr** | +0.47 (+0.57/+0.33), 156 tr | = | = |
PBO 0.0 (the in-sample best ranks well out of sample). Random baseline: M5 720+D1 97.7% (longs +9.5R, shorts +121R: fragile), M15 240+D1 96.9%, H1 99.9%. DSR (18 trials): 0.29 / 0.40 / 0.82. Win rates 16–33%, max losing streak 25 (M5). Standard USD 300 fails (0.01 lot forces 2.4–9% risk → 48% halt in Feb–Apr). Cent USD 300: H1 risk 1% → 753 (DD 11%); M15+H1 risk 1% → 1,437 (DD 30%, ~51/month); M5+M15+H1 risk 0.5% → 1,076 (DD 33%, ~96/month). EA `XAU_SSL_EA_v7.10.mq5` (chart TF, `InpHMALen`, `InpUseD1`).

### SSL optimisation round 2 (`ssl_opt2.py`, `ssl_opt2_port.py`)
M15: HMA {160,240,320} × D1 EMA {10,20,50} × SL {1.0,1.5,2.0} (27); H1: HMA {40,60,80} × SL (9). Selected on Nov–Jun.
M15 best: HMA 320 (80 h) EMA 10/20 SL 1.5: Nov–Jun +0.56R / Jul–Nov +0.48 to +0.54R (247–253 trades); HMA 160 fails out of sample. PBO 0.39.
H1 best is the default HMA 60 SL 1.5 (Jul–Nov +0.29R); HMA 40 fails. PBO 0.34.
Portfolio Cent USD 300: M15 320/EMA20 + H1 60, risk 1% → 2,232 (DD 31%, ~47 trades/month, 3 losing months) vs 240 version 1,437 (DD 30%, ~51/month). Risk 1.5% → 4,776 (DD 43%).

### SSL M5 optimisation (`ssl_opt3.py`, `ssl_port3.py`)
M5: HMA {480,720,960} × D1 EMA {10,20,50} × SL {1.0,1.5,2.0}. Train-best 960/EMA10/SL1.5: Nov–Jun +0.55R → Jul–Nov +0.08R (decays); 960/EMA20/SL1.5: +0.54 → +0.17R (452 trades, win 15%, beats random 98.8%, longs +68R / shorts +114R); HMA 480 fails. PBO 0.30.
Portfolio Cent USD 300: M15 320 + H1 60: risk 0.5% → 895 (DD 17%), 0.75% → 1,443 (DD 24%), 1% → 2,232 (DD 31%), ~47 trades/month, 2–3 losing months. Adding M5 960: ~84 trades/month, 0.5% → 1,650 (DD 33%), 0.75% → 3,026 (DD 45%), 1% → 4,872 (DD 55%), 5 losing months. M5 adds trades and return but most of the DD.

### XAU SENTINEL stages (`sentinel_bt.py`, `sentinel_stages.py`; Cent USD 300, DD halt 50%)
| Stage | Standard M15+H1 0.5 / 0.75 / 1% | High-freq M5+M15+H1 0.5 / 0.75 / 1% |
|---|---|---|
| 0 before optimisation (HMA 60 on every TF, no D1) | 343 / 343 / 330 (M15 −0.04R) | halted at DD 50% in all |
| 1 HMA ≈60 h + D1 (M15 240, M5 720) | 708 / 1,027 / 1,437 | 1,076 / 1,658 / halted |
| 2 optimised (M15 320, M5 960) = SENTINEL | 895 / 1,443 / 2,232 | 1,650 / 3,026 / halted |
Slippage 0.10 USD/side costs 5% (standard) to 13% (high-freq). Standard USD 300 account halts.

## 10 more TradingView indicators (`ind10b.py`, `ind10b_check.py`, 2026-11-20)
Defaults, SL 1.5 ATR, own exit rule (SAR types exit on opposite signal). avg R per trade:
| Indicator | M5 | M15 | H1 (Nov–Jun / Jul–Nov) |
|---|---|---|---|
| WaveTrend (LazyBear, ±53) | −0.08 | +0.14 (+0.22 / +0.01) | +0.08 (41 tr, +0.45 / −0.50) |
| Bollinger Bands Strategy | −0.12 | −0.11 | −0.12 |
| RSI(2) Connors + SMA200 | −0.11 | −0.07 | +0.05, beats random 91% |
| Stochastic RSI 20/80 | −0.12 | −0.08 | −0.12 |
| Donchian 20/10 | −0.11 | −0.05 | +0.15, beats random 86% |
| **MACD 12/26/9 (histogram sign)** | −0.08 | −0.05 | **+0.18 (+0.19 / +0.18), 446 tr, beats random 99.3%** |
| Parabolic SAR | −0.10 | −0.05 | +0.11, beats random 90% |
| Smoothed Heikin Ashi | −0.07 | −0.02 | +0.18, beats random 94% |
| DMI/ADX cross | −0.19 | −0.07 | −0.09 |
| CM Williams Vix Fix (long, 10 bars) | −0.10 | −0.05 | −0.12 |
PBO 0.056. MACD H1: longs +41R / shorts +41R, always-buy −0.3R, DSR (59 trials) 0.47, daily-R correlation with SSL H1 0.60 (same trend family), Cent USD 300 risk 0.75% → 534 (DD 14%). Mean-reversion indicators lose on every TF; M5 loses for all.

### MACD scaled to lower TFs and combined with SENTINEL (`macd_tf.py`, `port_macd.py`)
MACD histogram sign, periods ×(60 min / TF), SL 1.5 ATR, exit on flip. avg R (Nov–Jun / Jul–Nov), beats random:
| Config | n | avg | split | random |
|---|---|---|---|---|
| H1 12/26/9 | 446 | +0.18 | +0.19 / +0.18 | 99.5% |
| H1 +D1 | 215 | +0.31 | +0.31 / +0.32 | 99.3% |
| M15 48/104/36 | 455 | +0.26 | +0.22 / +0.34 | 97.6% |
| M15 +D1 | 220 | +0.43 | +0.22 / +0.81 | 96.0% |
| M5 144/312/108 | 461 | +0.11 | +0.08 / +0.17 | 90.9% |
| M5 +D1 | 222 | +0.45 | +0.34 / +0.63 | 97.2% |
PBO 0.19. Portfolios (Cent USD 300, DD halt 50%), end USD / DD at risk 0.25 / 0.5 / 0.75%:
A SSL M15+H1 (47/mo): 531/9%, 895/17%, 1,443/24% (1%: 2,232/31%) · B SSL M5+M15+H1 (84/mo): 772/18%, 1,650/33%, 3,026/45% ·
C A + MACD H1,M15 +D1 (82/mo): 756/16%, 1,653/30%, 3,201/42% · F A + MACD H1,M15 unfiltered (120/mo): 815/17%, 1,854/32%, 3,616/46% ·
D/E with M5 MACD (137–174/mo): 0.5% → 3,463–3,892 at DD 47–50%, 0.75% halts. MACD correlates with SSL (0.6), so it adds trades and return but DD scales with it; best return per DD at ≤ 31% DD is still A at 1%.

### XAU THUNDER v1.00 (MACD-only EA, `macd_port.py`)
MACD engine portfolios, Cent USD 300, DD halt 50%, end USD / DD at 0.5 / 0.75 / 1 / 1.5%:
H1: 444/9, 534/14, 637/18, 884/26 · M15: 515/15, 651/23, 805/29, 1,155/41 · **H1+M15 (73/mo)**: 730/23, 1,052/33, 1,446/42, halt ·
**H1+M15+M5(D1) (91/mo)**: 1,047/28, 1,660/40, halt, halt · H1d+M15d+M5d (53/mo): 905/26, 1,377/36, 1,946/46, halt · H1+M15d: 674/16, 960/24, 1,325/31, 2,311/43 · H1+M15+M5 unfiltered: 783/35, 1,036/49, halt.
EA `MQL5/Experts/XAU_THUNDER_v1.00.mq5` (modes H1+M15 / H1+M15+M5 D1, magic 890000+). Docs/visuals in `MQL5/Docs/thunder/`. MACD alone is weaker than SENTINEL (SSL) at the same DD.

## StraddleReverse v4.60 check (`sr_sim.py`, `sr_test.py`, `sr_test2.py`, `sr_cost.py`, 2026-11-20)
v4.60 source not found in Drive; simulated v4.40 source logic (Drive `XAU_EA_ALL_v2_20260817.zip`) with the report's v4.60 settings: straddle ±1.00, SL 12, reverse trap after +2.50 at 2.40 trailing, cooldown 300 s, max 2 SL/day, window 19:00–20:30 UTC (= Thai 02:00–03:30), close at window end, 0.01 lot. Dukascopy ticks Nov 2025–Nov 2026; trade count 112/month matches the report (~113).
| Variant | avg USD/trade | Nov–Aug / Sep–Nov | PF |
|---|---|---|---|
| Dukascopy spread (median 0.63 in window) | −0.60 | −0.60 / −0.66 | 0.72 |
| Window shift −60/−30/+30/+60 min | −0.94 / −0.89 / −0.75 / −0.82 | all negative | 0.60–0.66 |
| Slippage 0.05 / 0.10 / 0.20 per fill | −0.69 / −0.76 / −1.00 | | |
| Fixed spread 0.10 / 0.15 / 0.20 / 0.25 / 0.30 | +0.06 / +0.05 / +0.02 / −0.03 / −0.07 | Sep–Nov −0.21 to −0.33 at every spread | 0.96–1.03 |
| ATR(f)/ATR(s) < 0.95 filters (5/20, 14/50, 14/100) | −0.70 to −0.77 (−0.13 to −0.26 at spread 0.30) | | |
Win rate 64% at spread 0.30 matches the report, but the report's +0.51 USD/trade does not replicate: even at 0.10 spread the edge is +0.06 and the months after the report's sample (Sep–Nov 2026) are negative at every spread. Consistent with the Drive handoff (2026-09-08): breakout-straddle cost ≈ 3.3× edge on gold.

## Third batch: 10 TradingView indicators (`ind10c*.py`, 2026-11-20)
Defaults, SL 1.5 ATR, exit/reverse on opposite signal. avg R (H1 Nov–Jun / Jul–Nov):
| Indicator | M5 | M15 | H1 |
|---|---|---|---|
| Hull Suite (HMA 55) | −0.09 | −0.05 | +0.12 (+0.15/+0.07), random 89% |
| Keltner Channels Strategy | −0.05 | +0.01 | +0.28 (77 tr), random 39% |
| **Aroon 14** | −0.10 | −0.04 | **+0.12 (+0.15/+0.08), 407 tr, random 98.1%** |
| Vortex 14 | −0.09 | −0.03 | +0.01 |
| **Coral Trend (LazyBear 21/0.4)** | −0.07 | +0.01 | **+0.18 (+0.13/+0.27), 282 tr, random 97.3%** |
| Zero Lag Trend (AlgoAlpha 70/1.2) | −0.15 | −0.05 | +0.06 |
| Pivot Point SuperTrend | −0.15 | −0.03 | +0.01 |
| Fisher Transform 9 | −0.11 | −0.05 | −0.04 |
| KAMA 10/2/30 | −0.11 | −0.04 | −0.01 |
| CCI 20 ±100 | −0.08 | −0.02 | +0.19 (+0.09/+0.35), random 94.6% |
PBO 0.048; DSR (89 cumulative trials) 0.06–0.16. Scaling Aroon/Coral to M15 (×4) / M5 (×12) ± D1 fails (random 34–90%, Coral M15/M5 negative Nov–Jun); H1 +D1: Aroon +0.29R (187 tr, 96.9%), Coral +0.48R (122 tr, 98.4%). PBO of the 10 scaled configs 0.17.
Cent USD 300 risk 0.75%: Aroon H1 418 (DD 18%), Coral H1 428 (DD 12%), both 570 (DD 23%). Adding to SENTINEL standard does not improve return per DD: SENTINEL std 1% → 2,232 / DD 31% vs SENTINEL std + Coral 0.75% → 1,849 / DD 33%, + Aroon + Coral 0.75% → 2,217 / DD 39%. Daily-R correlation with SSL H1 0.46–0.51 (same trend family).

## Fourth batch: 10 TradingView indicators + optimisation of low-profit passers (`ind10d*.py`, `opt_ind.py`, `opt_ott.py`, 2026-11-20)
avg R (Nov–Jun / Jul–Nov where noted): M5 all negative (−0.06 to −0.11).
| Indicator | M15 | H1 | Random baseline (best TF) |
|---|---|---|---|
| Trend Magic (Kivanc) | −0.04 | +0.05 (+0.05/+0.06) | 81% |
| OTT (Kivanc 2/1.4) | −0.16 | **+0.32 (+0.30/+0.35), 202 tr** | **91.7%** (longs +32R / shorts +32R, corr SSL 0.38) |
| AlphaTrend (Kivanc, RSI) | +0.02 | +0.08 (+0.00/+0.21) | 81.5% |
| MavilimW (Kivanc) | **+0.18 (+0.12/+0.27), 528 tr** | −0.08 | 87.8% |
| Elder Impulse | −0.06 | +0.05 (+0.08/−0.00) | – |
| Alligator | +0.06 (+0.03/+0.12) | +0.09 (+0.27/−0.23) | 89.2% (M15) |
| T3 Tilson | −0.07 | +0.01 | – |
| Volatility Stop | −0.06 | +0.04 | 77.9% |
| Bollinger breakout | −0.12 | +0.01 | – |
| RSI 50 cross | −0.03 | +0.01 | – |
None passes ≥ 95%. PBO 0.05, DSR (119 trials) ≤ 0.15.
Optimisation (length ×0.5/1/2, SL 1.0/1.5/2.0, D1 on/off = 18 configs, select on Nov–Jun):
- Aroon H1: selected len 14 SL 1.5 +D1 → test +0.11 (default +0.08), random 97%, Cent 0.75% 441 / DD 9% (default 418 / DD 18%); PBO 0.44.
- Coral H1: selected len 10 SL 1.0 +D1 → test +0.09 (default +0.27), random 85%: optimisation hurts; PBO 0.07.
- OTT H1 (percent 0.7/1.4/2.8): selected 2.8 SL 1.0 → test −0.35 (default +0.35), random 77%: optimisation hurts; PBO 0.42.
Optimising small-edge H1 trend indicators does not raise profit above ~450 USD/year on Cent 300 (SENTINEL standard 0.75% = 1,443).

### Source check: OTT and MavilimW against the user-supplied Pine code (`src_check.py`, `ott_m15.py`)
MavilimW: our port matches the source (WMA 3/5/8/13/21/34, signal = colour change). OTT: logic matches; the source strategy is pure stop-and-reverse without SL (we had added SL 1.5 ATR); VAR starts at 0 (warm-up only).
Re-test with the source behaviour (USD per 0.01 lot, avg in 1.5-ATR units, random baseline):
| | M5 | M15 | H1 |
|---|---|---|---|
| OTT no SL (original) | +100, +0.06, 86% | **+2,110, +0.23 (+0.21/+0.28), 96.7%**, worst −151 | +1,153, +0.15, 81% |
| OTT SL 1.5 ATR | −1,373 | −1,546 | +1,887, +0.31, 89% |
| MavilimW no SL | +684, −0.04 | +1,282, +0.12, 86% | +1, +0.06 |
| MavilimW SL 1.5 ATR | −483 | +1,752, +0.18, 87% | −541 |
OTT M15 passes only without a tight SL. With a 5-ATR safety SL: 520 trades, +0.073R (5-ATR units), Nov–Jun +0.07 / Jul–Nov +0.09, random 96.2%, longs/shorts both positive, DSR (121 trials) 0.15, corr with SSL H1 0.46; Cent USD 300 risk 1% → 427 (DD 12%). Small edge, same trend family as SENTINEL.

### Lorentzian Classification re-test from the user-supplied Pine source (`lorentz.py`, numba)
Our first port had the label sign reversed (source: src[4] < src[0] → short) and exited on the opposite signal; the source holds 4 bars (strict exit). Rolling 2000-bar window, k = 8, all 3 filters and kernel as in the source.
| TF | trades/month | avg R (1.5-ATR units) | Nov–Jun / Jul–Nov | random |
|---|---|---|---|---|
| H1 | 13 | −0.03 (no SL) / −0.02 (SL 1.5) | −0.01 / −0.05 | 49–65% |
| M15 | 62 | −0.06 / −0.07 | −0.05 / −0.07 | 42–44% |
| M5 | 187 | −0.12 / −0.12 | −0.11 / −0.12 | 20–22% |
With the corrected label the indicator trades normally but loses on every TF and is worse than random direction. The flipped (old) label gives almost no trades. Dead end.

## Fifth batch: 10 TradingView indicators, KST passes (`ind10e*.py`, `kst_scale.py`, `kst_port.py`, 2026-11-20)
Defaults, SL 1.5 ATR, exit/reverse on opposite signal. M5 all negative; M15 only TRIX +0.10 (random 88%).
H1 avg R (Nov–Jun / Jul–Nov), random baseline: Gann HiLo +0.11 (+0.08/+0.15) 85% · LSMA −0.02 · Trendilo +0.12 (98 tr) 81% · Schaff TC +0.09 89% · TRIX −0.03 · Ehlers ITrend +0.06 89% · McGinley −0.00 · **KST +0.34 (+0.30/+0.42), 304 tr, random 100%, longs +49R / shorts +55R, DSR (151 trials) 0.61, Cent 0.75% → 633 / DD 9%** · Laguerre RSI −0.04 · JMA −0.03. PBO 0.008.
KST periods scaled (roc 10/15/20/30, sma 10/10/10/15, signal 9) × k: H1 ×1 +0.34 (25/mo) · H1 +D1 +0.44 (98.9%) · M15 ×4 +0.39 (99.8%, longs +11 / shorts +110: lopsided) · M15 +D1 +0.77 (99.0%) · M5 ×12 +0.22 (99.0%, DSR 0.02) · M5 +D1 +0.34 (97.7%). PBO 0.23.
Correlation of daily R: KST H1 vs SSL H1 0.54, vs SSL M15 0.29, vs MACD H1 0.56; KST M15 vs SSL M15 0.25.
Portfolios, Cent USD 300 (end / DD at 0.5 / 0.75 / 1%):
| Portfolio | /month | 0.5% | 0.75% | 1% |
|---|---|---|---|---|
| KST H1 | 25 | 497 / 6% | 633 / 9% | 799 / 11% |
| KST H1+M15 | 49 | 843 / 12% | 1,322 / 18% | 1,995 / 25% |
| SENTINEL std (SSL M15+H1) | 47 | 895 / 17% | 1,443 / 24% | 2,232 / 31% |
| SENTINEL turbo (+MACD H1,M15) | 120 | 1,854 / 32% | 3,616 / 46% | halt |
| **SENTINEL std + KST H1** | 72 | 1,407 / 17% | **2,715 / 24%** | 4,899 / 32% |
| **SENTINEL std + KST H1+M15** | 96 | **2,240 / 22%** | 4,996 / 32% | 9,945 / 42% |
KST is the first addition that raises return at the same DD (lower correlation with SSL M15 than MACD). Caveat: found after ~151 trials; formula not yet checked against the TradingView source.

## Previous-year check of passed and watch-list indicators (`prev_year.py`, `two_year.py`, 2026-11-20)
Same rules, no re-tuning; previous year Nov 2024–Oct 2025 on Dukascopy M1 bid/ask (4 pseudo-ticks/min); latest year on real ticks. avg R per trade:
| Indicator (TF) | latest-year status | latest | previous | 2-year random | 2-year longs / shorts |
|---|---|---|---|---|---|
| KST (H1) | passed 100% | +0.34 | +0.08 (prev-year random 89.6%) | **100.0%** | +103 / +27 |
| SSL HMA60 (H1) | passed 99.9% | +0.27 | +0.06 | **99.8%** | +100 / +14 |
| MACD (H1) | passed 99.5% | +0.18 | **−0.02** | 98.8% | +80 / −6 |
| Aroon (H1) | passed 98.1% | +0.12 | +0.05 | 99.3% | +80 / −14 |
| Coral (H1) | passed 97.3% | +0.18 | +0.19 | **99.7%** | +93 / +9 |
| CCI (H1) | watch 94.6% | +0.19 | +0.14 | 96.5% | +81 / −11 |
| OTT (H1) | watch 91.7% | +0.32 | +0.24 | 96.5% | +87 / +14 |
| OTT source M15 SL 5 ATR | passed 96.2% | +0.07 | +0.06 | 96.0% | +62 / −2 |
| Hull Suite (H1) | watch 89.4% | +0.12 | +0.26 | 99.6% | +108 / −11 |
| Schaff TC (H1) | watch 88.6% | +0.09 | −0.07 | 84.8% | +39 / −35 |
| Ehlers ITrend (H1) | watch 88.8% | +0.06 | +0.12 | **99.6%** | +75 / +10 |
| MavilimW (M15) | watch 87.8% | +0.18 | −0.01 | 97.1% | +112 / −22 |
| Gann HiLo (H1) | watch 85.0% | +0.11 | +0.22 | **99.5%** | +104 / +15 |
Findings: the one-year random test is noisy (KST 100% latest vs 89.6% previous; Gann HiLo 85% vs 99.3%). Both years were gold up-trends, so long trades dominate; shorts are the stricter check. Robust on both years with longs and shorts positive: KST, SSL, Coral, Gann HiLo, Ehlers ITrend (and OTT H1 at 96.5%). MACD H1 lost in the previous year (THUNDER and SENTINEL turbo caution). Schaff TC and MavilimW fail.

## Multi-timeframe map of the finalists (`multi_tf.py`, `multi_tf.csv`, 2026-11-20)
2 years (Nov 2024 – Nov 2026) on M1 bid/ask, SL 1.5×ATR14, reverse on opposite signal. avg R per trade (default params / periods scaled to H1 lookback):
- H1 is the best TF for all six: KST +0.20 (99.9%), Gann HiLo +0.15 (99.5%), SSL +0.15 (99.9%), Coral +0.18 (99.7%), ITrend +0.08 (99.8%), OTT +0.28 (97.0%).
- M5 loses for every indicator and variant (−0.10 to −0.21R). M15 default loses for all; M15/M30 scaled ≈ the H1 trades (KST: same trade count).
- H4: SSL +0.37R (98.7%, DD 14R, 7 trades/month), Coral +0.26R (96.8%); the others fail at H4.
- Weekly-R correlation: KST–SSL 0.71, SSL H4 vs H1 group 0.05–0.27, OTT vs group 0.27–0.48.
- Equal-weight combos (post-hoc, biased): KST+Coral+Gann H1 + SSL H4 = +397R, DD 42R (ratio 9.4); all five H1 = +518R, DD 80R (6.5); KST+SSL = +230R, DD 48R (4.8).
Catalogue of passed building blocks: `MQL5/Docs/passed/06_คลังกลยุทธ์ที่ผ่าน.md`.

## Cent USD 300 money simulation over 2 years (`port2y.py`, 2026-11-20)
M1 bid/ask, Nov 2024 – Nov 2026, realized-equity sizing, overlapping engines, halt at 50% DD. "Each year" restarts at USD 300.
| Portfolio | risk/trade | 2 years | previous year | latest year |
|---|---|---|---|---|
| SENTINEL standard (SSL H1 + SSL M15 HMA320 D1) | 0.75% | $1,698 DD 40% | $453 DD 40% | $1,124 DD 28% |
| SENTINEL turbo (+MACD H1, MACD M15) | 0.5% | **halted** $219 | **halted** | $1,252 DD 36% |
| **New 4 engines (KST H1 + Coral H1 + Gann HiLo H1 + SSL H4)** | 0.5% | $1,686 DD 24% | $694 DD 24% | $729 DD 20% |
| New 4 engines | **0.75%** | **$3,351 DD 35%** | $973 DD 35% | $1,033 DD 29% |
| New 4 engines | 1% | $5,992 DD 44% | $1,300 DD 44% | $1,383 DD 38% |
| New 4 + SSL M15 D1 | 0.5% | $3,162 DD 38% | $827 | $1,147 |
| SENTINEL v1.20 draft (SSL H1 + M15 + KST H1) | 0.75% | $3,384 DD 48% | $507 DD 48% | $2,003 DD 29% |
Engines alone (2-yr R): KST +123, Coral +98, Gann +112, SSL H4 +63, SSL H1 +106, SSL M15 D1 +171, MACD H1 +59 (prev yr −8), MACD M15 +51 (prev yr −38).
Findings: the new 4-engine portfolio is the only one with similar profit in both years; SENTINEL turbo (MACD) hits the 50% halt in the previous year at every risk; SENTINEL standard earns mostly in the latest year. M1 data is pessimistic vs ticks (SENTINEL standard 0.75% latest year: $1,124 on M1 vs $1,443 on ticks). Portfolio selection is post-hoc.

## XAU QUARTET v1.00 (EA, 2026-11-20)
`MQL5/Experts/XAU_QUARTET_v1.00.mq5`: KST H1 + Coral H1 + Gann HiLo H1 + SSL HMA60 H4, author defaults, SL 1.5×ATR14, reverse on opposite signal, risk 0.5/0.75/1%, DD halt 50%, magic 891000+.
`quartet_parity.py`: a literal Python port of the EA's state functions (1,500-bar rolling window) agrees 100% with the research signals on H1/H4 bars (Jan–May 2025). Not compiled in MT5 yet.

## QUARTET with a 70% DD halt (`quartet_dd70.py`, 2026-11-20)
Cent USD 300, 2 years: 1.25% → $9,718 DD 53% · **1.5% → $14,385 DD 60%** (prev year $2,031 DD 60%, latest $2,124 DD 52%, worst month −$3,902) · 2% halts at 70% in Aug 2025.
Halt 50%: 1.25% and 1.5% halt in Aug 2025. Block bootstrap of weekly R (4-week blocks, 5,000 paths): 1.5% → P(DD ≥ 50%) 79%, P(DD ≥ 70%) 22%, median DD 60%; 1% → 30% / 3%; 0.75% → 8% / 0%.

## QUARTET v1.10 lot modes (`quartet_lotmodes.py`, 2026-11-20)
Cent USD 300, 2 years, halt 70%, 0.01 cent-lot granularity: %Equity/%Balance 1.5% compounding $14,053 DD 60% (best) · same non-compounding $2,036 DD 33% · fixed $4.50 risk $2,036 · 0.01 per 3,000 USC $2,861 DD 49% (real risk up to 7.1%/trade) · 0.01 per 1,500 USC halts Apr 2026 · fixed 0.01 $394 · fixed 0.20 $2,175.
Best mode detail: 2,080 trades (85/month), win 34%, avg win +2.27R, avg loss −0.88R, PF 1.29, SL hit 44.6%, median hold 14 h (SSL H4 70 h), max losing streak 28, max DD 60% (Jun–Sep 2025, $1,802 → $723, recovered Oct 2025), 7 losing months of 25. Trade list: `MQL5/Docs/quartet/quartet_1.5pct_trades_2y.csv`.

## Batch 6: 10 more TradingView indicators as QUARTET engine candidates (`ind11.py`, `ind11.csv`, 2026-11-21)
2 years M1 bid/ask, M15/H1/H4, author/built-in defaults, SL 1.5×ATR14, reverse on opposite signal. 30 configs tested.
- M15: all fail (only Ichimoku M15 98.2% but shorts −15R and year 2 ≈ 0).
- H1 passers: **PMO 35/20/10 +0.17R 99.9% L/S +106/+9 (A)**, **TSI 25/13/13 +0.10R 99.8% L/S +71/+6 (A, year 1 only +0.02)**, MA Cross 9/18 +0.12R 99.8% (shorts −7), Awesome Osc +0.15R 98.7% (shorts −11), Chande Kroll +0.11R 98.5% (shorts −1), Ichimoku +0.31R 95.4% (9 trades/month, shorts −4). Fail: RVI, Andean (93.7%), Nadaraya-Watson, MAMA H1.
- H4 passers: **Awesome Osc +0.47R 98.4% L/S +53/+5**, **MAMA/FAMA +0.37R 98.7% L/S +41/+2 (5 trades/month)**, PMO +0.21R 96.3% L/S +37/+3, TSI 97.8% (shorts −5). Fail: Ichimoku, Andean, Chande Kroll, NW, MA Cross, RVI.
- Correlation of weekly R with the QUARTET total: PMO H1 0.72, TSI H1 0.70, MA Cross H1 0.83 (redundant); AO H4 0.20, MAMA H4 0.25, PMO H4 0.36 (diversifiers).
- Cent USD 300, halt 70%, risk scaled so max DD ≤ 44%: QUARTET alone 0.95% → $5,378 · +PMO H4 1.0% → $7,420 (each year from $300: $1,356 / $1,641) · +AO H4 0.9% → $6,685 ($1,454 / $1,379) · +MAMA H4 0.9% → $6,014 · +AO H4+MAMA H4 0.8% → $6,230 · +PMO H1 0.7% → $4,923 (worse) · +TSI H1 0.6% → $2,908 (worse).
Takeaway: new H1 engines duplicate KST/Coral/Gann; H4 engines add return at the same DD. Selection is post-hoc across 30 configs (~1.5 false passes expected at 95%).

## Faster trading search: M5 / M15 / M30 with the H4 "mothership" filter (`fast_tf.py`, `fast_tf.csv`, 2026-11-21)
10 passed engines; DF = defaults + enter only in the direction of SSL HMA60 H4; HF = periods × half of (60/TF) + filter; D = defaults M30 no filter. 2 years M1 bid/ask.
- M5: every engine and variant loses (DF −0.13 to −0.16R, 126–251 trades/month, hold ~0.7 h, SL ~$5.4; HF best Coral +0.12R but random 94%).
- M15 HF passers: **Awesome Osc 10/68 +0.29R, 17/month, hold 2.8 h, 99.7%, L/S +56/+65 (year 1 only +0.04)**, Coral 42 +0.11R 96.2% L/S +23/+31. All M15 DF fail.
- M30 DF passers: **Awesome Osc 5/34 +0.24R, 17/month, hold 5.4 h, 99.6%, L/S +44/+60 (year 1 +0.06)**, Gann 99.1% (year 1 0.00), SSL 98.5% (shorts −1). M30 D: Gann and AO 99.5% but shorts negative.
- Fast engines correlate 0.66–0.85 with each other. Fast-only portfolios fail: AO M30F + Coral M15F 1% → $821 DD 52%; four fast engines halt at 70% from 0.75%.
- Cent USD 300, halt 70%: SIX (QUARTET + PMO H4 + AO H4, 98 trades/month) 0.75% $5,376 DD 37% · 1% $10,370 DD 46% (each year from $300: $1,713 / $1,815). SIX + AO M30F (115/month) 0.75% $8,242 DD 38% · 1% $16,277 DD 48% (years $1,623 / $3,009). Adding Coral M15F lowers return per DD.

## XAU HEXA (QUARTET v1.20) and HEXA TURBO v1.00 EAs (2026-11-21)
`MQL5/Experts/XAU_QUARTET_v1.20_HEXA.mq5` (6 engines, magic 891000+, default 1%) and `XAU_HEXA_TURBO_v1.00.mq5` (+ AO M30 filtered by SSL H4, magic 892000+, default 0.75%). Built from QUARTET v1.10 (`make_hexa` script in the session scratchpad); PMO/AO state functions match research signals 100% (`hexa_parity.py`). Dashboard numbers from `hexa_levels.py`: HEXA 0.5–1.5% $2,425 / $5,376 / $10,370 / $17,658 / $26,859 (DD 26–62%, P(DD≥70%) 0/0/4/13/30%); TURBO $3,447 / $8,242 / $16,277 / $27,132 / $38,838 (DD 26–65%, 0/2/12/32/60%). Guide: `MQL5/Docs/passed/08_HEXA_และ_TURBO.md`.

## QUARTET / HEXA / TURBO on a Standard account (`std300.py`, `std_cap.py`, 2026-11-21)
Standard: 0.01 lot = $1 per $1 move. Median SL: H1 engines ~$21, H4 engines ~$42, AO M30 ~$14 → 0.01 lot risks 7% (H1) to 14% (H4) of $300.
- $300, EA default (skip if 0.01 lot risks > 5.5%): only 43 of 2,080–2,391 trades taken (QUARTET/HEXA), TURBO halts at 70% in Dec 2024. Unusable.
- $300, always 0.01 lot: 2-year numbers look huge (QUARTET $14,735, HEXA $28,536, TURBO $45,622) only because year 1 compounded before SLs grew; starting at $300 in the latest year: QUARTET $206 (halt), HEXA $90 (halt), TURBO $68 (halt).
- Latest year from other balances, risk 1% (lots floored, min 0.01 → real risk above 1% below ~$3,000): QUARTET $1,000 halts, $2,000 +459% DD 42%, $3,000 +375% DD 33%; HEXA $1,000 +1,327% DD 60%, $2,000 +614% DD 40%, $3,000 +598% DD 34%; TURBO $1,000 +2,086% DD 58%, $2,000 +1,158% DD 42%, $3,000 +879% DD 41%. Below $3,000 the 0.01-lot floor raises real risk to 2–4% per trade (higher return and ruin risk; QUARTET at $1,000 halted).
- Cent $300 latest year (reference): QUARTET $1,383, HEXA $1,815, TURBO $3,009.
Conclusion: with USD 300 use a Cent account; Standard needs about USD 3,000 for the EA's risk setting to mean what it says.

## Batch 8: scalping round M1 / M5 / M15 (`scalp8.py`, `scalp8.csv`, 2026-11-21)
10 TradingView scalping strategies (EMA 9/21 + EMA50, CM Sling Shot 38/62, Stochastic 5/3/3 pullback, daily VWAP cross, Bollinger 20/2 fade, RSI 7 fade, SuperTrend 10/3, Keltner 20/1.5 breakout, NY ORB 13:30–14:00, London ORB 07:00–08:00) × M1/M5/M15 × (no filter / SSL H1 filter) = 60 configs. Pre-registered: entries 07–20 UTC, SL 1×ATR14, TP 1.5R, time exit 48 bars, one trade at a time.
- **All 60 lose.** M1 −0.37 to −0.66R (SL ~$1.6 vs spread ~$0.56; M1 pseudo-ticks also crude), M5 −0.18 to −0.27R (SL ~$3.8), M15 best −0.09R (SL ~$7).
- Edge before spread (spread added back): only 4/60 above zero and all ≤ +0.012R; at a $0.10 all-in cost (raw-spread account) every config is still negative. These entries have no edge on gold, so a lower-cost broker would not rescue them.
- Dukascopy in-session spread: median $0.56.
Conclusion: no M1/M5/M15 scalping EA; fastest validated engine remains AO M30 + SSL H4 filter (HEXA TURBO).

## Batch 9: second scalping round, price-action / level / session ideas (`scalp9.py`, `scalp9.csv`, 2026-11-21)
Previous-day high/low breakout, Turtle Soup (PDH/PDL sweep fade), Asian range (00–07 UTC) breakout, inside-bar breakout, three-bar momentum, volatility-expansion bar, daily pivot S1/R1 rejection, $10 round-number bounce, Heikin Ashi + EMA200, Williams fractal breakout × M1/M5/M15 × N/F, same pre-registered scalping exits as batch 8.
- 59/60 lose after spread. Only Asian range breakout M15 + SSL H1 filter is positive (+0.036R, 10.7 trades/month, random 98.9%) but year 1 is negative (−0.07R) → fails.
- Edge before spread: 11/60 positive, best Asian break M15 F +0.14R / N +0.09R, three-bar M15 F +0.09R; M1 all negative even before spread (−0.15 to −0.42R).
- The Asian-range edge matches XAU ORB v6.10 (Asian range + D1 filter, held longer); scalping exits (TP 1.5R / 48 bars) waste it.
Conclusion: no scalping EA from 20 strategies over two rounds. Next useful test: ORB v6.10 over 2 years and its correlation with HEXA.

## XAU ORB v6.10 over 2 years (`orb2y.py`, 2026-11-21)
Asia 1-hour ranges 00/01/02/03 UTC, width $3–16, first M5 close outside within 5 h, D1 EMA20 trend filter, SL = opposite edge, exit 12:00 UTC (M1 bid/ask).
| Range | trades/month | avg R | previous year | latest year | random 2 yr |
|---|---|---|---|---|---|
| 00–01 (C1) | 5.8 | +0.19 | −10.6R | +37.7R | 84.7% |
| 01–02 | 4.2 | +0.21 | +12.3R | +9.0R | 99.7% (only pass) |
| 02–03 | 6.4 | +0.10 | 0.0R | +15.4R | 97.5% |
| 03–04 | 8.7 | −0.01 | −23.1R | +22.1R | 67.8% |
| all four | 25 | +0.10 | −21.5R | +84.2R | 99.6% |
The earlier one-year ORB numbers came from the latest year; over 2 years ORB fails (previous year negative). Cent $300 ORB alone: 4 ranges 1% $470 DD 48%. Weekly correlation with HEXA 0.22, yet adding ORB lowers HEXA at equal DD: HEXA 0.95% $9,188 DD 45% → +ORB 00–01 0.85% $8,130 · +4 ranges 0.60% $4,201. Do not add ORB to HEXA.
