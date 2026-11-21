import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from pbo import pbo, deflated_sharpe
out = pickle.load(open('ind10.pkl', 'rb')); days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    s = pd.Series(0.0, index=days); g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); s.loc[s.index.intersection(g.index)] = g; return s.values
keys = list(out); M = np.column_stack([daily(out[k]) for k in keys])
print('PBO over', len(keys), 'indicator x TF configs:', round(pbo(M)['pbo'], 3))
for k in [(3600, 'SSLHybrid'), (3600, 'Squeeze')]:
    print(k, 'DSR(29 trials):', {a: round(b, 3) for a, b in deflated_sharpe(daily(out[k]), len(keys)).items()})
    x = out[k].sort_values('ts')
    for name, cap in (('Cent 30,000 USC (fractional 0.01 USC lots)', 9), ('Standard USD 1,000', .055)):
        eq = pk = (300. if 'Cent' in name else 1000.); st = eq; mdd = 0; n = 0; mon = {}
        for r in x.itertuples():
            lots = eq * .02 / (r.S * 100) if 'Cent' in name else np.floor(eq * .02 / (r.S * 100) / .01 + 1e-9) * .01
            if lots < .01 and 'Cent' not in name:
                if r.S * 1 / eq > cap: continue
                lots = .01
            p = lots * 100 * r.S * r.R; eq += p; n += 1; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
            mk = pd.Timestamp(r.ts, unit='s').strftime('%y-%m'); mon[mk] = mon.get(mk, 0) + p
        print(f'   {name}: {st:,.0f} -> {eq:,.0f} USD, DD {mdd:.0%}, trades {n}, losing months {sum(v<0 for v in mon.values())}/{len(mon)}')
