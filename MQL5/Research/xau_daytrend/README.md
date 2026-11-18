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
