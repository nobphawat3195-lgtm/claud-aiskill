# Verify OTT / MavilimW against the user-supplied Pine source: original strategy = pure stop-and-reverse (no SL).
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import atr
from ind10d import mavilimw
START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002'); rng = np.random.default_rng(0)
def ott_src(c, length=2, percent=1.4):                     # line-by-line port of the Pine source (VAR starts at 0)
    a = 2 / (length + 1); n = len(c); d = np.r_[0, np.diff(c)]
    ud = pd.Series(np.where(d > 0, d, 0)).rolling(9).sum().values; dd = pd.Series(np.where(d < 0, -d, 0)).rolling(9).sum().values
    cmo = np.nan_to_num((ud - dd) / (ud + dd)); v = np.zeros(n)
    for i in range(n): v[i] = a * abs(cmo[i]) * c[i] + (1 - a * abs(cmo[i])) * (v[i - 1] if i else 0)
    ls = np.zeros(n); ss = np.zeros(n); dr = np.ones(n); ott = np.zeros(n)
    for i in range(n):
        f = v[i] * percent * 0.01; l0, s0 = v[i] - f, v[i] + f
        lp = ls[i - 1] if i else l0; sp = ss[i - 1] if i else s0
        l0 = max(l0, lp) if v[i] > lp else l0; s0 = min(s0, sp) if v[i] < sp else s0; ls[i], ss[i] = l0, s0
        dr[i] = (1 if dr[i - 1] == -1 and v[i] > sp else (-1 if dr[i - 1] == 1 and v[i] < lp else dr[i - 1])) if i else 1
        mt = l0 if dr[i] == 1 else s0; ott[i] = mt * (200 + percent) / 200 if v[i] > mt else mt * (200 - percent) / 200
    o2 = np.r_[ott[0], ott[0], ott[:-2]]
    up = (v > o2) & (np.r_[False, v[:-1] <= o2[:-1]]); dn = (v < o2) & (np.r_[False, v[:-1] >= o2[:-1]])
    st = np.zeros(n); s = 0
    for i in range(n):
        if up[i]: s = 1
        elif dn[i]: s = -1
        st[i] = s
    ch = np.flatnonzero((st != np.r_[0, st[:-1]]) & (st != 0)); return [(a_, int(st[a_]), b) for a_, b in zip(ch, np.r_[ch[1:], n - 1])]
for tf in (300, 900, 3600):
    m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
    for nm, ev in (('OTT (source)', ott_src(C)), ('MavilimW (source)', mavilimw(O, H, L, C))):
        for slk, lab in ((50.0, 'no SL (original)'), (1.5, 'SL 1.5 ATR')):
            rows = []
            for a, d, b in ev:
                if TS[a] < START or np.isnan(A[a]) or d == 0: continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                rows.append(dict(setup=nm, i=i, dir=int(d), sl=(ta[i] if d > 0 else tb[i]) - d * slk * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0'])
            x['usd'] = x['r0.0'] * slk * A[[int(np.searchsorted(TS, t)) for t in x.ts]]          # USD per 1 oz (0.01 lot)
            x['R1'] = x.usd / (1.5 * A[[int(np.searchsorted(TS, t)) for t in x.ts]])              # in units of 1.5 ATR for comparison
            mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
            Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; Ra = x['r0.0'].values
            drw = np.where(rng.random((5000, len(x))) < .5, Ra, Rf).sum(1)
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            print(f'M{tf//60:<3} {nm:18s} {lab:17s} n={len(x):5d} win {(x.usd>0).mean():.0%} USD/0.01lot {x.usd.sum():+8.1f} | avg {x.R1.mean():+.3f}R(1.5ATR) Nov-Jun {p.R1.mean():+.3f} Jul-Nov {q.R1.mean():+.3f} | random {(drw<Ra.sum()).mean():.1%} | worst trade {x.usd.min():+.1f}', flush=True)
