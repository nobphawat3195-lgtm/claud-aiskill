# XAU300_ORB_LogicLab_v2 — pre-registration (committed before any code, simulation or MT5 result for these configs)

Date: 2026-11-08 · Research only, never live. Symbol XAUUSD_DUKA (UTC), deposit $300, leverage 1:500, MT5 real ticks.

## Baseline (known, user-reported MT5 real ticks, random delay, 3 runs)
`XAU300_ORB_CappedRecovery_Research` preset `R0_autolot5` (recovery OFF, risk 5%):
net +$581.52 / +$538.42 / +$445.88 (median **+$538.42**), equity DD 22.22% / 22.84% / 24.33%,
representative run 79 trades (34 W / 45 L), commission and swap 0.
The whole benchmark year 2025-10-31 → 2026-10-31 has already been seen (R0 and earlier runs): **no clean out-of-sample
period exists**. Anything below is in-sample research on a seen year.

## EA
`MQL5/Experts/XAU300_ORB_LogicLab_v2.mq5`, derived from `XAU300_ORB_CappedRecovery_Research.mq5` (R0 path), magic 300336.
Unchanged from the baseline: guards (daily hard stop 3%, DD stop 30%, flatten retries, persisted state), MaxLot 0.10,
risk 5% with recovery OFF, rolling filter 0.18%, half filter 0.5, SL at range midpoint, RR 2, hold 90 min, session 00:00 UTC,
15-min range, 15-min entry window, one shot per day, spread gate 0, tester M1 equity CSV, AllowRealAccount=false.
New inputs: `InpEntryLogic` (0/1/2) and `InpBreakCloseLocationMin` (0.75).

## Entry logic (only difference between configs)
- **0 direct (control):** exactly the baseline: first closed M1 bar opened in [range end, range end + 15 min) closing outside
  the range ends the day; half filter; market entry.
- **1 close location:** as 0, plus the breakout bar (M1 bar 1, closed) must close in the outer 25% of its own high-low on the
  breakout side: long (close − low)/(high − low) ≥ 0.75, short (high − close)/(high − low) ≥ 0.75; zero-range bar rejected.
  Rejection still ends the day (one shot). No other change.
- **2 retest (independent of mode 1):** the first closed breakout bar that passes the half filter arms the direction and its bar
  time and ends the day for any NEW breakout (one shot consumed). Later CLOSED bars with time > armed time and
  < range end + 15 min are checked: long confirms if low ≤ OR high AND close > OR high; short if high ≥ OR low AND close < OR low.
  A long bar closing ≤ OR high (short: ≥ OR low) invalidates immediately (no waiting for a re-break). No confirmation inside the
  window → expire. On confirmation the same market TryEnter as mode 0 (current price, midpoint SL, 2R). No limit orders, no
  same-bar peeking, never bar 0 OHLC. Pending state is NOT persisted: a restart cancels it (dayDone stays true, so no duplicate
  trade); NewDay clears it.

## Configs (exactly 3; all other inputs copied from R0_autolot5)
| id | InpEntryLogic | InpBreakCloseLocationMin |
|---|---|---|
| Q0_direct_control | 0 | 0.75 (inactive) |
| Q1_close75 | 1 | 0.75 |
| Q2_retest | 2 | 0.75 (inactive) |

## Protocol and decision rule (user's MT5 runs)
1. Compile; Q0 must reproduce R0 deterministically (2 runs, no random delay) before Q1/Q2 are judged.
2. Q1 and Q2: 3 random-delay runs each over the full year, compared with the 3 known R0 runs. Seeds are not exposed by MT5,
   so runs are NOT paired.
3. A config is called "better on this seen year" only if its median net > +$538.42 AND every one of its 3 runs has equity
   DD ≤ 35%. Otherwise it is not better. Neither outcome is evidence for future performance.
4. Costs: real variable bid/ask from the tick data, commission/swap as the tester applies them (0 in the baseline runs).
5. No simulation, no extra parameters or variants for this logic set.

## Sources
- Rule base: anas1412/orb-mt5 @ 0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9 (MIT).
- Retest / candle-close ideas are generic; seen in phatnomenal/blackXAU_AUTOMATED-BOT-TRADE and
  bsAmirHeydar/breakout-micro-following (no root LICENSE found): ideas only, implemented independently, no code copied,
  README profit claims not used as evidence.
