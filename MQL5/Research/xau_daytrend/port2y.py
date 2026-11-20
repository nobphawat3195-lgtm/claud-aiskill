# Cent USD 300 money simulation over 2 years (Nov 2024 - Nov 2026, M1 bid/ask): new 4-engine portfolio vs SENTINEL v1.10 modes.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute, ema
from ind10 import atr, ssl_hybrid
from ind10b import sar_trades
from ind10c import coral
from ind10e import kst, gann_hilo
from sentinel_bt_run import run
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
tt, tb, ta = load_m1('20240801', '20261114')
d = bars(tt, tb, ta, 86400).reset_index(drop=True); dts = d.ts.values; dtr = np.where(d.c.values > ema(d.c.values, 20), 1, -1)
def evlist(ev):
    if isinstance(ev, list): return ev
    idx = np.flatnonzero(ev); return [(a, int(ev[a]), b) for a, b in zip(idx, np.r_[idx[1:], len(ev) - 1])]
def macd_k(c, k=1):
    m = ema(c, 12 * k) - ema(c, 26 * k); return sar_trades(np.sign(m - ema(m, 9 * k)))
def engine(nm, tf, fn, d1=False):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
    j = np.searchsorted(dts + 86400, TS, side='right') - 1; TR = np.where(j >= 0, dtr[np.clip(j, 0, None)], 0); rows = []
    for a, dr, b in evlist(fn(O, H, L, C)):
        if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or dr == 0 or (d1 and dr != TR[a]): continue
        i = int(np.searchsorted(tt, TS[a]))
        if i >= len(tt) - 2: continue
        e = ta[i] if dr > 0 else tb[i]
        rows.append(dict(setup=nm, i=i, dir=int(dr), sl=e - dr * 1.5 * A[a], texit=min(TS[min(b, len(m) - 1)], END), ts=TS[a], S=1.5 * A[a]))
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']).reset_index(drop=True); x['R'] = x['r0.0']
    print(f'{nm:14s} n={len(x):4d} ({len(x)/24.4:4.1f}/mo) avg {x.R.mean():+.3f}R sum {x.R.sum():+6.1f}R | y1 {x.R[x.ts<SPLIT].sum():+6.1f} y2 {x.R[x.ts>=SPLIT].sum():+6.1f}', flush=True)
    return x
E = {'KST H1': engine('KST H1', 3600, lambda O, H, L, C: kst(O, H, L, C)),
     'Coral H1': engine('Coral H1', 3600, lambda O, H, L, C: coral(O, H, L, C)),
     'Gann H1': engine('Gann H1', 3600, lambda O, H, L, C: gann_hilo(O, H, L, C)),
     'SSL H4': engine('SSL H4', 14400, lambda O, H, L, C: ssl_hybrid(H, L, C)),
     'SSL H1': engine('SSL H1', 3600, lambda O, H, L, C: ssl_hybrid(H, L, C)),
     'SSL M15 D1': engine('SSL M15 D1', 900, lambda O, H, L, C: ssl_hybrid(H, L, C, 320), d1=True),
     'MACD H1': engine('MACD H1', 3600, lambda O, H, L, C: macd_k(C)),
     'MACD M15': engine('MACD M15', 900, lambda O, H, L, C: macd_k(C, 4))}
pickle.dump(E, open('port2y.pkl', 'wb'))
P = {'SENTINEL มาตรฐาน (SSL H1+M15)': ['SSL H1', 'SSL M15 D1'],
     'SENTINEL เทอร์โบ (+MACD H1/M15)': ['SSL H1', 'SSL M15 D1', 'MACD H1', 'MACD M15'],
     'ใหม่ 4 เครื่อง (KST+Coral+Gann H1+SSL H4)': ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4'],
     'ใหม่ 4 + SSL M15 D1': ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4', 'SSL M15 D1'],
     'SENTINEL v1.20 ร่าง (SSL H1+M15 + KST H1)': ['SSL H1', 'SSL M15 D1', 'KST H1']}
for nm, ks in P.items():
    print('\n' + nm)
    for f in (.005, .0075, .01, .015):
        out = []
        for lab, lo, hi in (('2 ปี', START, END), ('ปีก่อน', START, SPLIT), ('ปีล่าสุด', SPLIT, END)):
            parts = {k: E[k][(E[k].ts >= lo) & (E[k].ts < hi)] for k in ks}
            eq, mdd, n, sk, mon, cv, st, by = run(parts, f, cent=True)
            mv = np.array(list(mon.values())); out.append(f'{lab}: ${eq:,.0f} DD{mdd:.0%}{" หยุด" if st else ""}' + (f' ไม้{n} เดือนลบ{(mv<0).sum()}/{len(mv)}' if lab == '2 ปี' else ''))
        print(f'  {f:.2%} | ' + ' | '.join(out), flush=True)
