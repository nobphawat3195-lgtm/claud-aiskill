import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, itertools
from scalp import features, signals, run, SPLIT
from m1 import load_m1
t, b, a = load_m1('20250701'); mid = (a + b) / 2
m5 = features(t, mid, mid)
for half_spread, label in [(0.0, 'zero spread'), (0.15, 'spread $0.30')]:
    bb, aa = mid - half_spread, mid + half_spread
    rows = []
    for tf, en, se in itertools.product(['D1', 'H1', 'NONE'], ['PB', 'BO', 'FADE'], ['ASIA', 'LON', 'NY', 'ALL']):
        if en != 'FADE' and tf == 'NONE': continue
        sig = signals(m5, tf, en, se)
        for hold in (12, 24):
            for tp, r in run(t, bb, aa, sig, (1.0, 1.5, 2.0), hold).items():
                tr, te = r[r.ts < SPLIT], r[r.ts >= SPLIT]
                rows.append(dict(cfg=f'{tf}_{en}_{se}_tp{tp}_h{hold}', R_train=tr.r.sum(), R_test=te.r.sum(), n=len(r), avg=r.r.mean()))
    df = pd.DataFrame(rows)
    both = df[(df.R_train > 0) & (df.R_test > 0)].sort_values('R_train', ascending=False)
    print(f'=== {label}: configs positive in train {int((df.R_train>0).sum())}/{len(df)}, positive in train AND test {len(both)}; mean avgR {df.avg.mean():.3f}')
    print(both.head(12).round(3).to_string(index=False))
