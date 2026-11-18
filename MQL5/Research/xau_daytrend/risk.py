import numpy as np, pandas as pd
r = pd.read_pickle('trades_dt.pkl'); r = r[r.setup == 'DT_0100_sl0.3'].dropna(subset=['r0.0']).sort_values('ts')
R = r['r0.0'].values; yr = r.yr.values
print('trades', len(R), 'mean', R.mean().round(3), 'std', R.std().round(2), 'win', (R>0).mean().round(2), 'avg win', R[R>0].mean().round(2), 'min', R.min().round(2), 't-stat 3y', (R.mean()/R.std()*np.sqrt(len(R))).round(2))
def path(Rs, f, start=300, halt=.45):
    eq = start; pk = start; mdd = 0
    for x in Rs:
        dd = 1 - eq/pk; ff = f*(.25 if dd >= .40 else .5 if dd >= .25 else 1)
        eq *= 1 + ff*x; pk = max(pk, eq); mdd = max(mdd, 1-eq/pk)
        if mdd >= halt: return eq, mdd, True
    return eq, mdd, False
print('\nHistorical, $300 start each year (risk % -> end balance / maxDD per year)')
for f in (.01,.015,.02,.03):
    s = []
    for y in ('Y1','Y2','Y3'):
        e, m, h = path(R[yr==y], f); s.append(f'{y}: ${e:,.0f} DD{m:.0%}' + (' HALT' if h else ''))
    print(f'{f:.0%}', ' | '.join(s))
rng = np.random.default_rng(7); n = 250; B = 20
print('\nBlock bootstrap 1 year (5000 runs, 20-trade blocks): median / 10th pct end balance, P(DD>=45% halt), median maxDD')
for f in (.01,.015,.02,.03):
    res = []
    for _ in range(5000):
        st = rng.integers(0, len(R)-B, n//B); Rs = np.concatenate([R[s:s+B] for s in st])
        res.append(path(Rs, f))
    e = np.array([x[0] for x in res]); m = np.array([x[1] for x in res]); h = np.array([x[2] for x in res])
    print(f'{f:.0%}  median ${np.median(e):,.0f}  p10 ${np.percentile(e,10):,.0f}  p90 ${np.percentile(e,90):,.0f}  P(halt) {h.mean():.0%}  medDD {np.median(m):.0%}  P(loss) {(e<300).mean():.0%}')
