import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute, ema
from ind10 import atr
from pbo import pbo
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); rng = np.random.default_rng(0)
d = bars(tt, tb, ta, 86400).reset_index(drop=True); dts = d.ts.values; dtr = np.where(d.c.values > ema(d.c.values, 20), 1, -1)
res = {}; rows = []
for tf, k in ((3600, 1), (900, 4), (300, 12)):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); C = m.c.values; TS = m.ts.values + tf; A = atr(m.h.values, m.l.values, C, 14)
    j = np.searchsorted(dts + 86400, TS, side='right') - 1; TR = np.where(j >= 0, dtr[np.clip(j, 0, None)], 0)
    mc = ema(C, 12 * k) - ema(C, 26 * k); st = np.sign(mc - ema(mc, 9 * k))
    ch = np.flatnonzero((st != np.r_[0, st[:-1]]) & (st != 0)); ch = ch[TS[ch] >= START]
    for filt in (False, True):
        sig = []
        for a, b in zip(ch, np.r_[ch[1:], len(m) - 1]):
            dr = int(st[a])
            if filt and dr != TR[a]: continue
            i = int(np.searchsorted(tt, TS[a]))
            if i >= len(tt) - 2: continue
            sig.append(dict(setup='macd', i=i, dir=dr, sl=(ta[i] if dr > 0 else tb[i]) - dr * 1.5 * A[a], texit=TS[b], ts=TS[a], S=1.5 * A[a]))
        x = execute(tt, tb, ta, pd.DataFrame(sig), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
        mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f["sl"] = 2 * np.asarray(mid) - x.sl.values
        Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; dr_ = np.where(rng.random((5000, len(x))) < .5, x.R.values, Rf).sum(1)
        p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; res[(tf, filt)] = x
        rows.append(dict(cfg=f'M{tf//60} MACD {12*k}/{26*k}/{9*k}' + (' +D1' if filt else ''), n=len(x), per_mo=round(len(x) / 12.4), avg=x.R.mean(), train=p.R.mean(), test=q.R.mean(), beats=(dr_ < x.R.sum()).mean(), SL=x.S.median()))
r = pd.DataFrame(rows); pd.set_option('display.width', 200); print(r.round(3).to_string(index=False))
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
print('PBO (6):', round(pbo(np.column_stack([daily(res[k]) for k in res]))['pbo'], 3))
pickle.dump(res, open('macd_tf.pkl', 'wb'))
