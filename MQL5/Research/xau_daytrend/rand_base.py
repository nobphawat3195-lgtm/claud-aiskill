# Random-direction baseline for the XMS modules, latest year, real ticks.
# Same entry time, SL distance and exit time; only the direction is randomised (10,000 draws).
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
r = pd.read_pickle('tf_base.pkl').dropna(subset=['r0.0'])
tt, tb, ta = load('20251102')
r = r[(r.ts >= pd.Timestamp('2025-11-03').timestamp()) & (r.ts < tt[-1] - 86400)].reset_index(drop=True)
r['i'] = np.searchsorted(tt, r.ts.values)
mid = (ta[r.i] + tb[r.i]) / 2
act = r[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy()
flip = act.copy(); flip['dir'] = -act.dir; flip['sl'] = 2 * mid - act.sl          # mirror the stop around the entry price
xa = execute(tt, tb, ta, act, tps=(0.0,)); xf = execute(tt, tb, ta, flip, tps=(0.0,))
r['Ra'] = xa['r0.0'].values; r['Rf'] = xf['r0.0'].values
r = r.dropna(subset=['Ra', 'Rf'])
r['Rlong'] = np.where(r.dir > 0, r.Ra, r.Rf)                                       # always-buy baseline
rng = np.random.default_rng(0)
def test(g, name):
    Ra, Rf = g.Ra.values, g.Rf.values
    draws = np.where(rng.random((10000, len(g))) < 0.5, Ra, Rf).sum(axis=1)
    real = Ra.sum(); pct = (draws < real).mean() * 100
    print(f'{name:10s} n={len(g):4d} | real {real:+7.1f}R | random dir: mean {draws.mean():+6.1f}R  95th {np.percentile(draws, 95):+6.1f}R | '
          f'real beats {pct:5.1f}% (p={1-pct/100:.3f}) | always-buy {g.Rlong.sum():+7.1f}R')
test(r, 'ALL 5')
for m in ['ORB_A', 'DM_A', 'DM_L', 'ASIA_B', 'LON_A']: test(r[r.setup == m], m)
