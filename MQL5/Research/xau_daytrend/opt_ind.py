# Pre-registered optimisation for passed H1 indicators: length x{0.5,1,2} x SL {1.0,1.5,2.0} ATR x D1 filter {off,on} = 18 configs.
# Select on Nov-Jun (sum R), report Jul-Nov, PBO over the 18, random baseline + Cent USD300 for the selected one.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute, ema
from ind10 import atr
from pbo import pbo
from sentinel_bt_run import run
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
def optimise(name, fn_of_len, base_len, tt, tb, ta, tf=3600):
    rng = np.random.default_rng(0)
    d = bars(tt, tb, ta, 86400).reset_index(drop=True); dtr = np.where(d.c.values > ema(d.c.values, 20), 1, -1)
    m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values
    A = atr(H, L, C, 14); TS = m.ts.values + tf; j = np.searchsorted(d.ts.values + 86400, TS, side='right') - 1; TR = np.where(j >= 0, dtr[np.clip(j, 0, None)], 0)
    res = {}; rows = []
    for mul in (0.5, 1, 2):
        n = max(2, int(round(base_len * mul))); ev = fn_of_len(O, H, L, C, n)
        for k in (1.0, 1.5, 2.0):
            for filt in (False, True):
                sig = []
                for a, dr, b in ev:
                    if TS[a] < START or np.isnan(A[a]) or dr == 0 or (filt and dr != TR[a]): continue
                    i = int(np.searchsorted(tt, TS[a]))
                    if i >= len(tt) - 2: continue
                    sig.append(dict(setup=name, i=i, dir=int(dr), sl=(ta[i] if dr > 0 else tb[i]) - dr * k * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], S=k * A[a]))
                x = execute(tt, tb, ta, pd.DataFrame(sig), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; res[(n, k, filt)] = x
                rows.append(dict(len=n, SL=k, D1=filt, n=len(x), avg=x.R.mean(), train_sum=p.R.sum(), train=p.R.mean(), test=q.R.mean()))
    r = pd.DataFrame(rows).sort_values('train_sum', ascending=False)
    pb = pbo(np.column_stack([daily(res[k]) for k in res]))['pbo']
    best = r.iloc[0]; key = (int(best.len), float(best.SL), bool(best.D1)); x = res[key].reset_index(drop=True)
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((10000, len(x))) < .5, x.R.values, Rf).sum(1)
    money = {fr: run({'X': x}, fr)[:2] for fr in (.0075, .01)}
    base = r[(r.len == base_len) & (r.SL == 1.5) & (~r.D1)].iloc[0]
    print(f'\n=== {name} H1 (default len {base_len}) PBO {pb:.2f} ===')
    print(r.round(3).head(6).to_string(index=False))
    print(f'default: avg {base.avg:+.3f} train {base.train:+.3f} test {base.test:+.3f}')
    print(f'selected {key}: n={len(x)} avg {x.R.mean():+.3f} test {best.test:+.3f} | beats random {(drw < x.R.sum()).mean():.1%} | longs {x.R[x.dir>0].sum():+.1f} shorts {x.R[x.dir<0].sum():+.1f} | Cent 0.75% ${money[.0075][0]:,.0f} DD {money[.0075][1]:.0%} | 1% ${money[.01][0]:,.0f} DD {money[.01][1]:.0%}', flush=True)
    return res, r
if __name__ == '__main__':
    from ind10c import aroon, coral
    tt, tb, ta = load('20251002'); out = {}
    out['Aroon'] = optimise('Aroon', lambda O, H, L, C, n: aroon(O, H, L, C, n=n), 14, tt, tb, ta)
    out['Coral'] = optimise('Coral', lambda O, H, L, C, n: coral(O, H, L, C, sm=n), 21, tt, tb, ta)
    pickle.dump(out, open('opt_ac.pkl', 'wb'))
