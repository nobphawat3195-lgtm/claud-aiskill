import sys, os, glob; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
r = pd.read_pickle('grok_rep.pkl'); r = r.dropna(subset=['r0.0'])
have = sorted(os.path.basename(f)[:8] for f in glob.glob('days/*.npz'))
dd = pd.to_datetime(pd.Series(have)); gaps = dd.diff().dt.days.fillna(0).values
start = have[int(np.flatnonzero(gaps > 4)[-1])] if (gaps > 4).any() else have[0]
tt, tb, ta = load(start)
s0 = pd.Timestamp(start).timestamp() + 86400
sub = r[(r.ts >= s0) & (r.ts < tt[-1] - 86400)].copy()
sub['i'] = np.searchsorted(tt, sub.ts.values)
x = execute(tt, tb, ta, sub[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].reset_index(drop=True), tps=(0.0,))
sub = sub.reset_index(drop=True); sub['r_tick'] = x['r0.0']
print('tick coverage from', start, '| trades', len(sub))
print(sub.groupby('setup').agg(n=('r_tick', 'size'), R_m1=('r0.0', 'sum'), R_tick=('r_tick', 'sum')).round(1))
print('median |diff| R', round(float(np.median(abs(sub.r_tick - sub['r0.0']))), 3))
