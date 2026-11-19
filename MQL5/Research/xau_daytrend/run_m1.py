import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import time, numpy as np, pandas as pd
from bt import prepare, execute
from m1 import load_m1
from setups import gen
d0 = sys.argv[1] if len(sys.argv) > 1 else None
t0=time.time(); t,b,a = load_m1(d0); print('pseudo-ticks', len(t), 'days', round((t[-1]-t[0])/86400), 'load', round(time.time()-t0,1))
m5 = prepare(t,b,a); s = gen(m5); r = execute(t,b,a,s)
r.to_pickle('trades_m1.pkl')
r['month'] = pd.to_datetime(r.ts, unit='s').dt.strftime('%Y-%m')
cols = [c for c in r if c.startswith('r')]
g = r.groupby('setup')
print(pd.concat([g.size().rename('n'), g[cols].sum().round(1), g['r0.0'].apply(lambda x: (x>0).mean()).round(2).rename('win0')], axis=1))
print('median spread $', round(float(np.median(a-b)),3), 'elapsed', round(time.time()-t0,1))
