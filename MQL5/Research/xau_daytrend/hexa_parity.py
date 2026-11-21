# Parity: literal Python port of the new EA state functions (StatePMO, StateAO; 1,500-bar window) vs research signals.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars
from ind10b import hold
from ind11 import pmo, awesome
tt, tb, ta = load_m1('20240801', '20250601')
def state_of(ev, n):
    st = np.zeros(n)
    for a, d, b in ev: st[a:b + 1] = d
    return hold(st)
def mq_pmo(c):
    a1, a2, ag = 2 / 35, 2 / 20, 2 / 11; s1 = p = sg = 0
    for i in range(len(c)):
        roc = (c[i] / c[i - 1] - 1) * 100 if i else 0
        if i == 0: s1 = roc; p = 10 * s1; sg = p; continue
        s1 += a1 * (roc - s1); p += a2 * (10 * s1 - p); sg += ag * (p - sg)
    return int(np.sign(p - sg))
def mq_ao(h, l):
    m = (h + l) / 2; return int(np.sign(m[-5:].mean() - m[-34:].mean()))
for nm, tf, rf, mf, W in (('PMO H4', 14400, lambda m: pmo(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_pmo(w.c.values), 300),
                          ('AO H4', 14400, lambda m: awesome(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_ao(w.h.values, w.l.values), 300),
                          ('AO M30', 1800, lambda m: awesome(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_ao(w.h.values, w.l.values), 1500)):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); R = state_of(rf(m), len(m))
    ag = [R[i] == mf(m.iloc[i - W + 1:i + 1]) for i in range(W, len(m))]
    print(f'{nm:7s} bars {len(ag)} agree {np.mean(ag):.2%}', flush=True)
