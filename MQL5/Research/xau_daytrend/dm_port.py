import numpy as np, pandas as pd
r = pd.read_pickle('dm_grid.pkl'); r = r[r.S > 0].copy(); r['R'] = r['r0.0']; r['x'] = r['x0.0']
def pick(spec): return pd.concat([r[(r.setup == s) & (r.adx < X)] for s, X in spec]).sort_values('ts').reset_index(drop=True)
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
            if 0.01 * 100 * S[i] / eq > cap: continue
            lots = 0.01
        op[i] = lots; n += 1
    return eq, mdd, False, n
def boot(tr, f, cap, runs=1500, rng=np.random.default_rng(2)):
    wk = (tr.ts // (7 * 86400)).values; uw = np.unique(wk); out = []
    for _ in range(runs):
        parts = []; off = 0
        for w in rng.choice(uw, 52):
            g = tr[wk == w].copy(); base = (g.ts.min() // 86400) * 86400
            g['ts'] = g.ts - base + off; g['x'] = g.x - base + off; off += 7 * 86400; parts.append(g)
        out.append(sim(pd.concat(parts).sort_values('ts'), f, cap))
    E = np.array([o[0] for o in out]); H = np.array([o[2] for o in out])
    return np.median(E), np.percentile(E, 10), np.percentile(E, 90), (E < 300).mean(), H.mean()
yrs = {'Y1': ('2023-11-01', '2024-11-01'), 'Y2': ('2024-11-01', '2025-11-01'), 'Y3': ('2025-11-01', '2026-11-14')}
cands = {
 'A current v5 (01:00 k1.0 ADX<25)': [('H1_k1.0', 25)],
 'B 01:00 k0.75 ADX<25':             [('H1_k0.75', 25)],
 'C B + 02:00 k1.25 ADX<25':         [('H1_k0.75', 25), ('H2_k1.25', 25)],
 'D B + 02:00 k1.0 ADX<25':          [('H1_k0.75', 25), ('H2_k1.0', 25)],
 'E 01:00 k0.75 ADX<30':             [('H1_k0.75', 30)],
 'F 01:00 k0.75 no ADX filter':      [('H1_k0.75', 100)],
}
for name, spec in cands.items():
    tr = pick(spec)
    for f, cap in [(.03, .05), (.04, .06)]:
        ys = []
        for y, (s0, s1) in yrs.items():
            g = tr[(pd.to_datetime(tr.ts, unit='s') >= s0) & (pd.to_datetime(tr.ts, unit='s') < s1)]
            e, m, h, n = sim(g, f, cap); ys.append(f'{y} ${e:,.0f} DD{m:.0%} {n/12:.1f}/mo' + ('!' if h else ''))
        md, p10, p90, pl, ph = boot(tr, f, cap)
        print(f'{name:34s} risk{f:.0%} cap{cap:.0%} | ' + ' | '.join(ys) + f' || boot med ${md:,.0f} p10 ${p10:,.0f} p90 ${p90:,.0f} P(loss){pl:.0%} P(halt){ph:.0%}')
