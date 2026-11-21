# Parity: literal Python port of XAU_QUARTET_v1.00 state functions (rolling window of 1500 closed bars) vs research signals.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars
from ind10 import ssl_hybrid, hma
from ind10c import coral
from ind10e import kst, gann_hilo
from ind10b import hold
tt, tb, ta = load_m1('20250101', '20250601')
def research_state(ev, n):
    st = np.zeros(n)
    if isinstance(ev, list):
        for a, d, b in ev: st[a:b + 1] = d
        return hold(st)
    return hold(ev)
def mq_kst(c):
    roc = lambda L: np.r_[np.zeros(L), (c[L:] / c[:-L] - 1) * 100]
    sm = lambda x, n: pd.Series(x).rolling(n).mean().values
    k = sm(roc(10), 10) + 2 * sm(roc(15), 10) + 3 * sm(roc(20), 10) + 4 * sm(roc(30), 15); k[:44] = 0
    d = k[-1] - np.mean(k[-9:]); return int(np.sign(d))
def mq_coral(c, sm=21, cd=.4):
    di = (sm - 1) / 2 + 1; c1 = 2 / (di + 1); c2 = 1 - c1; c3 = 3 * (cd * cd + cd ** 3); c4 = -3 * (2 * cd * cd + cd + cd ** 3); c5 = 3 * cd + 1 + cd ** 3 + 3 * cd * cd
    v = np.full(6, c[0]); bf = pbf = 0; st = 0
    for t in range(len(c)):
        src = c[t]
        for j in range(6): v[j] = c1 * src + c2 * v[j]; src = v[j]
        pbf, bf = bf, -cd ** 3 * v[5] + c3 * v[4] + c4 * v[3] + c5 * v[2]
        if t: st = 1 if bf > pbf else (-1 if bf < pbf else 0)
    return st
def mq_gann(h, l, c):
    hi = pd.Series(h).rolling(13).mean().values; lo = pd.Series(l).rolling(21).mean().values; st = 0
    for i in range(22, len(c)):
        if c[i] > hi[i - 1]: st = 1
        elif c[i] < lo[i - 1]: st = -1
    return st
def mq_ssl(h, l, c):
    eh, el = hma(h, 60), hma(l, 60); st = 0
    for i in range(70, len(c)):
        if c[i] > eh[i]: st = 1
        elif c[i] < el[i]: st = -1
    return st
W = 600
for nm, tf, rf, mf in (('KST', 3600, lambda m: kst(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_kst(w.c.values)),
                      ('Coral', 3600, lambda m: coral(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_coral(w.c.values)),
                      ('Gann', 3600, lambda m: gann_hilo(m.o.values, m.h.values, m.l.values, m.c.values), lambda w: mq_gann(w.h.values, w.l.values, w.c.values)),
                      ('SSL H4', 14400, lambda m: ssl_hybrid(m.h.values, m.l.values, m.c.values), lambda w: mq_ssl(w.h.values, w.l.values, w.c.values))):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); R = research_state(rf(m), len(m)); idx = range(W, len(m)) if tf == 3600 else range(300, len(m))
    win = W if tf == 3600 else 300
    agree = [R[i] == mf(m.iloc[i - win + 1:i + 1]) for i in idx]
    print(f'{nm:7s} bars {len(agree)} agree {np.mean(agree):.2%}', flush=True)
