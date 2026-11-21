# QUARTET / HEXA / TURBO on a STANDARD USD 300 account: 0.01 lot = $1 per $1 move, lot step 0.01, halt 70%.
# Min-lot rule as in the EA: cap 5.5% (skip trades whose 0.01 lot risks more), or always trade 0.01 (cap = 100%).
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
E = pickle.load(open('port2y.pkl', 'rb')); F = pickle.load(open('fast_tf.pkl', 'rb')); N = pickle.load(open('ind11.pkl', 'rb'))
Q = {k: E[k] for k in ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']}
SIX = {**Q, 'PMO H4': N[('PMO', 14400)], 'AO H4': N[('AwesomeOsc', 14400)]}
SEV = {**SIX, 'AO M30F': F[('AO', 1800, 'DF')]}
SPLIT = pd.Timestamp('2025-11-01').timestamp()
x = pd.concat(SEV.values()); print('SL $ median by engine:', {k: round(v.S.median(), 1) for k, v in SEV.items()})
print('share of trades whose 0.01 lot risks > 5.5% of $300 (SL > $16.5):', {k: f'{(v.S > 16.5).mean():.0%}' for k, v in SEV.items()})
for nm, P in (('QUARTET', Q), ('HEXA', SIX), ('TURBO', SEV)):
    for cap, cl in ((.055, 'cap 5.5%'), (1.0, '0.01 always')):
        for f in (.0075, .01, .015):
            eq, mdd, n, sk, mon, cv, st, by = run(P, f, cent=False, halt=.70, cap=cap)
            ys = [round(run({k: v[(v.ts >= lo) & (v.ts < hi)] for k, v in P.items()}, f, cent=False, halt=.70, cap=cap)[0]) for lo, hi in ((0, SPLIT), (SPLIT, 9e9))]
            print(f'{nm:7s} {cl:11s} {f:.2%}: ${eq:>8,.0f} DD {mdd:.0%} trades {n} skipped {sk} | each year from $300 {ys}' + (f' HALT {pd.Timestamp(st, unit="s"):%Y-%m-%d}' if st else ''), flush=True)
