import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import atr
from pbo import deflated_sharpe
from sentinel_bt_run import run
_s = open('src_check.py').read(); exec(_s[_s.index('def ott_src'):_s.index('for tf in (300, 900, 3600):')])
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); rng = np.random.default_rng(1)
o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
tf = 900; m = bars(tt, tb, ta, tf).reset_index(drop=True); C = m.c.values; A = atr(m.h.values, m.l.values, C, 14); TS = m.ts.values + tf
ev = ott_src(C); res = {}
for slk in (50.0, 5.0, 3.0):
    rows = []
    for a, d, b in ev:
        if TS[a] < START or np.isnan(A[a]): continue
        i = int(np.searchsorted(tt, TS[a]))
        if i >= len(tt) - 2: continue
        rows.append(dict(setup='ott', i=i, dir=d, sl=(ta[i] if d > 0 else tb[i]) - d * slk * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], a=A[a]))
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0'])
    unit = min(slk, 5.0)                                                     # sizing unit: SL distance (5 ATR notional for no-SL)
    x['R'] = x['r0.0'] * slk / unit; x['S'] = unit * x.a
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values * slk / unit; drw = np.where(rng.random((10000, len(x))) < .5, x.R.values, Rf).sum(1)
    p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; res[slk] = x
    money = [run({'X': x}, fr)[:2] for fr in (.005, .01)]
    print(f'OTT M15 SL {"none" if slk == 50 else str(slk)+" ATR":8s} n={len(x)} avg {x.R.mean():+.3f}R({unit}ATR) Nov-Jun {p.R.mean():+.3f} Jul-Nov {q.R.mean():+.3f} | random {(drw<x.R.sum()).mean():.1%} | longs {x.R[x.dir>0].sum():+.1f} shorts {x.R[x.dir<0].sum():+.1f} | worst {x.R.min():+.2f}R | DSR(121) {deflated_sharpe(daily(x),121)["dsr"]:.2f} | corr SSL-H1 {np.corrcoef(daily(x), daily(o2[(3600,60,None,1.5)]))[0,1]:.2f} | Cent 0.5% ${money[0][0]:,.0f} DD {money[0][1]:.0%} | 1% ${money[1][0]:,.0f} DD {money[1][1]:.0%}', flush=True)
pickle.dump(res, open('ott_m15.pkl', 'wb'))
