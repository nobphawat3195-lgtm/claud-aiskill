# D1-trend trades sized for a $300 Standard account, last year only. Exit at 20:30 UTC or SL; no TP.
#  A) one entry at 01:00 UTC, SL = k x ADR
#  B) entry at 01:00 plus re-entries on M5 EMA20 pullbacks in the trend direction after a stop, SL = m x ATR(M5)
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from scalp import features, SPLIT, START
from m1 import load_m1
t, b, a = load_m1('20250701'); m5 = features(t, b, a)
c, o, h, l, e20 = m5.c.values, m5.o.values, m5.h.values, m5.l.values, m5.ema20.values
def trade(i, d, sl_dist, te, slip=0.0):
    e = (a[i] if d > 0 else b[i]) + d * slip; j1 = np.searchsorted(t, te)
    if j1 <= i + 1: return None
    adv = ((b[i+1:j1] if d > 0 else a[i+1:j1]) - d * slip - e) * d
    hs = np.flatnonzero(adv <= -sl_dist); k = hs[0] if len(hs) else len(adv) - 1
    return t[i + 1 + k], adv[k] / sl_dist, sl_dist
rows = []
for date, g in m5.groupby('date'):
    g = g[(g.wd < 5) & (g.ts >= START)]
    if len(g) < 200 or g.trend.isna().all(): continue
    T = int(g.trend.iloc[0]); adr = g.adr.iloc[0]; us = g.us.iloc[0]
    day0 = g.ts.iloc[0] - g.mn.iloc[0] * 60; te = day0 + (20*60+30 - us) * 60
    x = g[g.mn + 5 == 60]
    if not len(x) or T == 0: continue
    k0 = x.index[0]
    for kf in (0.1, 0.15, 0.2, 0.3):
        r = trade(int(m5.i1[k0]), T, kf * adr, te)
        if r: rows.append(('A_sl%.2fADR' % kf, x.ts.iloc[0], *r))
    for mf, maxn in [(1.5, 3), (2.0, 3), (1.5, 6), (2.0, 6)]:
        busy, n = -1, 0; name = f'B_sl{mf}ATR_max{maxn}'
        for k in g.index[g.index >= k0]:
            if n >= maxn or m5.ts[k] + 300 >= te: break
            if m5.ts[k] + 300 < busy: continue
            first = (k == k0)
            pb = (T > 0 and l[k] <= e20[k] < c[k] and c[k] > o[k]) or (T < 0 and h[k] >= e20[k] > c[k] and c[k] < o[k])
            if not (first or (n > 0 and pb)): continue
            r = trade(int(m5.i1[k]), T, mf * m5.atr[k], te)
            if not r: continue
            rows.append((name, m5.ts[k], *r)); n += 1; busy = r[0]
            if r[1] > -0.999: break          # still open at the close or exited by time: day done
df = pd.DataFrame(rows, columns=['cfg', 'ts', 'x', 'r', 'sl_usd'])
df['part'] = np.where(df.ts < SPLIT, 'train', 'test')
p = df.pivot_table(index='cfg', columns='part', values='r', aggfunc=['sum', 'size']).round(1)
p['avgR'] = df.groupby('cfg').r.mean().round(3); p['trades/day'] = (df.groupby('cfg').size() / df.ts.map(lambda s: s // 86400).nunique()).round(2)
p['SL$ median'] = df.groupby('cfg').sl_usd.median().round(1); p['risk% of $300 at 0.01'] = (p['SL$ median'] / 3).round(1)
pd.set_option('display.width', 220); print(p)
df.to_pickle('trend_re.pkl')
