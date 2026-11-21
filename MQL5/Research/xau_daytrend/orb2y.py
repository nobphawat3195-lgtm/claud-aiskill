# XAU ORB v6.10 logic over 2 years (Nov 2024 - Nov 2026, Dukascopy M1 bid/ask): Asia 1-hour ranges starting 00/01/02/03 UTC,
# width 3-16 USD, first M5 close outside within range start + 5 h, only in the D1 trend (yesterday close vs EMA20), SL = opposite edge,
# no TP, exit 12:00 UTC. Same rules as orb4.py (latest year, real ticks). Then: random-direction test, yearly split, correlation with HEXA,
# and Cent USD 300 money simulation alone and added to HEXA at equal DD.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, ema, execute
from sentinel_bt_run import run as money
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
tt, tb, ta = load_m1('20240801', '20261114')
m = bars(tt, tb, ta, 300).reset_index(drop=True); d = bars(tt, tb, ta, 86400).reset_index(drop=True); d['e20'] = ema(d.c.values, 20)
dmap = {int(r.ts): (r.c, r.e20) for r in d.itertuples()}
mts = m.ts.values
def orb(rs, last=None, ex=12, minW=3, maxW=16, trend=True):
    last = rs + 5 if last is None else last; rows = []
    for day in range(int(START // 86400) * 86400, int(END) // 86400 * 86400 - 86400, 86400):
        wd = pd.Timestamp(day, unit='s').weekday()
        if wd > 4: continue
        p = dmap.get(day - 86400 * (1 if wd else 3))
        if p is None: continue
        tr = 1 if p[0] > p[1] else -1
        a, b = np.searchsorted(mts, day + rs * 3600), np.searchsorted(mts, day + (rs + 1) * 3600)
        if b - a < 10: continue
        hi, lo = m.h.values[a:b].max(), m.l.values[a:b].min()
        if not (minW <= hi - lo <= maxW): continue
        c2 = np.searchsorted(mts, day + last * 3600)
        for k in range(b, c2):
            c = m.c.values[k]; dr = 1 if c > hi else -1 if c < lo else 0
            if dr == 0: continue
            if trend and dr != tr: break                    # first close outside decides the day (as the EA: one signal per range)
            i = int(np.searchsorted(tt, mts[k] + 300)); sl = lo if dr > 0 else hi
            rows.append(dict(setup=f'R{rs}', i=i, dir=dr, sl=sl, texit=day + ex * 3600, ts=mts[k] + 300, S=abs((ta[i] + tb[i]) / 2 - sl))); break
    x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']).reset_index(drop=True); x['R'] = x['r0.0']
    return x
rng = np.random.default_rng(0)
def report(x, nm):
    mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
    Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((10000, len(x))) < .5, x.R.values, Rf).sum(1)
    p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    print(f"{nm:22s} n={len(x):4d} ({len(x)/24.4:4.1f}/mo) win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+6.1f}R | y1 {p.R.mean():+.3f} ({p.R.sum():+.1f}R) y2 {q.R.mean():+.3f} ({q.R.sum():+.1f}R) | random {(drw < x.R.sum()).mean():.1%} | L {x.R[x.dir>0].sum():+.1f} S {x.R[x.dir<0].sum():+.1f} | SL med ${x.S.median():.1f}", flush=True)
R = {rs: orb(rs) for rs in (0, 1, 2, 3)}
for rs in R: report(R[rs], f'range {rs:02d}-{rs+1:02d}')
ALL = pd.concat(R.values()).sort_values('ts').reset_index(drop=True); report(ALL, 'ORB v6.10 (4 ranges)')
R0 = R[0]; report(R0, 'ORB single 00-01 (C1)')
pickle.dump(R, open('orb2y.pkl', 'wb'))
# correlation + money
E = pickle.load(open('port2y.pkl', 'rb')); N = pickle.load(open('ind11.pkl', 'rb'))
HEXA = {**{k: E[k] for k in ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']}, 'PMO H4': N[('PMO', 14400)], 'AO H4': N[('AwesomeOsc', 14400)]}
wk = lambda x: x.groupby(pd.to_datetime(x.ts, unit='s').dt.to_period('W')).R.sum()
W = pd.DataFrame({**{k: wk(v) for k, v in HEXA.items()}, 'ORB4': wk(ALL), 'ORB0': wk(R0)}).fillna(0); hs = W[list(HEXA)].sum(axis=1)
print('weekly corr with HEXA total: ORB4 %.2f  ORB0 %.2f' % (W.ORB4.corr(hs), W.ORB0.corr(hs)))
for k in ('ORB4', 'ORB0'): print(k, 'vs engines', ' '.join(f'{e}:{W[k].corr(W[e]):.2f}' for e in HEXA))
def at_dd(parts, target=.46):
    best = None
    for f in np.arange(.004, .0201, .0005):
        eq, mdd, n, sk, mon, cv, st, by = money(parts, f, cent=True, halt=.70)
        if mdd <= target and not st: best = (f, eq, mdd)
    return best
ORBP = {f'ORB R{rs}': R[rs] for rs in R}
for nm, parts in (('ORB 4 ranges alone', ORBP), ('ORB R0 alone', {'ORB R0': R0}), ('HEXA', HEXA), ('HEXA + ORB R0', {**HEXA, 'ORB R0': R0}), ('HEXA + ORB 4 ranges', {**HEXA, **ORBP})):
    for f in (.005, .01, .015, .02):
        eq, mdd, n, sk, mon, cv, st, by = money(parts, f, cent=True, halt=.70)
        ys = [round(money({k: v[(v.ts >= lo) & (v.ts < hi)] for k, v in parts.items()}, f, cent=True, halt=.70)[0]) for lo, hi in ((0, SPLIT), (SPLIT, 9e9))]
        mv = np.array(list(mon.values()))
        print(f'{nm:20s} {f:.2%}: ${eq:>8,.0f} DD {mdd:.0%} trades {n} yrs {ys} neg months {(mv<0).sum()}/{len(mv)}' + (' HALT' if st else ''), flush=True)
    b = at_dd(parts); print(f'   -> at DD<=46%: risk {b[0]:.2%} ${b[1]:,.0f} DD {b[2]:.0%}' if b else '   -> none', flush=True)
