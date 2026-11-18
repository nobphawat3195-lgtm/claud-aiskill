import sys; sys.path.insert(0, '.')
import numpy as np, pandas as pd
exec(open('dm_port.py').read().split("yrs = {")[0])          # reuse pick / sim / boot
def scaled(tr, f):                                             # Cent $300 = Standard $30,000 lot granularity, results / 100
    out = []
    for y, (s0, s1) in yrs.items():
        g = tr[(pd.to_datetime(tr.ts, unit='s') >= s0) & (pd.to_datetime(tr.ts, unit='s') < s1)]
        e, m, h, n = sim(g, f, 1.0, start=30000.); out.append(f'{y} ${e/100:,.0f} DD{m:.0%} {n/12:.1f}/mo' + ('!' if h else ''))
    return out
def bootc(tr, f, runs=1500, rng=np.random.default_rng(4)):
    wk = (tr.ts // (7 * 86400)).values; uw = np.unique(wk); E = []; H = []
    for _ in range(runs):
        parts = []; off = 0
        for w in rng.choice(uw, 52):
            g = tr[wk == w].copy(); base = (g.ts.min() // 86400) * 86400
            g['ts'] = g.ts - base + off; g['x'] = g.x - base + off; off += 7 * 86400; parts.append(g)
        e, m, h, n = sim(pd.concat(parts).sort_values('ts'), f, 1.0, start=30000.); E.append(e / 100); H.append(h)
    E = np.array(E); return np.median(E), np.percentile(E, 10), np.percentile(E, 90), (E < 300).mean(), np.mean(H)
yrs = {'Y1': ('2023-11-01', '2024-11-01'), 'Y2': ('2024-11-01', '2025-11-01'), 'Y3': ('2025-11-01', '2026-11-14')}
for name, spec in {'A 01:00 k1.0 ADX<25': [('H1_k1.0', 25)], 'B 01:00 k0.75 ADX<25': [('H1_k0.75', 25)],
                   'C 01:00 k0.75 + 02:00 k1.25 (ADX<25)': [('H1_k0.75', 25), ('H2_k1.25', 25)]}.items():
    tr = pick(spec)
    for f in (0.02, 0.03):
        md, p10, p90, pl, ph = bootc(tr, f)
        print(f'CENT $300 {name:38s} risk{f:.0%} | ' + ' | '.join(scaled(tr, f)) + f' || boot med ${md:,.0f} p10 ${p10:,.0f} p90 ${p90:,.0f} P(loss){pl:.0%} P(halt){ph:.0%}')
