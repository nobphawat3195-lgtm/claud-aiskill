# XAU300_ORB_Research — pre-registration (committed before any run of these configs)

Date: 2026-11-08 · Logic: Asia 15-minute ORB, public spec anas1412/orb-mt5 @ 0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9
(MIT, strategies/asia-gold.toml + mql5/ORB.mq5 behaviour), re-implemented standalone. Deposit $300 USD, 1:500.
This is a second, separate logic. XAU_300_Research_v1 results stay as recorded (research-only, failed).

## Entry rules (identical in all configs)
- Session 00:00 UTC (server = UTC + InpServerOffsetMinutes, 0 for XAUUSD_DUKA), range = M1 bars 00:00–00:14.
- Break = first CLOSED M1 bar whose open time is in [00:15, 00:30) and closes above range high / below range low.
- Half-of-range filter: cp = (last range bar close − low)/(high − low); longs need cp ≥ 0.5, shorts need 1 − cp ≥ 0.5.
- Rolling filter: median of 100·(high − low)/last close over the previous 20 complete weekday sessions (strictly before
  today) must be ≥ 0.18%. Fewer than 20 complete sessions available → no trade (strict).
- Mon–Thu only. Max 1 trade per day. The first break decides the day: if it is rejected (filter, spread, daily guard,
  DD halt, or min lot above budget) the day is over (upstream retries on later bars; this EA does not).
- Market entry at next bar open; SL = range midpoint; TP = fill ± 2R (R = |fill − SL|); at +0.5R move SL to −0.5R
  (tighten only); close after 90 minutes held.
Costs: spread $0.28 round trip on the ask side, no commission, no swap (trade closes ≤ 02:00 UTC).

## Configs (max 4 for this logic)
| id | sizing | daily guard | DD stop |
|---|---|---|---|
| E0 | fixed 0.01 lot, every signal, no guards (entry edge only) | off | off |
| P1 safe | 1% equity, skip if < min lot | 3% | 20% |
| P2 balanced | 2% equity, skip if < min lot | 3% | 20% |
| P5 aggressive (research only, high risk) | 5% equity, skip if < min lot | 3% | 20% |
Daily guard = hard stop: when equity ≤ day-start balance × (1 − 3%) the EA flattens (retrying every tick until flat)
and blocks entries until the next server day; state persists across restarts.
Note P5: a full stop-out (−5%) is larger than the 3% daily stop, so P5 losers are normally cut by the daily stop near
−3% (more if price gaps through the threshold: the threshold is a trigger, not a guaranteed cap). P1/P2 stop-outs
(−1%/−2%) never reach it. This is part of P5's sizing behaviour, not an entry change.

## Period
2025-10-31 → 2026-10-31 (Dukascopy M1, Oct 2025 = warm-up for the 20-session filter). Halves: Nov–Apr / May–Oct.
No pristine holdout: the upstream author selected this configuration on 2026 data (their page reports 2026 trades),
so 2026 is in-sample for the upstream choice. Only Nov–Dec 2025 lies outside the upstream "2026-01-01 → today" window.

## Decision rules (fixed now)
1. Best preset = highest net profit among P1/P2/P5 with max equity DD ≤ 20% and no DD halt.
2. Entry edge judged on E0 only: t(R) ≥ 2, PF ≥ 1.5, both halves positive, Nov–Dec 2025 reported separately.
3. Doc §2 acceptance reported per preset. Raising risk is never counted as improving the logic.
4. Python results are relative estimates on Dukascopy M1; only the user's MT5 real-tick runs count as MT5 evidence.
