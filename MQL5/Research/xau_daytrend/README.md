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
