import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars
from sr_sim import run
exec(open('sr_test.py').read().split('x = rep(')[0].split('from sr_sim import run')[1])
# spread in window
w = [(np.searchsorted(tt, d + 19*3600), np.searchsorted(tt, d + 20*3600 + 1800)) for d in days]
sp = np.concatenate([ta[a:b] - tb[a:b] for a, b in w]); print(f'Dukascopy spread 19:00-20:30 UTC: median {np.median(sp):.3f} mean {sp.mean():.3f} p90 {np.percentile(sp,90):.3f}')
# synthetic VT-like spread 0.30: ask = bid + 0.30
ta30 = tb + 0.30
rep(run(tt, tb, ta30, days), 'base, spread fixed 0.30')
m = bars(tt, tb, ta, 60).reset_index(drop=True); H, L, C = m.h.values, m.l.values, m.c.values
pc = np.r_[C[0], C[:-1]]; TR = np.maximum(H - L, np.maximum(abs(H - pc), abs(L - pc))); te = m.ts.values + 60
def atr(n): return pd.Series(TR).ewm(alpha=1/n, adjust=False).mean().values
for f, s in ((5, 20), (14, 50), (14, 100), (10, 60)):
    r = atr(f) / atr(s)
    ok = lambda t, r=r: r[max(0, np.searchsorted(te, t, side='right') - 1)] < 0.95
    rep(run(tt, tb, ta, days, atrok=ok), f'ATR({f})/ATR({s}) < 0.95')
    rep(run(tt, tb, ta30, days, atrok=ok), f'ATR({f})/ATR({s}) < 0.95, spread 0.30')
