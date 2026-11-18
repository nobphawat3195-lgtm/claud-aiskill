# Grok v7 aggressive on a $100 USD Standard account, 6 months from every month start.
# 0.01-lot trades allowed while risk <= 40% of equity, risk-% sizing 0.5/0.25/0.75% (min lot dominates at $100),
# max 2 open positions while equity < $1000, max open risk 80%, daily loss stop 60%, no DD halt.
# Real ticks from Nov 2025, M1 before. No runner trail (not modelled).
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
from m1 import load_m1
r = pd.read_pickle('grok_v7.pkl').dropna(subset=['r0.0']).sort_values('ts').reset_index(drop=True)
mt, mb, ma = load_m1()
r['S'] = (np.where(r.dir > 0, ma[r.i], mb[r.i]) - r.sl) * r.dir; r['R'] = r['r0.0']; r['x'] = r['x0.0']
tt, tb, ta = load('20251102'); cut = pd.Timestamp('2025-11-03').timestamp()
m = (r.ts >= cut) & (r.ts < tt[-1] - 86400)
sub = r[m].copy(); sub['i'] = np.searchsorted(tt, sub.ts.values)
x = execute(tt, tb, ta, sub[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].reset_index(drop=True), tps=(0.0,))
r.loc[m, 'R'] = x['r0.0'].values; r.loc[m, 'x'] = x['x0.0'].values
r.loc[m, 'S'] = (np.where(sub.dir > 0, ta[sub.i], tb[sub.i]) - sub.sl) * sub.dir
r = r.dropna(subset=['R', 'x', 'S']); r = r[r.S > 0]
RISK = {'ORB_A': .005, 'DM_A': .005, 'DM_L': .0025, 'ASIA_B': .0075, 'LON_A': .0075}
def sim(tr, start=100.):
    ev = sorted([(x.ts, 1, i) for i, x in enumerate(tr.itertuples())] + [(x.x, 0, i) for i, x in enumerate(tr.itertuples())])
    R, S, M = tr.R.values, tr.S.values, tr.setup.values
    eq = pk = start; mdd = 0; op = {}; n = 0; day = None; dstart = eq; dstop = False
    for ts, kind, i in ev:
        d = int(ts // 86400)
        if d != day: day, dstart, dstop = d, eq, False
        if kind == 0:
            if i in op:
                eq += op.pop(i) * 100 * S[i] * R[i]; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
                if eq <= dstart * 0.4: dstop = True
                if eq <= 5: return max(eq, 0), mdd, n, True
            continue
        if dstop: continue
        lots = np.floor(eq * RISK[M[i]] / (S[i] * 100) / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * 100 * S[i] / eq > 0.40: continue
            if eq < 1000 and sum(1 for v in op.values() if v == 0.01) >= 2: continue
            lots = 0.01
        if sum(v * 100 * S[k] for k, v in op.items()) + lots * 100 * S[i] > 0.8 * eq: continue
        op[i] = lots; n += 1
    return eq, mdd, n, eq < 10
starts = pd.date_range('2024-01-01', '2026-05-01', freq='MS').append(pd.DatetimeIndex(['2026-05-12']))
rows = []
for s in starts:
    e = s + pd.DateOffset(months=6)
    g = r[(pd.to_datetime(r.ts, unit='s') >= s) & (pd.to_datetime(r.ts, unit='s') < e)]
    eq, mdd, n, dead = sim(g); rows.append((s.strftime('%Y-%m-%d'), eq, mdd, n, dead))
d = pd.DataFrame(rows, columns=['start', 'end_$', 'maxDD', 'trades', 'wiped'])
d['result'] = d['end_$'].map(lambda v: f'{v - 100:+,.0f}')
print(d.assign(maxDD=(d.maxDD * 100).round(0)).to_string(index=False))
print(f'\nstarts {len(d)} | ended above $100: {(d["end_$"] > 100).sum()} | lost >80%: {(d["end_$"] < 20).sum()} | median end ${d["end_$"].median():,.0f}')
