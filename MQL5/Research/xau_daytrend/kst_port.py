import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
k = pickle.load(open('kst_scale.pkl', 'rb')); o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); mc = pickle.load(open('macd_tf.pkl', 'rb'))
days = pd.date_range('2025-11-03', '2026-11-13', freq='D')
def daily(x):
    g = x.groupby(pd.to_datetime(x.ts, unit='s').dt.normalize()).R.sum(); return pd.Series(0.0, index=days).add(g, fill_value=0).reindex(days).values
E = {'sM15': o2[(900, 320, 20, 1.5)], 'sH1': o2[(3600, 60, None, 1.5)], 'mH1': mc[(3600, False)], 'mM15': mc[(900, False)],
     'kH1': k[(3600, False)], 'kM15': k[(900, False)], 'kM5': k[(300, False)]}
print('corr daily R: KST H1 vs SSL H1 %.2f, vs SSL M15 %.2f, vs MACD H1 %.2f | KST M15 vs SSL M15 %.2f' % (
    np.corrcoef(daily(E['kH1']), daily(E['sH1']))[0, 1], np.corrcoef(daily(E['kH1']), daily(E['sM15']))[0, 1],
    np.corrcoef(daily(E['kH1']), daily(E['mH1']))[0, 1], np.corrcoef(daily(E['kM15']), daily(E['sM15']))[0, 1]))
P = {'KST H1': ['kH1'], 'KST H1+M15': ['kH1', 'kM15'], 'KST H1+M15+M5': ['kH1', 'kM15', 'kM5'],
     'SENTINEL std (SSL M15+H1)': ['sM15', 'sH1'], 'SENTINEL turbo (+MACD H1,M15)': ['sM15', 'sH1', 'mH1', 'mM15'],
     'SENTINEL std + KST H1': ['sM15', 'sH1', 'kH1'], 'SENTINEL std + KST H1+M15': ['sM15', 'sH1', 'kH1', 'kM15']}
for nm, ks in P.items():
    n = sum(len(E[x]) for x in ks); out = []
    for f in (.005, .0075, .01):
        eq, mdd, nn, sk, mon, cv, st, by = run({x: E[x] for x in ks}, f)
        out.append(f'{f:.2%}: ${eq:,.0f} DD {mdd:.0%} lose {sum(v<0 for v in mon.values())}' + (' HALT' if st else ''))
    print(f'{nm:30s} ~{n/12.4:.0f}/mo | ' + ' | '.join(out))
