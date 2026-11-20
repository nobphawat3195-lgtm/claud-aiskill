import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from bt import load, bars, execute
from ind10 import hma, atr, flips
from pbo import pbo
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); m = bars(tt, tb, ta, 3600).reset_index(drop=True)
H, L, C = m.h.values, m.l.values, m.c.values; TS = m.ts.values + 3600; A = atr(H, L, C, 14)
def run(n, k):
    eh, el = hma(H, n), hma(L, n); s = np.zeros(len(C)); v = 0
    for i in range(len(C)):
        if not np.isnan(eh[i]): v = 1 if C[i] > eh[i] else (-1 if C[i] < el[i] else v)
        s[i] = v
    ev = flips(s); idx = [i for i in np.flatnonzero(ev) if TS[i] >= START]; rows = []
    for a, b in zip(idx, idx[1:] + [len(m) - 1]):
        i = int(np.searchsorted(tt, TS[a]))
        if i >= len(tt) - 2: continue
        d = int(ev[a]); rows.append(dict(setup='ssl', i=i, dir=d, sl=(ta[i] if d > 0 else tb[i]) - d * k * A[a], texit=TS[b], ts=TS[a], S=k * A[a]))
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']; return x
def sim(x, start=300., cent=True):
    eq = pk = start; mdd = 0; curve = []; mon = {}
    for r in x.sort_values('ts').itertuples():
        lots = eq * .02 / (r.S * 100); p = lots * 100 * r.S * r.R; eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
        curve.append((r.ts, eq)); k = pd.Timestamp(r.ts, unit='s').strftime('%Y-%m'); mon[k] = mon.get(k, 0) + p
    return eq, mdd, curve, mon
x = run(60, 1.5); eq, mdd, curve, mon = sim(x)
hold = (x['x0.0'] - x.ts) / 3600
print(f'default HMA60 SL1.5: trades {len(x)} ({len(x)/12.4:.0f}/month) win {(x.R>0).mean():.0%} avg win {x.R[x.R>0].mean():+.2f}R avg loss {x.R[x.R<=0].mean():+.2f}R PF {x.R[x.R>0].sum()/-x.R[x.R<=0].sum():.2f} | SL hit {(x.R<=-0.98).mean():.0%} | hold median {hold.median():.0f}h | best {x.R.max():+.1f}R')
print(f'Cent 30,000 USC risk 2%: -> {eq*100:,.0f} USC (= USD {eq:,.0f}), max DD {mdd:.0%}')
print('month   USD    month-end equity')
run_eq = 300.
for k, v in sorted(mon.items()): run_eq += v; print(f'{k}  {v:+7.1f}  {run_eq:8.1f}')
t, e = zip(*curve); plt.figure(figsize=(9, 4)); plt.plot(pd.to_datetime(t, unit='s'), e); plt.title('SSL Hybrid core H1, Cent 30,000 USC (USD 300), risk 2%, real ticks'); plt.ylabel('USD'); plt.grid(alpha=.3); plt.tight_layout(); plt.savefig('/home/user/claud-aiskill/MQL5/Research/xau_daytrend/ssl_h1_equity.png', dpi=110)
# pre-registered optimisation grid: HMA length x SL ATR (9 configs), select on Nov-Jun
rows = []; days = pd.date_range('2025-11-03', '2026-11-13', freq='D'); cols = []
for n in (40, 60, 80):
    for k in (1.0, 1.5, 2.0):
        y = x if (n, k) == (60, 1.5) else run(n, k); a, b = y[y.ts < SPLIT], y[y.ts >= SPLIT]; e2, d2, _, _ = sim(y)
        rows.append(dict(HMA=n, SL=k, n=len(y), avg=y.R.mean(), train=a.R.mean(), test=b.R.mean(), USD=e2, DD=d2, SLmed=y.S.median()))
        g = y.groupby(pd.to_datetime(y.ts, unit='s').dt.normalize()).R.sum(); cols.append(pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values)
r = pd.DataFrame(rows); print(r.round(3).to_string(index=False)); print('PBO (9 configs):', round(pbo(np.column_stack(cols))['pbo'], 3))
