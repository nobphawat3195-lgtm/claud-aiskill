# XAU_300_Research_v1 — pre-registration (written and committed before any run of these configs)

Date: 2026-11-08 · Logic: Asia ORB (YY19 family) re-implemented independently · Symbol: XAUUSD · Deposit $300 USD · Leverage 1:500

## Why this logic
Strongest reproducible evidence in the project log: Asia 00:00–01:00 UTC opening-range breakout on gold
(YY19 family). On the current Dukascopy M1 set the Python reference gives 159 trades / +$893 / PF 1.75 with the
OLD sizing (2.5% risk, force 0.01 lot up to 6% loss). Every other family tested (≈80 EAs, grid/martingale, SMC,
Lorentzian, S/D, momentum, etc.) failed. The same ORB failed on 13 non-gold symbols (edge is gold-specific).

## Configs (max 4 for this logic)
| id | purpose | sizing | daily loss | peak-equity DD stop |
|---|---|---|---|---|
| E0 | entry edge only | fixed 0.01 lot, no skips by size, no stops | off | off |
| P1 safe | preset | 1% equity risk, skip if < min lot | 3% | 20% |
| P2 balanced | preset | 2% equity risk, skip if < min lot | 3% | 20% |
| P3 aggressive (research only, NOT a live recommendation) | preset | 5% equity risk, skip if < min lot | 3% | 20% |

Shared entry rules (all four): range 00:00–01:00 server (GMT+0), M5 close breakout until 20:00, 1 signal per
direction per day, SL = opposite side of range, TP 2R, BE at 1R, time exit 21:00, no Friday, kill filter median
D1 range% of previous 20 days < 1.5, spread ≤ 10% of SL distance, max 1 position. Spread $0.28 round trip,
no commission, no swap (flat before rollover).

## Period and splits
Benchmark: 2025-10-31 → 2026-10-31 (Oct 2025 used only as warm-up for the kill filter).
Halves: H1 = Nov 2025–Apr 2026, H2 = May–Oct 2026. Sep–Oct 2026 is NOT a pristine holdout: YY19 results for that
window were already seen in earlier sessions. No untouched holdout exists for this logic.

## Decision rules (fixed now)
1. "Best preset" = highest net profit among P1–P3 whose max equity DD ≤ 20% and that did not hit the DD halt.
   If none qualifies, report the one with the highest net profit and mark it as failing the risk limit.
2. Entry edge is judged on E0 only (R units): t(R) ≥ 2.0, PF ≥ 1.5, both halves positive. Raising risk is never
   counted as an improvement of the logic.
3. Project acceptance (Doc §2) is reported as pass/fail per preset: PF ≥ 1.5, equity DD ≤ 15%, ≥ 100 trades,
   t(R) ≥ 2, no negative half, profit not from one trade.
4. Python numbers are relative estimates. Only the user's MT5 real-tick run (Model=4) is evidence for the EA.
