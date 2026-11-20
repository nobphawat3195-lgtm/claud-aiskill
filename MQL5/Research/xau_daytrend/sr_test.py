import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load
from sr_sim import run
tt, tb, ta = load('20251102')
days = [d for d in range(int(pd.Timestamp('2025-11-03').timestamp()), int(tt[-1]) - 86400, 86400) if pd.Timestamp(d, unit='s').weekday() < 5]
SPLIT = pd.Timestamp('2026-09-01').timestamp()
def rep(x, nm):
    if x.empty: print(nm, 'no trades'); return
    a, b = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    eq = 300 + x.pnl.cumsum(); dd = (1 - eq / eq.cummax()).max()
    pf = x.pnl[x.pnl > 0].sum() / -x.pnl[x.pnl < 0].sum()
    print(f'{nm:38s} n={len(x):5d} ({len(x)/12.4:4.0f}/mo) win {(x.pnl>0).mean():.0%} avg ${x.pnl.mean():+.3f} sum ${x.pnl.sum():+7.1f} PF {pf:.2f} DD {dd:.0%} | Nov-Aug ${a.pnl.mean():+.3f} ({len(a)}) Sep-Nov ${b.pnl.mean():+.3f} ({len(b)}) | {dict(x.why.value_counts())}', flush=True)
    return x
x = rep(run(tt, tb, ta, days), 'v4.60 base 19:00-20:30 UTC')
for sh in (-60, -30, 30, 60):
    rep(run(tt, tb, ta, days, win=(19*60+sh, 20*60+30+sh)), f'shift {sh:+d} min')
for sl in (0.05, 0.10, 0.20):
    rep(run(tt, tb, ta, days, slip=sl), f'slippage {sl:.2f}/fill')
rep(run(tt, tb, ta, days, win=(0, 90)), 'S1 Thai 07:00-08:30 (00:00-01:30 UTC)')
rep(run(tt, tb, ta, days, win=(12*60, 13*60+30)), 'S2 Thai 19:00-20:30 (12:00-13:30 UTC)')
x.to_pickle('sr_base.pkl')
