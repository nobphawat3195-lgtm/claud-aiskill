import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
tt, tb, ta = load('20251002'); out = pickle.load(open('ind10.pkl', 'rb')); rng = np.random.default_rng(0)
for k in [(3600, n) for n in ('SSLHybrid', 'Squeeze', 'HalfTrend', 'QQEMod', 'TwinRange')] + [(900, 'Squeeze')]:
    x = out[k].reset_index(drop=True); mid = (ta[x.i] + tb[x.i]) / 2
    f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * mid - x.sl
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; Ra = x.R.values
    dr = np.where(rng.random((10000, len(x))) < .5, Ra, Rf).sum(1); lon = np.where(x.dir > 0, Ra, Rf)
    sh = x.dir < 0
    print(f'M{k[0]//60} {k[1]:10s} n={len(x)} real {Ra.sum():+6.1f}R | random mean {dr.mean():+6.1f} 95th {np.percentile(dr,95):+6.1f} | beats {(dr<Ra.sum()).mean():.1%} | always-buy {lon.sum():+6.1f}R | longs {Ra[~sh].sum():+.1f}R shorts {Ra[sh].sum():+.1f}R')
