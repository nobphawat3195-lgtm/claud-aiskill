import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); o3 = pickle.load(open('ssl_opt3.pkl', 'rb')); mc = pickle.load(open('macd_tf.pkl', 'rb'))
S = {'sH1': o2[(3600, 60, None, 1.5)], 'sM15': o2[(900, 320, 20, 1.5)], 'sM5': o3[(300, 960, 20, 1.5)],
     'mH1': mc[(3600, False)], 'mH1d': mc[(3600, True)], 'mM15': mc[(900, False)], 'mM15d': mc[(900, True)], 'mM5d': mc[(300, True)]}
P = {'A SENTINEL มาตรฐาน (SSL M15+H1)': ['sM15', 'sH1'],
     'B SENTINEL ไม้เยอะ (SSL M5+M15+H1)': ['sM5', 'sM15', 'sH1'],
     'C A + MACD H1,M15 (+D1)': ['sM15', 'sH1', 'mH1d', 'mM15d'],
     'D B + MACD H1,M15,M5 (+D1)': ['sM5', 'sM15', 'sH1', 'mH1d', 'mM15d', 'mM5d'],
     'E B + MACD H1,M15 ไม่กรอง + M5 +D1': ['sM5', 'sM15', 'sH1', 'mH1', 'mM15', 'mM5d'],
     'F A + MACD H1,M15 ไม่กรอง': ['sM15', 'sH1', 'mH1', 'mM15']}
rows = []
for nm, ks in P.items():
    n = sum(len(S[k]) for k in ks)
    for f in (.0025, .005, .0075):
        eq, mdd, nn, sk, mon, cv, st, by = run({k: S[k] for k in ks}, f)
        rows.append(dict(port=nm, risk=f'{f:.2%}', per_mo=round(n / 12.4), end=round(eq), DD=round(mdd * 100), ret_per_DD=round((eq / 300 - 1) / max(mdd, 1e-9), 1), lose_m=sum(v < 0 for v in mon.values()), halt=st is not None))
r = pd.DataFrame(rows); pd.set_option('display.width', 220); print(r.to_string(index=False))
