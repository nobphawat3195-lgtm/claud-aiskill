import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
r = pd.read_pickle('grok_rep.pkl')
t, b, a = load_m1(); e = np.where(r.dir > 0, a[r.i], b[r.i]); r['S'] = (e - r.sl) * r.dir; r['R'] = r['r0.0']; r['x'] = r['x0.0']
print('dropped rows without a result:', int(r[['R','x','S']].isna().any(axis=1).sum()), 'of', len(r)); r = r.dropna(subset=['R', 'x', 'S']); r = r[r.S > 0]
def sim(tr, f, cap, start=300., halt=.45):
    ev = sorted([(x.ts, 1, i) for i, x in enumerate(tr.itertuples())] + [(x.x, 0, i) for i, x in enumerate(tr.itertuples())])
    R, S = tr.R.values, tr.S.values; eq = pk = start; mdd = 0; op = {}; n = 0
    for ts, kind, i in ev:
        if kind == 0:
            if i in op:
                eq += op.pop(i) * 100 * S[i] * R[i]; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
                if mdd >= halt or eq <= 0: return max(eq, 0), mdd, True, n
            continue
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .4 else .5 if dd >= .25 else 1)
        lots = np.floor(eq * ff / (S[i] * 100) / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * 100 * S[i] / eq > cap: continue          # min lot would risk more than the cap: skip
            lots = 0.01
        op[i] = lots; n += 1
    return eq, mdd, False, n
def boot(tr, f, cap, runs=2000, rng=np.random.default_rng(1)):
    wk = (tr.ts // (7 * 86400)).values; uw = np.unique(wk); out = []
    for _ in range(runs):
        pick = rng.choice(uw, 52); parts = []; off = 0
        for w in pick:
            g = tr[wk == w].copy(); base = (g.ts.min() // 86400) * 86400
            g['ts'] = g.ts - base + off; g['x'] = g.x - base + off; off += 7 * 86400; parts.append(g)
        out.append(sim(pd.concat(parts).sort_values('ts'), f, cap))
    E = np.array([o[0] for o in out]); H = np.array([o[2] for o in out]); M = np.array([o[1] for o in out])
    return f'median ${np.median(E):,.0f} p10 ${np.percentile(E,10):,.0f} p90 ${np.percentile(E,90):,.0f} P(loss) {(E<300).mean():.0%} P(halt) {H.mean():.0%} medDD {np.median(M):.0%}'
dtt = pd.to_datetime(r.ts, unit='s')
yrs = {'Y1 23/24': ('2023-11-01', '2024-11-01'), 'Y2 24/25': ('2024-11-01', '2025-11-01'), 'Y3 25/26': ('2025-11-01', '2026-11-14')}
for name, mods, f, cap in [('DM_A only', ['DM_A'], .03, .05), ('DM_A only', ['DM_A'], .05, .06),
                           ('DM_A + ORB_A', ['DM_A', 'ORB_A'], .03, .05), ('DM_A + ORB_A', ['DM_A', 'ORB_A'], .05, .07)]:
    tr = r[r.setup.isin(mods)].sort_values('ts').reset_index(drop=True)
    line = []
    for y, (s0, s1) in yrs.items():
        g = tr[(pd.to_datetime(tr.ts, unit='s') >= s0) & (pd.to_datetime(tr.ts, unit='s') < s1)]
        eq, m, h, n = sim(g, f, cap); line.append(f'{y}: ${eq:,.0f} DD{m:.0%} n{n}{" HALT" if h else ""}')
    print(f'{name:13s} risk {f:.0%} cap {cap:.0%} | ' + ' | '.join(line))
    print(f'{"":13s} bootstrap 1y from 3y: ' + boot(tr, f, cap))
