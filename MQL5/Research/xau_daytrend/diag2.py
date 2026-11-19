import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import prepare
from m1 import load_m1
t,b,a = load_m1(); m5 = prepare(t,b,a)
m5['dt'] = pd.to_datetime(m5.ts, unit='s')
m5['yr'] = np.select([m5.dt < '2024-11-01', m5.dt < '2025-11-01'], ['Y1','Y2'], 'Y3')
rows = []
for d, g in m5.groupby('date'):
    g = g[g.wd < 5]
    if g.trend.isna().all() or len(g) < 200: continue
    T = g.trend.iloc[0]; adr = g.adr.iloc[0]
    def px(m): x = g[g.mn >= m]; return x.o.iloc[0] if len(x) else np.nan
    o1, o7, o13, c20 = px(60), px(7*60-g.eu.iloc[0]), px(13*60+30-g.us.iloc[0]), px(20*60+30-g.us.iloc[0])
    rows.append(dict(yr=g.yr.iloc[0], T=T, asia_lon=(o7-o1)*T/adr, lon_ny=(o13-o7)*T/adr, ny_pm=(c20-o13)*T/adr, full=(c20-o1)*T/adr,
                     up=T>0, raw=(c20-o1)/adr))
r = pd.DataFrame(rows)
print('mean move in D1-trend direction, as fraction of ADR (positive = trend continues intraday)')
print(r.groupby('yr')[['asia_lon','lon_ny','ny_pm','full']].mean().round(3))
print('share of days with uptrend', r.groupby('yr').up.mean().round(2).to_dict())
print('t-stat of full', r.groupby('yr').full.apply(lambda x: x.mean()/x.std()*np.sqrt(len(x))).round(2).to_dict())
print('gold drift (raw full-day move/ADR)', r.groupby('yr').raw.mean().round(3).to_dict())
p = m5.groupby('yr').c.agg(['first','last']).round(0); print(p)
