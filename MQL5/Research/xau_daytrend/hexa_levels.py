# Dashboard numbers for QUARTET v1.20 HEXA (6 engines) and HEXA TURBO (7 engines): Cent USD 300, 2 years, halt 70%, 5 risk levels
# + block bootstrap of weekly R (4-week blocks, 5,000 paths) for P(DD >= 70%).
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
E = pickle.load(open('port2y.pkl', 'rb')); F = pickle.load(open('fast_tf.pkl', 'rb')); N = pickle.load(open('ind11.pkl', 'rb'))
Q = {k: E[k] for k in ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']}
SIX = {**Q, 'PMO H4': N[('PMO', 14400)], 'AO H4': N[('AwesomeOsc', 14400)]}
SEV = {**SIX, 'AO M30F': F[('AO', 1800, 'DF')]}
rng = np.random.default_rng(1)
for nm, P in (('HEXA', SIX), ('TURBO', SEV)):
    x = pd.concat(P.values()); w = x.groupby(pd.to_datetime(x.ts, unit='s').dt.to_period('W')).R.sum()
    w = w.reindex(pd.period_range(w.index.min(), w.index.max(), freq='W'), fill_value=0).values
    for f in (.005, .0075, .01, .0125, .015):
        eq, mdd, n, sk, mon, cv, st, by = run(P, f, cent=True, halt=.70)
        dds = []
        for _ in range(5000):
            idx = np.concatenate([np.arange(s, s + 4) for s in rng.integers(0, len(w) - 4, 26)])
            e = np.cumprod(1 + f * w[idx]); pk = np.maximum.accumulate(np.r_[1, e])[1:]; dds.append((1 - e / pk).max())
        print(f'{nm} {f:.2%}: ${eq:,.0f} DD {mdd:.0%}' + (' HALT' if st else '') + f' | P(DD>=70%) {np.mean(np.array(dds) >= .7):.0%}', flush=True)
