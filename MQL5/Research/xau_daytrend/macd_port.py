import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
mc = pickle.load(open('macd_tf.pkl', 'rb'))
M = {'H1': mc[(3600, False)], 'H1d': mc[(3600, True)], 'M15': mc[(900, False)], 'M15d': mc[(900, True)], 'M5': mc[(300, False)], 'M5d': mc[(300, True)]}
P = {'H1': ['H1'], 'M15': ['M15'], 'H1+M15': ['H1', 'M15'], 'H1+M15+M5d': ['H1', 'M15', 'M5d'], 'H1d+M15d+M5d': ['H1d', 'M15d', 'M5d'],
     'H1+M15d': ['H1', 'M15d'], 'M15+M5d': ['M15', 'M5d'], 'H1+M15+M5': ['H1', 'M15', 'M5']}
rows = []
for nm, ks in P.items():
    n = sum(len(M[k]) for k in ks)
    for f in (.005, .0075, .01, .015):
        eq, mdd, nn, sk, mon, cv, st, by = run({k: M[k] for k in ks}, f)
        rows.append(dict(port=nm, risk=f'{f:.2%}', per_mo=round(n / 12.4), end=round(eq), DD=round(mdd * 100), lose_m=sum(v < 0 for v in mon.values()), halt=st is not None))
r = pd.DataFrame(rows); pd.set_option('display.width', 200); print(r.to_string(index=False))
