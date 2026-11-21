# Which timeframe suits each finalist? 2 years (Nov 2024 - Nov 2026) on Dukascopy M1 bid/ask (4 pseudo-ticks/min), same rules
# (entry next tick after bar close, SL 1.5 x ATR14, exit/reverse on opposite signal). Two variants per TF:
#   default = author parameters on that TF;  scaled = periods x (60 / TF minutes) so the lookback in hours equals the H1 version.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, ssl_hybrid
from ind10b import sar_trades
from ind10c import coral
from ind10d import ott
from ind10e import itrend, kst, gann_hilo
from ind10 import sma
def kst_k(o, h, l, c, k=1):
    roc = lambda n: (c / np.r_[np.full(n, c[0]), c[:-n]] - 1) * 100
    v = sma(roc(10 * k), 10 * k) + 2 * sma(roc(15 * k), 10 * k) + 3 * sma(roc(20 * k), 10 * k) + 4 * sma(roc(30 * k), 15 * k)
    return sar_trades(np.nan_to_num(np.sign(v - sma(v, 9 * k))))
IND = {  # name: (default fn, scaled fn(k) or None)
    'KST': (lambda O, H, L, C: kst(O, H, L, C), lambda k: (lambda O, H, L, C: kst_k(O, H, L, C, k))),
    'SSL': (lambda O, H, L, C: ssl_hybrid(H, L, C), lambda k: (lambda O, H, L, C: ssl_hybrid(H, L, C, 60 * k))),
    'Coral': (lambda O, H, L, C: coral(O, H, L, C), lambda k: (lambda O, H, L, C: coral(O, H, L, C, sm=21 * k))),
    'GannHiLo': (lambda O, H, L, C: gann_hilo(O, H, L, C), lambda k: (lambda O, H, L, C: gann_hilo(O, H, L, C, 13 * k, 21 * k))),
    'ITrend': (lambda O, H, L, C: itrend(O, H, L, C), lambda k: (lambda O, H, L, C: itrend(O, H, L, C, a=0.07 / k))),
    'OTT': (lambda O, H, L, C: ott(O, H, L, C), None)}
TFS = [(300, 12), (900, 4), (1800, 2), (3600, 1), (14400, None)]
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
tt, tb, ta = load_m1('20240801', '20261114'); rng = np.random.default_rng(0)
def evlist(ev):
    if isinstance(ev, list): return ev
    idx = np.flatnonzero(ev); return [(a, int(ev[a]), b) for a, b in zip(idx, np.r_[idx[1:], len(ev) - 1])]
def run(nm, fn, m, A, tf):
    O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; TS = m.ts.values + tf; rows = []
    for a, d, b in evlist(fn(O, H, L, C)):
        if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or d == 0: continue
        i = int(np.searchsorted(tt, TS[a]))
        if i >= len(tt) - 2: continue
        rows.append(dict(setup=nm, i=i, dir=int(d), sl=(ta[i] if d > 0 else tb[i]) - d * 1.5 * A[a], texit=min(TS[min(b, len(m) - 1)], END), ts=TS[a]))
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']).reset_index(drop=True); x['R'] = x['r0.0']
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((4000, len(x))) < .5, x.R.values, Rf).sum(1)
    p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    return x, dict(ind=nm, n=len(x), per_month=len(x) / 24.4, avgR=x.R.mean(), sumR=x.R.sum(), y1=p.R.mean(), y2=q.R.mean(), rnd=(drw < x.R.sum()).mean(),
                   longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum(), win=(x.R > 0).mean())
res, trades = [], {}
for tf, k in TFS:
    m = bars(tt, tb, ta, tf).reset_index(drop=True); A = atr(m.h.values, m.l.values, m.c.values, 14)
    for nm, (fd, fs) in IND.items():
        vars_ = [('default', fd)] + ([('scaled', fs(k))] if fs and k and k > 1 else [])
        for vn, fn in vars_:
            x, r = run(nm, fn, m, A, tf); r.update(tf=f'M{tf//60}' if tf < 3600 else f'H{tf//3600}', var=vn); res.append(r); trades[(nm, tf, vn)] = x
            print(f"{r['ind']:9s} {r['tf']:4s} {vn:7s} n={r['n']:5d} ({r['per_month']:5.1f}/mo) avg {r['avgR']:+.3f}R sum {r['sumR']:+7.1f}R | y1 {r['y1']:+.3f} y2 {r['y2']:+.3f} | random {r['rnd']:6.1%} | L {r['longs']:+6.1f} S {r['shorts']:+6.1f}", flush=True)
pd.DataFrame(res).to_csv('multi_tf.csv', index=False); pickle.dump(trades, open('multi_tf.pkl', 'wb'))
