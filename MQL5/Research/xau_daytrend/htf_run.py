import sys, os, time, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars
from htf_cisd import detect
from htf_engine import engine
START = pd.Timestamp('2025-11-03').timestamp()
tt, tb, ta = load('20251002')
TFS = {60: 900, 300: 3600, 900: 14400}
VAR = [('brC', 'Limit'), ('brC', 'Market'), ('obOpen', 'Limit'), ('fvgCE', 'Limit')]
TPS = {'Bal 1/3R': (1.0, 3.0), 'Scalp 0.8/2R': (0.8, 2.0)}
res = {}
for tf, htf in TFS.items():
    m = bars(tt, tb, ta, tf).reset_index(drop=True)
    for fam, mode in VAR:
        t0 = time.time(); s = detect(m, htf, fam, mode)
        sig = [(m.ts.values[i] + tf, d, en, sl, mk) for i, d, en, sl, mk in s if m.ts.values[i] + tf >= START]
        for tpn, (a, b) in TPS.items():
            x = pd.DataFrame(engine(tt, tb, ta, sig, tf, a, b))
            res[(tf, fam, mode, tpn)] = x
            print(f'M{tf//60} {fam}-{mode} {tpn}: signals {len(sig)} trades {len(x)} | avg {x.R.mean():+.3f}R sum {x.R.sum():+.1f}R win {(x.R>0).mean():.0%} | SLmed {x.S.median():.2f} | {time.time()-t0:.0f}s', flush=True)
pickle.dump(res, open('htf_res.pkl', 'wb'))
