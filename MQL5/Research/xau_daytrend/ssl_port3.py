import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); o3 = pickle.load(open('ssl_opt3.pkl', 'rb'))
tt, tb, ta = load('20251002'); rng = np.random.default_rng(0)
x = o3[(300, 960, 20, 1.5)].reset_index(drop=True); mid = (ta[x.i] + tb[x.i]) / 2
f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * mid - x.sl
Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; Ra = x.R.values
dr = np.where(rng.random((10000, len(x))) < .5, Ra, Rf).sum(1)
print(f'M5 960/EMA20/SL1.5: n={len(x)} beats random {(dr<Ra.sum()).mean():.1%} | longs {Ra[x.dir>0].sum():+.1f}R shorts {Ra[x.dir<0].sum():+.1f}R | win {(Ra>0).mean():.0%}')
def cent(x, f):
    x = x.sort_values('ts').copy(); x['xe'] = x['x0.0']; closed = []
    for r in x.itertuples():
        e0 = 300 + sum(p for t, p in closed if t <= r.ts); closed.append((r.xe, e0 * f * r.R))
    eq = pk = 300.; mdd = 0; mon = {}
    for t, p in sorted(closed):
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); k = pd.Timestamp(t, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + p
    return eq, mdd, mon
M5, M15, H1 = o3[(300, 960, 20, 1.5)], o2[(900, 320, 20, 1.5)], o2[(3600, 60, None, 1.5)]
for nm, parts in (('M15+H1', [M15, H1]), ('M5+M15+H1', [M5, M15, H1])):
    P = pd.concat(parts)
    for fr in (.005, .0075, .01):
        eq, mdd, mon = cent(P, fr)
        print(f'{nm:10s} n={len(P)} (~{len(P)/12.4:.0f}/mo) risk {fr:.2%}: Cent USD300 -> {eq:,.0f} DD {mdd:.0%} losing months {sum(v<0 for v in mon.values())}/13')
        if nm == 'M5+M15+H1' and fr == .0075: print('   ' + ' '.join(f'{a}:{b:+.0f}' for a, b in sorted(mon.items())))
