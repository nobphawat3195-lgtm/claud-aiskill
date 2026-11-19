# Five replicated v2.90/v4.10 modules on a $300 USD account, sized like XMS RECENT:
# risk 1.5% per trade, min-lot cap 5.5% (ORB_A/DM_A/DM_L) and 2% (ASIA_B/LON_A), max open risk 8%,
# DD 35% -> x0.5, 45% -> x0.25, halt 48%. Latest year uses real ticks, earlier years M1.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
from m1 import load_m1
r = pd.read_pickle('grok_rep.pkl').dropna(subset=['r0.0']).sort_values('ts').reset_index(drop=True)
mt, mb, ma = load_m1()
r['S'] = (np.where(r.dir > 0, ma[r.i], mb[r.i]) - r.sl) * r.dir; r['R'] = r['r0.0']; r['x'] = r['x0.0']
tt, tb, ta = load('20251102'); cut = pd.Timestamp('2025-11-03').timestamp()
m = (r.ts >= cut) & (r.ts < tt[-1] - 86400)
sub = r[m].copy(); sub['i'] = np.searchsorted(tt, sub.ts.values)
x = execute(tt, tb, ta, sub[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].reset_index(drop=True), tps=(0.0,))
r.loc[m, 'R'] = x['r0.0'].values; r.loc[m, 'x'] = x['x0.0'].values
r.loc[m, 'S'] = (np.where(sub.dir > 0, ta[sub.i], tb[sub.i]) - sub.sl) * sub.dir
r = r.dropna(subset=['R', 'x', 'S']); r = r[r.S > 0]
CAP = {'ORB_A': .055, 'DM_A': .055, 'DM_L': .055, 'ASIA_B': .02, 'LON_A': .02}
def sim(tr, f=.015, start=300., halt=.48, maxopen=.08):
    ev = sorted([(x.ts, 1, i) for i, x in enumerate(tr.itertuples())] + [(x.x, 0, i) for i, x in enumerate(tr.itertuples())])
    R, S, M = tr.R.values, tr.S.values, tr.setup.values
    eq = pk = start; mdd = 0; op = {}; n = 0; mon = {}; lowest = start
    for ts, kind, i in ev:
        if kind == 0:
            if i in op:
                lots, rk = op.pop(i); pnl = lots * 100 * S[i] * R[i]; eq += pnl
                k = pd.Timestamp(ts, unit='s').strftime('%Y-%m'); mon.setdefault(k, [0, 0.0]); mon[k][0] += 1; mon[k][1] += pnl
                pk = max(pk, eq); lowest = min(lowest, eq); mdd = max(mdd, 1 - eq / pk)
                if mdd >= halt: return eq, mdd, True, n, mon, lowest
            continue
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .45 else .5 if dd >= .35 else 1)
        lots = np.floor(eq * ff / (S[i] * 100) / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * 100 * S[i] / eq > CAP[M[i]]: continue
            lots = 0.01
        rk = lots * 100 * S[i] / eq
        if sum(v[1] for v in op.values()) + rk > maxopen: continue
        op[i] = (lots, rk); n += 1
    return eq, mdd, False, n, mon, lowest
for title, s0, s1 in [('Nov 2023 - Oct 2024 (M1)', '2023-11-01', '2024-11-01'), ('Nov 2024 - Oct 2025 (M1)', '2024-11-01', '2025-11-01'),
                      ('Nov 2025 - Nov 2026 (real ticks)', '2025-11-01', '2026-11-14')]:
    g = r[(pd.to_datetime(r.ts, unit='s') >= s0) & (pd.to_datetime(r.ts, unit='s') < s1)]
    eq, mdd, h, n, mon, low = sim(g)
    pos = sum(1 for v in mon.values() if v[1] > 0)
    print(f'{title}: $300 -> ${eq:,.0f} ({eq-300:+,.0f}) | trades {n} ({n/12:.0f}/month) | max closed DD {mdd:.0%} | lowest balance ${low:,.0f} | {"HALTED at 48% DD" if h else "no halt"} | positive months {pos}/{len(mon)}')
    print('   monthly $:', ' '.join(f'{k[2:]}:{v[1]:+.0f}' for k, v in sorted(mon.items())))

rng = np.random.default_rng(9)
def boot(tr, fn, runs=1500):
    wk = (tr.ts // (7 * 86400)).values; uw = np.unique(wk); E = []; H = []
    for _ in range(runs):
        parts = []; off = 0
        for w in rng.choice(uw, 52):
            g = tr[wk == w].copy(); base = (g.ts.min() // 86400) * 86400
            g['ts'] = g.ts - base + off; g['x'] = g.x - base + off; off += 7 * 86400; parts.append(g)
        o = fn(pd.concat(parts).sort_values('ts')); E.append(o[0]); H.append(o[2])
    E = np.array(E); return np.median(E), np.percentile(E, 10), np.percentile(E, 90), (E < 300).mean(), np.mean(H)
def dma(tr):   # EA v5.00 sizing on DM_A only
    CAP['DM_A'] = .05; o = sim(tr, f=.03, halt=.45, maxopen=1.0); CAP['DM_A'] = .055; return o
print('\n1-year bootstrap over all 3 years (1500 runs):')
md, p10, p90, pl, ph = boot(r, sim)
print(f'  XMS 5 modules (Grok):  median ${md:,.0f} | p10 ${p10:,.0f} | p90 ${p90:,.0f} | P(loss) {pl:.0%} | P(halt) {ph:.0%}')
md, p10, p90, pl, ph = boot(r[r.setup == 'DM_A'], dma)
print(f'  DM_A only (EA v5.00):  median ${md:,.0f} | p10 ${p10:,.0f} | p90 ${p90:,.0f} | P(loss) {pl:.0%} | P(halt) {ph:.0%}')
