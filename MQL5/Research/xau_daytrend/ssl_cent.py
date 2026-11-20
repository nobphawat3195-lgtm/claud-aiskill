import pickle, numpy as np, pandas as pd
res = pickle.load(open('ssl_grid.pkl', 'rb'))
def cent(x, f):
    x = x.sort_values('ts'); closed = []
    for r in x.itertuples():
        e0 = 300 + sum(p for t, p in closed if t <= r.ts); closed.append((getattr(r, '_' + str(list(x.columns).index('x0.0') + 1)), e0 * f * r.R))
    eq = pk = 300.; mdd = 0; mon = {}
    for t, p in sorted(closed):
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); k = pd.Timestamp(t, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + p
    return eq, mdd, mon
C = {'M5 HMA720 +D1': [(300, 720, True)], 'M15 HMA240 +D1': [(900, 240, True)], 'H1 HMA60': [(3600, 60, False)], 'PORT M5+M15+H1': [(300, 720, True), (900, 240, True), (3600, 60, False)], 'PORT M15+H1': [(900, 240, True), (3600, 60, False)]}
for nm, ks in C.items():
    x = pd.concat([res[k] for k in ks])
    for f in (.005, .01):
        eq, mdd, mon = cent(x, f)
        print(f'{nm:15s} n={len(x)} (~{len(x)/12.4:.0f}/mo) Cent USD300 risk {f:.1%}: -> {eq:,.0f} DD {mdd:.0%} losing months {sum(v<0 for v in mon.values())}/13')
