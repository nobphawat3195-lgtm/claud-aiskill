# DM_A family: at hour H (UTC), if ADX(H1) < X: direction = sign(close of last H1 bar - previous trading-day open),
# SL = k x ATR(H1, Wilder), hold to flat (20:30 UTC / Fri 20:00, minus 1h in US DST). Exness UTC days, Sunday -> Monday.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, itertools
from bt import bars, execute, us_dst
from m1 import load_m1
from grok_rep_lib import adx, tday

t, b, a = load_m1()
h1 = bars(t, b, a, 3600); h1['adx'], h1['atrw'] = adx(h1.h.values, h1.l.values, h1.c.values)
m5 = bars(t, b, a, 300); m5['td'] = tday(m5.ts).values
D = m5.groupby('td').agg(o=('o', 'first'))
days = list(D.index); h1end = h1.ts.values + 3600
rows = []
for k, d in enumerate(days):
    if k < 60 or pd.Timestamp(d).weekday() >= 5: continue
    day0 = pd.Timestamp(d).timestamp(); us = 3600 if us_dst(d) else 0
    flat = day0 + (20 * 3600 if pd.Timestamp(d).weekday() == 4 else 20 * 3600 + 1800) - us
    po = D.o.iloc[k - 1]
    for H in (1, 2, 3, 4, 5, 6):
        sec = day0 + H * 3600
        j = np.searchsorted(h1end, sec, side='right') - 1
        if j < 0 or h1end[j] < sec - 3600: continue
        c, ad, at = h1.c.values[j], h1.adx.values[j], h1.atrw.values[j]
        if c == po: continue
        dd = 1 if c > po else -1
        for kk in (0.75, 1.0, 1.25):
            rows.append((f'H{H}_k{kk}', int(np.searchsorted(t, sec)), dd, c - dd * kk * at, flat, sec, ad, at * kk))
s = pd.DataFrame(rows, columns=['setup', 'i', 'dir', 'sl', 'texit', 'ts', 'adx', 'S_nom'])
r = execute(t, b, a, s[['setup', 'i', 'dir', 'sl', 'texit', 'ts']], tps=(0.0,))
r['adx'] = s.adx.values; r = r.dropna(subset=['r0.0'])
r['S'] = (np.where(r.dir > 0, a[r.i], b[r.i]) - r.sl) * r.dir
dtt = pd.to_datetime(r.ts, unit='s')
r['yr'] = np.select([dtt < '2024-11-01', dtt < '2025-11-01'], ['Y1', 'Y2'], 'Y3')
r.to_pickle('dm_grid.pkl')
out = []
for X in (20, 25, 30, 35, 100):
    g = r[r.adx < X]
    p = g.pivot_table(index='setup', columns='yr', values='r0.0', aggfunc='sum')
    n = g.groupby('setup').size()
    for st in p.index:
        out.append(dict(setup=st, adx_max=X, Y1=p.loc[st, 'Y1'], Y2=p.loc[st, 'Y2'], Y3=p.loc[st, 'Y3'], n=n[st],
                        per_month=n[st] / 34.5, avgR=g[g.setup == st]['r0.0'].mean()))
o = pd.DataFrame(out); o['min'] = o[['Y1', 'Y2', 'Y3']].min(axis=1)
pd.set_option('display.width', 200); pd.set_option('display.max_rows', 200)
print(o.sort_values(['setup', 'adx_max']).round(2).to_string(index=False))
print('\npositive in all 3 years:', (o['min'] > 0).sum(), 'of', len(o))
