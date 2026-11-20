import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute, ema
from ind10 import atr
from pbo import pbo
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002')
def wma(x, n):
    w = np.arange(1, n + 1, dtype=float); y = np.convolve(x, w[::-1], 'full')[n - 1:len(x)] / w.sum(); return np.r_[np.full(n - 1, np.nan), y]
def hma(x, n): return wma(2 * wma(x, n // 2) - wma(x, n), int(round(np.sqrt(n))))
d = bars(tt, tb, ta, 86400).reset_index(drop=True); dts = d.ts.values
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
out = {}
for tf, lens, sls, emas in ((900, (160, 240, 320), (1.0, 1.5, 2.0), (10, 20, 50)), (3600, (40, 60, 80), (1.0, 1.5, 2.0), (None,))):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); H, L, C = m.h.values, m.l.values, m.c.values; TS = m.ts.values + tf; A = atr(H, L, C, 14)
    j = np.searchsorted(dts + 86400, TS, side='right') - 1
    rows = []; cols = []
    for n in lens:
        eh, el = hma(H, n), hma(L, n); st = np.zeros(len(C)); v = 0; ok = ~np.isnan(eh)
        for i in range(len(C)):
            if ok[i]: v = 1 if C[i] > eh[i] else (-1 if C[i] < el[i] else v)
            st[i] = v
        fl = np.flatnonzero((st != np.r_[0, st[:-1]]) & (st != 0)); fl = fl[TS[fl] >= START]
        for e in emas:
            if e: tr = np.where(d.c.values > ema(d.c.values, e), 1, -1); TR = tr[np.clip(j, 0, None)]
            for k in sls:
                sig = []
                for a, b in zip(fl, np.r_[fl[1:], len(m) - 1]):
                    dr = int(st[a])
                    if e and dr != TR[a]: continue
                    i = int(np.searchsorted(tt, TS[a]))
                    if i >= len(tt) - 2: continue
                    sig.append(dict(setup='s', i=i, dir=dr, sl=(ta[i] if dr > 0 else tb[i]) - dr * k * A[a], texit=TS[b], ts=TS[a], S=k * A[a]))
                x = execute(tt, tb, ta, pd.DataFrame(sig), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; out[(tf, n, e, k)] = x; cols.append(daily(x))
                rows.append(dict(HMA=n, D1EMA=e, SL=k, n=len(x), avg=x.R.mean(), train_sum=p.R.sum(), train=p.R.mean(), test=q.R.mean(), test_sum=q.R.sum()))
    r = pd.DataFrame(rows).sort_values('train_sum', ascending=False); print(f'=== M{tf//60} (sorted by Nov-Jun total R) ==='); print(r.round(3).to_string(index=False))
    print('PBO:', round(pbo(np.column_stack(cols))['pbo'], 3))
pickle.dump(out, open('ssl_opt2.pkl', 'wb'))
