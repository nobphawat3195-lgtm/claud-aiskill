import pickle, numpy as np, pandas as pd
o = pickle.load(open('ssl_opt2.pkl', 'rb'))
def cent(x, f):
    x = x.sort_values('ts').copy(); x['xe'] = x['x0.0']; closed = []
    for r in x.itertuples():
        e0 = 300 + sum(p for t, p in closed if t <= r.ts); closed.append((r.xe, e0 * f * r.R))
    eq = pk = 300.; mdd = 0; mon = {}
    for t, p in sorted(closed):
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); k = pd.Timestamp(t, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + p
    return eq, mdd, mon
for nm, ks in (('old M15 240/EMA20 + H1 60', [(900, 240, 20, 1.5), (3600, 60, None, 1.5)]), ('new M15 320/EMA20 + H1 60', [(900, 320, 20, 1.5), (3600, 60, None, 1.5)])):
    x = pd.concat([o[k] for k in ks])
    for f in (.01, .015):
        eq, mdd, mon = cent(x, f)
        print(f'{nm}: n={len(x)} (~{len(x)/12.4:.0f}/mo) risk {f:.1%}: Cent USD300 -> {eq:,.0f} DD {mdd:.0%} losing months {sum(v<0 for v in mon.values())}/13')
        if f == .01: print('   ' + ' '.join(f'{a}:{b:+.0f}' for a, b in sorted(mon.items())))
