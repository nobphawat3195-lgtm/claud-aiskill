import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
r = pd.read_pickle('trades_dt.pkl'); r = r[r.setup == 'DT_0100_sl0.3'].dropna(subset=['r0.0']).sort_values('ts').reset_index(drop=True)
t, b, a = load_m1()
e = np.where(r.dir > 0, a[r.i], b[r.i]); sld = (e - r.sl) * r.dir          # SL distance in $
r['sl_usd'] = sld.values
dt_ = pd.to_datetime(r.ts, unit='s'); r['q'] = dt_.dt.to_period('Q').astype(str)
print('SL distance $ (= loss per 0.01 lot on Standard) by quarter, median:')
print(r.groupby('q').sl_usd.median().round(1).to_string())
last = r[dt_ >= '2026-05-01']
print('last 6 months: median SL $%.1f, i.e. %.1f%% of $300 per trade at 0.01 lot' % (last.sl_usd.median(), last.sl_usd.median()/3))
R, S = r['r0.0'].values, r.sl_usd.values
def path(idx, f, start, forced):
    eq = pk = start; mdd = 0; n = 0
    for k in idx:
        dd = 1 - eq/pk; ff = f * (.25 if dd >= .4 else .5 if dd >= .25 else 1)
        lots = np.floor(eq * ff / (S[k] * 100) / 0.01 + 1e-9) * 0.01   # 1 lot = 100 oz
        if lots < 0.01:
            if not forced: continue
            lots = 0.01
        eq += lots * 100 * S[k] * R[k]; n += 1
        pk = max(pk, eq); mdd = max(mdd, 1 - eq/pk)
        if mdd >= .45 or eq <= 0: return eq, mdd, True, n
    return eq, mdd, False, n
rng = np.random.default_rng(3); last_idx = np.flatnonzero(dt_ >= '2025-11-01')
print('\n1 year, bootstrap from the most recent year (current gold price level), 5000 runs, risk 1.5%')
for name, start, forced in [('Standard $300, EA as written (skips if lot < 0.01)', 300, False),
                            ('Standard $300, forced 0.01 lot', 300, True),
                            ('Cent $300 (= Standard $30,000 / 100)', 30000, False)]:
    out = []
    for _ in range(5000):
        st = rng.choice(last_idx[:-20], 250 // 20); idx = np.concatenate([np.arange(s, s + 20) for s in st])
        out.append(path(idx, .015, start, forced))
    eq = np.array([o[0] for o in out]) / (100 if start == 30000 else 1); h = np.array([o[2] for o in out]); n = np.array([o[3] for o in out])
    print(f'{name}: trades/yr {np.median(n):.0f} | median ${np.median(eq):,.0f} | p10 ${np.percentile(eq,10):,.0f} | p90 ${np.percentile(eq,90):,.0f} | P(halt 45%) {h.mean():.0%} | P(loss) {(eq<300).mean():.0%}')
