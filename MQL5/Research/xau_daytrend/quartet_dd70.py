# XAU QUARTET money sim with a 70% DD halt (Cent USD 300, 2 years, M1 bid/ask), risk 0.75-2%.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
E = pickle.load(open('port2y.pkl', 'rb')); ks = ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
for halt in (.5, .7):
    for f in (.0075, .01, .0125, .015, .02):
        out = []
        for lab, lo, hi in (('2 ปี', START, END), ('ปีก่อน', START, SPLIT), ('ปีล่าสุด', SPLIT, END)):
            eq, mdd, n, sk, mon, cv, st, by = run({k: E[k][(E[k].ts >= lo) & (E[k].ts < hi)] for k in ks}, f, cent=True, halt=halt)
            mv = np.array(list(mon.values())); low = min(e for t, e in cv)
            s = f'{lab}: ${eq:,.0f} DD{mdd:.0%} ต่ำสุด ${low:,.0f}{" หยุด " + pd.Timestamp(st, unit="s").strftime("%Y-%m-%d") if st else ""}'
            if lab == '2 ปี': s += f' เดือนลบ {(mv<0).sum()}/{len(mv)} แย่สุด {mv.min():+,.0f}'
            out.append(s)
        print(f'halt {halt:.0%} risk {f:.2%} | ' + ' | '.join(out), flush=True)
