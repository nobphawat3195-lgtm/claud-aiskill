import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, execute
from pbo import deflated_sharpe
tt, tb, ta = load('20251002'); res = pickle.load(open('ssl_grid.pkl', 'rb')); rng = np.random.default_rng(0)
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
def std300(x, f, cap=.055, halt=.48):
    eq = pk = 300.; mdd = 0; n = 0; mon = {}; closed = []
    x = x.sort_values('ts').copy(); x['xe'] = x['x0.0']
    for r in x.itertuples():
        e0 = 300 + sum(p for t, p in closed if t <= r.ts)                 # realized equity at entry (overlaps allowed)
        lots = np.floor(e0 * f / (r.S * 100) / .01 + 1e-9) * .01
        if lots < .01:
            if r.S / e0 > cap: continue
            lots = .01
        closed.append((r.xe, lots * 100 * r.S * r.R)); n += 1
    eq = 300.
    for t, p in sorted(closed):
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); k = pd.Timestamp(t, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + p
        if mdd >= halt: break
    return eq, mdd, n, mon
C = {'M5 HMA720 +D1': (300, 720, True), 'M15 HMA240 +D1': (900, 240, True), 'H1 HMA60 (EA v7.00)': (3600, 60, False), 'H1 HMA60 +D1': (3600, 60, True)}
for nm, k in C.items():
    x = res[k].reset_index(drop=True); mid = (ta[x.i] + tb[x.i]) / 2
    f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * mid - x.sl
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; Ra = x.R.values
    dr = np.where(rng.random((10000, len(x))) < .5, Ra, Rf).sum(1); lon = np.where(x.dir > 0, Ra, Rf).sum()
    ds = deflated_sharpe(daily(x), 18)['dsr']
    print(f'{nm}: n={len(x)} real {Ra.sum():+.1f}R beats random {(dr<Ra.sum()).mean():.1%} | always-buy {lon:+.1f}R | longs {Ra[x.dir>0].sum():+.1f} shorts {Ra[x.dir<0].sum():+.1f} | DSR {ds:.2f} | win {(Ra>0).mean():.0%} max losing streak {max(len(s) for s in "".join("L" if r<0 else "W" for r in Ra).split("W")) }')
    for f_ in (.01, .02):
        eq, mdd, n, mon = std300(x, f_)
        print(f'   Standard USD300 risk {f_:.0%} (min 0.01 lot if <=5.5%): -> {eq:,.0f} DD {mdd:.0%} trades {n} | ' + ' '.join(f'{a}:{b:+.0f}' for a, b in sorted(mon.items())))
P = pd.concat([res[C['M5 HMA720 +D1']], res[C['M15 HMA240 +D1']], res[C['H1 HMA60 (EA v7.00)']]])
for f_ in (.01, .02):
    eq, mdd, n, mon = std300(P, f_); print(f'PORTFOLIO M5+M15(+D1)+H1, Standard USD300 risk {f_:.0%}: -> {eq:,.0f} DD {mdd:.0%} trades {n} (~{n/12.4:.0f}/month) losing months {sum(v<0 for v in mon.values())}')
    print('   ' + ' '.join(f'{a}:{b:+.0f}' for a, b in sorted(mon.items())))
