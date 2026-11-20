# "SSL Hybrid Strategy" (Pine v5, based on Mihkel00 SSL Hybrid) ported vs our simple SSL1 EA. H1, latest year, real ticks.
# Entry (both): SSL1 flip (close > sslDown; HMA60 of high/low), first tick after the bar close. Reverse on the opposite flip.
# Strategy exits: SL 1.8 ATR(14, RMA) from the bar close, 5 parts 20/30/30/10/10% at TP 1.8/2.2/2.6/4/8 ATR (limit), after TP1 SL -> entry.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars
from ind10 import hma, atr, flips
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); m = bars(tt, tb, ta, 3600).reset_index(drop=True)
H, L, C = m.h.values, m.l.values, m.c.values; TS = m.ts.values + 3600; A = atr(H, L, C, 14)
eh, el = hma(H, 60), hma(L, 60); s = np.zeros(len(C)); v = 0
for i in range(len(C)):
    if not np.isnan(eh[i]): v = 1 if C[i] > eh[i] else (-1 if C[i] < el[i] else v)
    s[i] = v
ev = flips(s); idx = [i for i in np.flatnonzero(ev) if TS[i] >= START]
FR = np.array([.2, .3, .3, .1, .1]); TPM = np.array([1.8, 2.2, 2.6, 4.0, 8.0])
def first(mask): k = np.flatnonzero(mask); return k[0] if len(k) else None
def trade(i, j1, d, slk, parts, be):
    e = ta[i] if d > 0 else tb[i]; sl = C_sig - d * slk * a_sig; risk = d * (e - sl)
    if risk <= 0 or j1 <= i + 1: return None
    px = (tb[i + 1:j1] if d > 0 else ta[i + 1:j1]); adv = d * (px - e)
    ks = first(adv <= -risk)
    if not parts:                                                     # simple: SL or exit at the next flip
        return (adv[ks] if ks is not None else adv[-1]) / risk, risk
    lv = d * (C_sig + d * TPM * a_sig - e)                            # TP distances from the actual entry
    kt = [first(adv >= x) for x in lv]
    k1 = kt[0]
    if ks is not None and (k1 is None or ks < k1): return adv[ks] / risk, risk
    if k1 is None: return adv[-1] / risk, risk
    kb = first(adv[k1 + 1:] <= 0) if be else first(adv[k1 + 1:] <= -risk)
    kb = None if kb is None else kb + k1 + 1
    R = 0.0
    for f, x, k in zip(FR, lv, kt):
        if k is not None and (kb is None or k < kb): R += f * x
        elif kb is not None: R += f * adv[kb]
        else: R += f * adv[-1]
    return R / risk, risk
res = {}
for name, slk, parts, be in (('A ours: SL 1.5 ATR, exit on flip', 1.5, False, False), ('B strategy: SL 1.8, 5 TPs, BE after TP1', 1.8, True, True),
                             ('C strategy exits with SL 1.5', 1.5, True, True)):
    rows = []
    for a, b in zip(idx, idx[1:] + [len(m) - 1]):
        i = int(np.searchsorted(tt, TS[a])); j1 = int(np.searchsorted(tt, TS[b]))
        if i >= len(tt) - 2: continue
        C_sig, a_sig = C[a], A[a]; d = int(ev[a])
        r = trade(i, j1, d, slk, parts, be)
        if r: rows.append(dict(ts=TS[a], dir=d, R=r[0], S=r[1]))
    x = pd.DataFrame(rows); res[name] = x
    p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    eq = pk = 300.; mdd = 0; mon = {}
    for r in x.itertuples():
        pnl = eq * .02 * r.R; eq += pnl; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); k = pd.Timestamp(r.ts, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + pnl
    pf = x.R[x.R > 0].sum() / -x.R[x.R < 0].sum()
    print(f'{name}: n={len(x)} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+.1f}R PF {pf:.2f} | Nov-Jun {p.R.mean():+.3f} Jul-Nov {q.R.mean():+.3f} | SLmed {x.S.median():.1f} | Cent USD300 risk2% -> {eq:,.0f} DD {mdd:.0%} losing months {sum(v<0 for v in mon.values())}/13')
    print('   ' + ' '.join(f'{k}:{v:+.0f}' for k, v in sorted(mon.items())))
pd.to_pickle(res, 'ssl_strat.pkl')
