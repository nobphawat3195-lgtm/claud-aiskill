# Watchlist + passed indicators on the PREVIOUS year (Nov 2024 - Oct 2025), Dukascopy M1 bid/ask candles (4 pseudo-ticks/min).
# Same rules as the latest-year tests (author defaults, SL k x ATR14, exit/reverse on opposite signal). No re-tuning.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, ssl_hybrid
from ind10b import macd
from ind10c import aroon, coral, cci, hull_suite
from ind10d import ott, mavilimw
from ind10e import stc, itrend, kst, gann_hilo
_s = open('src_check.py').read(); exec(_s[_s.index('def ott_src'):_s.index('for tf in (300, 900, 3600):')])
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2025-11-01').timestamp(); SPLIT = pd.Timestamp('2025-05-01').timestamp()
tt, tb, ta = load_m1('20240901', '20251101'); rng = np.random.default_rng(0)
def evlist(ev):
    if isinstance(ev, list): return ev
    idx = np.flatnonzero(ev); return [(a, int(ev[a]), b) for a, b in zip(idx, np.r_[idx[1:], len(ev) - 1])]
TESTS = [  # name, tf, fn(O,H,L,C), SL k, status in latest year
    ('KST', 3600, lambda O, H, L, C: kst(O, H, L, C), 1.5, 'passed 100%'),
    ('SSL (HMA60)', 3600, lambda O, H, L, C: ssl_hybrid(H, L, C), 1.5, 'passed 99.9%'),
    ('MACD', 3600, lambda O, H, L, C: macd(O, H, L, C), 1.5, 'passed 99.5%'),
    ('Aroon', 3600, lambda O, H, L, C: aroon(O, H, L, C), 1.5, 'passed 98.1%'),
    ('Coral', 3600, lambda O, H, L, C: coral(O, H, L, C), 1.5, 'passed 97.3%'),
    ('CCI', 3600, lambda O, H, L, C: cci(O, H, L, C), 1.5, 'watch 94.6%'),
    ('OTT', 3600, lambda O, H, L, C: ott(O, H, L, C), 1.5, 'watch 91.7%'),
    ('OTT src M15 SL5', 900, lambda O, H, L, C: ott_src(C), 5.0, 'passed 96.2%'),
    ('Hull Suite', 3600, lambda O, H, L, C: hull_suite(O, H, L, C), 1.5, 'watch 89.4%'),
    ('Schaff TC', 3600, lambda O, H, L, C: stc(O, H, L, C), 1.5, 'watch 88.6%'),
    ('Ehlers ITrend', 3600, lambda O, H, L, C: itrend(O, H, L, C), 1.5, 'watch 88.8%'),
    ('MavilimW', 900, lambda O, H, L, C: mavilimw(O, H, L, C), 1.5, 'watch 87.8%'),
    ('Gann HiLo', 3600, lambda O, H, L, C: gann_hilo(O, H, L, C), 1.5, 'watch 85.0%')]
cache = {}; out = {}
for nm, tf, fn, k, st in TESTS:
    if tf not in cache:
        m = bars(tt, tb, ta, tf).reset_index(drop=True); cache[tf] = (m, atr(m.h.values, m.l.values, m.c.values, 14))
    m, A = cache[tf]; O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; TS = m.ts.values + tf
    rows = []
    for a, d, b in evlist(fn(O, H, L, C)):
        if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or d == 0: continue
        i = int(np.searchsorted(tt, TS[a]))
        if i >= len(tt) - 2: continue
        rows.append(dict(setup=nm, i=i, dir=int(d), sl=(ta[i] if d > 0 else tb[i]) - d * k * A[a], texit=min(TS[min(b, len(m) - 1)], END + 5 * 86400), ts=TS[a]))
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((10000, len(x))) < .5, x.R.values, Rf).sum(1)
    p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; out[nm] = x
    print(f'{nm:16s} M{tf//60:<3} [{st:13s}] prev year: n={len(x):4d} avg {x.R.mean():+.3f}R sum {x.R.sum():+6.1f}R | Nov-Apr {p.R.mean():+.3f} May-Oct {q.R.mean():+.3f} | random {(drw<x.R.sum()).mean():5.1%} | longs {x.R[x.dir>0].sum():+6.1f} shorts {x.R[x.dir<0].sum():+6.1f}', flush=True)
pickle.dump(out, open('prev_year.pkl', 'wb'))
