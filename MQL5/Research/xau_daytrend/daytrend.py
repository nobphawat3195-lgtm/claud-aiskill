import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import prepare, execute
from m1 import load_m1
t,b,a = load_m1(); m5 = prepare(t,b,a)
rows = []
for d, g in m5.groupby('date'):
    g = g[(g.wd < 5)]
    if len(g) < 200 or g.trend.isna().iloc[0]: continue
    for name, m in [('DT_0100', 60), ('DT_LON', 7*60 - g.eu.iloc[0])]:
        x = g[g.mn + 5 == m]
        if not len(x): continue
        k = x.index[0]; T = int(x.trend.iloc[0]); adr = x.adr.iloc[0]
        day0 = x.ts.iloc[0] - x.mn.iloc[0]*60
        for f in (0.3, 0.5, 0.8):
            rows.append((f'{name}_sl{f}', int(x.i1.iloc[0]), T, x.c.iloc[0] - T*f*adr, day0 + (20*60+30 - x.us.iloc[0])*60, x.ts.iloc[0]))
s = pd.DataFrame(rows, columns=['setup','i','dir','sl','texit','ts'])
r = execute(t,b,a,s, tps=(1.0, 2.0, 0.0))
dt_ = pd.to_datetime(r.ts, unit='s'); r['yr'] = np.select([dt_ < '2024-11-01', dt_ < '2025-11-01'], ['Y1','Y2'], 'Y3')
for c in ['r1.0','r2.0','r0.0']:
    p = r.pivot_table(index='setup', columns='yr', values=c, aggfunc='sum').round(1); p['avgR'] = r.groupby('setup')[c].mean().round(3)
    print('---', c); print(p)
r.to_pickle('trades_dt.pkl')
