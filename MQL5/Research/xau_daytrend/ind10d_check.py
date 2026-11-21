import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); sys.path.insert(0, '/home/user/claud-aiskill/MQL5/Research/toolkit')
import numpy as np, pandas as pd
from bt import load, execute
from pbo import pbo, deflated_sharpe
from sentinel_bt_run import run
tt, tb, ta = load('20251002'); out = pickle.load(open('ind10d.pkl', 'rb')); g = pickle.load(open('ssl_grid.pkl', 'rb')); rng = np.random.default_rng(0)
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    gg = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(gg, fill_value=0).reindex(days).values
print('PBO over 30 configs:', round(pbo(np.column_stack([daily(out[k]) for k in out]))['pbo'], 3))
ssl = daily(g[(3600, 60, False)])
for TFK, nm in ((3600,'OTT'), (900,'MavilimW'), (900,'Alligator'), (3600,'AlphaTrend'), (3600,'TrendMagic'), (3600,'VolStop')):
    x = out[(TFK, nm)].reset_index(drop=True); mid = (ta[x.i] + tb[x.i]) / 2
    f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * mid - x.sl
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; Ra = x.R.values
    dr = np.where(rng.random((10000, len(x))) < .5, Ra, Rf).sum(1); dd = daily(x)
    eq, mdd, n, sk, mon, cv, st, by = run({'X': x}, .0075)
    print(f'M{TFK//60} {nm:10s} n={len(x)} beats random {(dr<Ra.sum()).mean():.1%} | always-buy {np.where(x.dir>0,Ra,Rf).sum():+.1f}R | longs {Ra[x.dir>0].sum():+.1f} shorts {Ra[x.dir<0].sum():+.1f} | DSR(119) {deflated_sharpe(dd,119)["dsr"]:.2f} | corr with SSL H1 {np.corrcoef(dd, ssl)[0,1]:.2f} | Cent 0.75% -> ${eq:,.0f} DD {mdd:.0%} losing months {sum(v<0 for v in mon.values())}')
