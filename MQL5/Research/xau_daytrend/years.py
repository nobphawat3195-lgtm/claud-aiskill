import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
r = pd.read_pickle(sys.argv[1] if len(sys.argv) > 1 else 'trades_m1.pkl')
dt_ = pd.to_datetime(r.ts, unit='s')
r['yr'] = np.select([dt_ < '2024-11-01', dt_ < '2025-11-01'], ['Y1 23/24', 'Y2 24/25'], 'Y3 25/26')
cols = [c for c in r if c.startswith('r') and c[1].isdigit()]
pd.set_option('display.width', 200)
for c in cols:
    p = r.pivot_table(index='setup', columns='yr', values=c, aggfunc='sum').round(1)
    p['min'] = p.min(axis=1); p['avgR/trade'] = r.groupby('setup')[c].mean().round(3)
    print(f'--- exit {c} (sum R per year)'); print(p)
print(r.pivot_table(index='setup', columns='yr', values='r0.0', aggfunc='size'))
