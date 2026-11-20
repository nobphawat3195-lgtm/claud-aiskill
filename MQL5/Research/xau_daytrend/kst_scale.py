import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute, ema
from ind10 import atr, sma
from ind10b import sar_trades
from pbo import pbo, deflated_sharpe
from sentinel_bt_run import run
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); rng = np.random.default_rng(0)
d = bars(tt, tb, ta, 86400).reset_index(drop=True); dts = d.ts.values; dtr = np.where(d.c.values > ema(d.c.values, 20), 1, -1)
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
def kst_k(c, k):
    roc = lambda n: (c / np.r_[np.full(n, c[0]), c[:-n]] - 1) * 100
    v = sma(roc(10 * k), 10 * k) + 2 * sma(roc(15 * k), 10 * k) + 3 * sma(roc(20 * k), 10 * k) + 4 * sma(roc(30 * k), 15 * k)
    return sar_trades(np.nan_to_num(np.sign(v - sma(v, 9 * k))))
res = {}; rows = []
for tf, k in ((3600, 1), (900, 4), (300, 12)):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); C = m.c.values; A = atr(m.h.values, m.l.values, C, 14); TS = m.ts.values + tf
    j = np.searchsorted(dts + 86400, TS, side='right') - 1; TR = np.where(j >= 0, dtr[np.clip(j, 0, None)], 0); ev = kst_k(C, k)
    for filt in (False, True):
        sig = []
        for a, dr, b in ev:
            if TS[a] < START or np.isnan(A[a]) or dr == 0 or (filt and dr != TR[a]): continue
            i = int(np.searchsorted(tt, TS[a]))
            if i >= len(tt) - 2: continue
            sig.append(dict(setup='kst', i=i, dir=int(dr), sl=(ta[i] if dr > 0 else tb[i]) - dr * 1.5 * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], S=1.5 * A[a]))
        x = execute(tt, tb, ta, pd.DataFrame(sig), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
        mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
        Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((10000, len(x))) < .5, x.R.values, Rf).sum(1)
        p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; res[(tf, filt)] = x
        eq, mdd = run({'X': x}, .0075)[:2]
        rows.append(dict(cfg=f'KST M{tf//60} x{k}' + (' +D1' if filt else ''), n=len(x), per_mo=round(len(x) / 12.4), avg=x.R.mean(), train=p.R.mean(), test=q.R.mean(),
                         random=(drw < x.R.sum()).mean(), longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum(), DSR=deflated_sharpe(daily(x), 157)['dsr'], usd075=eq, DD=mdd))
r = pd.DataFrame(rows); pd.set_option('display.width', 220); print(r.round(3).to_string(index=False))
print('PBO (6):', round(pbo(np.column_stack([daily(res[k]) for k in res]))['pbo'], 3))
pickle.dump(res, open('kst_scale.pkl', 'wb'))
