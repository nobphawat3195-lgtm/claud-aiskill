# SSL1 (HMA high/low channel) build-out: TF x HMA length x D1 trend filter. Entry on SSL flip (in trend direction if filtered),
# exit on the next flip or SL 1.5 ATR(14). Latest year, real ticks.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, bars, execute, ema
from ind10 import atr
from pbo import pbo, deflated_sharpe
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002')
def wma(x, n):
    w = np.arange(1, n + 1, dtype=float); y = np.convolve(x, w[::-1], 'full')[n - 1:len(x)] / w.sum()
    return np.r_[np.full(n - 1, np.nan), y]
def hma(x, n): return wma(2 * wma(x, n // 2) - wma(x, n), int(round(np.sqrt(n))))
d = bars(tt, tb, ta, 86400).reset_index(drop=True); d['e'] = ema(d.c.values, 20)
dts = d.ts.values; dtr = np.where(d.c.values > d.e.values, 1, -1)          # trend of each completed D1 bar
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
res = {}; rows = []
for tf in (60, 300, 900, 1800, 3600):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); H, L, C = m.h.values, m.l.values, m.c.values; TS = m.ts.values + tf; A = atr(H, L, C, 14)
    j = np.searchsorted(dts + 86400, TS, side='right') - 1; TR = np.where(j >= 0, dtr[np.clip(j, 0, None)], 0)   # last D1 bar closed by TS
    for n in sorted({60, min(960, 60 * 3600 // tf)}):
        eh, el = hma(H, n), hma(L, n)
        st = np.zeros(len(C)); v = 0
        ok = ~np.isnan(eh)
        for i in range(len(C)):
            if ok[i]: v = 1 if C[i] > eh[i] else (-1 if C[i] < el[i] else v)
            st[i] = v
        fl = np.flatnonzero((st != np.r_[0, st[:-1]]) & (st != 0)); fl = fl[TS[fl] >= START]
        for filt in (False, True):
            sig = []
            for a, b in zip(fl, np.r_[fl[1:], len(m) - 1]):
                dr = int(st[a])
                if filt and dr != TR[a]: continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                sig.append(dict(setup='s', i=i, dir=dr, sl=(ta[i] if dr > 0 else tb[i]) - dr * 1.5 * A[a], texit=TS[b], ts=TS[a], S=1.5 * A[a]))
            x = execute(tt, tb, ta, pd.DataFrame(sig), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']
            key = (tf, n, filt); res[key] = x
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            eq = pk = 300.; mdd = 0
            for r in x.sort_values('ts').itertuples(): eq += eq * .02 * r.R; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
            rows.append(dict(TF=f'M{tf//60}', HMA=n, D1=filt, n=len(x), per_mo=len(x) / 12.4, avg=x.R.mean(), train=p.R.mean(), test=q.R.mean(), USD=eq, DD=mdd, SLmed=x.S.median()))
            print(rows[-1], flush=True)
r = pd.DataFrame(rows); pd.set_option('display.width', 200); print(r.round(3).to_string(index=False))
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
M = np.column_stack([daily(res[k]) for k in res]); print('PBO over', len(res), 'configs:', round(pbo(M)['pbo'], 3))
pickle.dump(res, open('ssl_grid.pkl', 'wb'))
