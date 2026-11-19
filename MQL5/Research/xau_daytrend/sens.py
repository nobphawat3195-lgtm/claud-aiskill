import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import prepare, execute
from m1 import load_m1
t,b,a = load_m1(); m5 = prepare(t,b,a)
rows = []
for d, g in m5.groupby('date'):
    g = g[(g.wd < 5)]
    if len(g) < 200 or g.trend.isna().iloc[0]: continue
    day0 = g.ts.iloc[0] - g.mn.iloc[0]*60; us = g.us.iloc[0]
    for em in (30, 60, 90, 120, 180):
        x = g[g.mn + 5 == em]
        if not len(x): continue
        T = int(x.trend.iloc[0]); adr = x.adr.iloc[0]
        for ex in (17*60, 19*60, 20*60+30):
            rows.append((f'in{em//60:02d}{em%60:02d}_out{ex//60}{ex%60:02d}', int(x.i1.iloc[0]), T, x.c.iloc[0]-T*0.3*adr, day0+(ex-us)*60, x.ts.iloc[0]))
s = pd.DataFrame(rows, columns=['setup','i','dir','sl','texit','ts'])
r = execute(t,b,a,s, tps=(0.0,))
dt_ = pd.to_datetime(r.ts, unit='s'); r['yr'] = np.select([dt_ < '2024-11-01', dt_ < '2025-11-01'], ['Y1','Y2'], 'Y3')
p = r.pivot_table(index='setup', columns='yr', values='r0.0', aggfunc='sum').round(1); p['avgR'] = r.groupby('setup')['r0.0'].mean().round(3)
print(p); print('positive all 3 years:', (p[['Y1','Y2','Y3']] > 0).all(axis=1).sum(), 'of', len(p))
