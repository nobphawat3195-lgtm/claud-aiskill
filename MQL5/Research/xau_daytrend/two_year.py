# Combine latest year (real ticks) and previous year (M1) per indicator: random-direction test over both years.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
from m1 import load_m1
prev = pickle.load(open('prev_year.pkl', 'rb'))
a = pickle.load(open('ind10.pkl', 'rb')); b = pickle.load(open('ind10b.pkl', 'rb')); c = pickle.load(open('ind10c.pkl', 'rb'))
d = pickle.load(open('ind10d.pkl', 'rb')); e = pickle.load(open('ind10e.pkl', 'rb')); o = pickle.load(open('ott_m15.pkl', 'rb'))
LATEST = {'KST': e[(3600, 'KST')], 'SSL (HMA60)': a[(3600, 'SSLHybrid')], 'MACD': b[(3600, 'MACD')], 'Aroon': c[(3600, 'Aroon')], 'Coral': c[(3600, 'Coral')],
          'CCI': c[(3600, 'CCI')], 'OTT': d[(3600, 'OTT')], 'OTT src M15 SL5': o[5.0], 'Hull Suite': c[(3600, 'HullSuite')], 'Schaff TC': e[(3600, 'STC')],
          'Ehlers ITrend': e[(3600, 'ITrend')], 'MavilimW': d[(900, 'MavilimW')], 'Gann HiLo': e[(3600, 'GannHiLo')]}
def flipR(x, tt, tb, ta):
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    return execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values
tt, tb, ta = load('20251002'); FL = {}
for k, x in LATEST.items():
    x = x.reset_index(drop=True); s = 1.0 if 'R' in x and k != 'OTT src M15 SL5' else 1.0
    FL[k] = (x['R'].values, flipR(x, tt, tb, ta) * (x['R'].values / np.where(x['r0.0'].values == 0, 1, x['r0.0'].values) if k == 'OTT src M15 SL5' else 1), x.dir.values)
del tt, tb, ta
tt, tb, ta = load_m1('20240901', '20251101'); rng = np.random.default_rng(0)
print(f'{"indicator":16s} | latest R  prev R | 2-yr sum  2-yr random | longs  shorts (2 yr)')
for k, x in prev.items():
    x = x.reset_index(drop=True); Rp, Fp = x.R.values, flipR(x, tt, tb, ta)
    Rl, Fl, Dl = FL[k]
    Ra, Rf, D = np.r_[Rl, Rp], np.r_[Fl, Fp], np.r_[Dl, x.dir.values]
    drw = np.where(rng.random((10000, len(Ra))) < .5, Ra, Rf).sum(1)
    print(f'{k:16s} | {Rl.mean():+.3f}  {Rp.mean():+.3f} | {Ra.sum():+7.1f}R  {(drw < Ra.sum()).mean():6.1%} | {Ra[D>0].sum():+6.1f} {Ra[D<0].sum():+6.1f}', flush=True)
