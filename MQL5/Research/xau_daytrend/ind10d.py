# Fourth batch: 10 TradingView indicators (author/built-in defaults). Same execution as earlier batches.
import sys, os, time, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import ema, rma, sma, atr, rsi, tr_
from ind10b import sar_trades, hold, cross_up, cross_dn
from ind10c import wma
S = pd.Series
def trend_magic(o, h, l, c, n=20):
    tp = c; m = sma(tp, n); md = S(tp).rolling(n).apply(lambda a: np.abs(a - a.mean()).mean(), raw=True).values
    cc = (tp - m) / (0.015 * md); return sar_trades(np.nan_to_num(np.sign(cc)))
def ott(o, h, l, c, n=2, pct=1.4):
    a = 2 / (n + 1); d = np.diff(c, prepend=c[0]); ud = S(np.maximum(d, 0)).rolling(9).sum().values; dd = S(np.maximum(-d, 0)).rolling(9).sum().values
    cmo = np.nan_to_num((ud - dd) / np.where(ud + dd == 0, 1, ud + dd)); v = np.zeros(len(c)); v[0] = c[0]
    for i in range(1, len(c)): k = a * abs(cmo[i]); v[i] = k * c[i] + (1 - k) * v[i - 1]
    ls = np.zeros(len(c)); ss = np.zeros(len(c)); dr = np.ones(len(c)); o_ = np.zeros(len(c))
    for i in range(len(c)):
        f = v[i] * pct * 0.01; l0, s0 = v[i] - f, v[i] + f
        if i: l0 = max(l0, ls[i - 1]) if v[i] > ls[i - 1] else l0; s0 = min(s0, ss[i - 1]) if v[i] < ss[i - 1] else s0
        ls[i], ss[i] = l0, s0
        if i: dr[i] = 1 if dr[i - 1] == -1 and v[i] > ss[i - 1] else (-1 if dr[i - 1] == 1 and v[i] < ls[i - 1] else dr[i - 1])
        mt = ls[i] if dr[i] == 1 else ss[i]; o_[i] = mt * (200 + pct) / 200 if v[i] > mt else mt * (200 - pct) / 200
    o2 = np.r_[o_[0], o_[0], o_[:-2]]; return sar_trades(np.sign(v - o2))
def alphatrend(o, h, l, c, n=14, coeff=1.0):
    a = sma(tr_(h, l, c), n); r = rsi(c, n); at = np.zeros(len(c))
    for i in range(len(c)):
        if np.isnan(a[i]): at[i] = c[i]; continue
        up, dn = l[i] - a[i] * coeff, h[i] + a[i] * coeff; p = at[i - 1]
        at[i] = (p if up < p else up) if r[i] >= 50 else (p if dn > p else dn)
    a2 = np.r_[at[0], at[0], at[:-2]]
    return sar_trades(hold(np.where(cross_up(at, a2), 1, np.where(cross_dn(at, a2), -1, 0))))
def mavilimw(o, h, l, c):
    m = c
    for n in (3, 5, 8, 13, 21, 34): m = wma(np.nan_to_num(m, nan=c[0]), n)
    return sar_trades(np.nan_to_num(np.sign(m - np.r_[m[0], m[:-1]])))
def elder(o, h, l, c):
    e = ema(c, 13); mc = ema(c, 12) - ema(c, 26); hi = mc - ema(mc, 9)
    es, hs = np.sign(np.r_[0, np.diff(e)]), np.sign(np.r_[0, np.diff(hi)])
    return sar_trades(hold(np.where((es > 0) & (hs > 0), 1, np.where((es < 0) & (hs < 0), -1, 0))))
def smma(x, n): return rma(x, n)
def alligator(o, h, l, c):
    m = (h + l) / 2; sh = lambda x, k: np.r_[np.full(k, x[0]), x[:-k]]
    jaw, teeth, lips = sh(smma(m, 13), 8), sh(smma(m, 8), 5), sh(smma(m, 5), 3)
    return sar_trades(hold(np.where((lips > teeth) & (teeth > jaw), 1, np.where((lips < teeth) & (teeth < jaw), -1, 0))))
def t3(o, h, l, c, n=5, b=0.7):
    e1 = ema(c, n); e2 = ema(e1, n); e3 = ema(e2, n); e4 = ema(e3, n); e5 = ema(e4, n); e6 = ema(e5, n)
    c1 = -b ** 3; c2 = 3 * b * b + 3 * b ** 3; c3 = -6 * b * b - 3 * b - 3 * b ** 3; c4 = 1 + 3 * b + b ** 3 + 3 * b * b
    t = c1 * e6 + c2 * e5 + c3 * e4 + c4 * e3; return sar_trades(np.sign(np.r_[0, np.diff(t)]))
def volstop(o, h, l, c, n=20, mult=2.0):
    a = atr(h, l, c, n) * mult; up = True; mx = c[0]; mn = c[0]; st = c[0]; tr = np.ones(len(c))
    for i in range(1, len(c)):
        mx, mn = max(mx, c[i]), min(mn, c[i])
        st = max(st, mx - a[i]) if up else min(st, mn + a[i])
        if up and c[i] < st: up = False; mn = c[i]; st = c[i] + a[i]
        elif not up and c[i] > st: up = True; mx = c[i]; st = c[i] - a[i]
        tr[i] = 1 if up else -1
    return sar_trades(tr)
def bb_break(o, h, l, c, n=20, k=2.0):
    b = sma(c, n); sd = S(c).rolling(n).std(ddof=0).values
    return sar_trades(hold(np.where(c > b + k * sd, 1, np.where(c < b - k * sd, -1, 0))))
def rsi50(o, h, l, c, n=14): return sar_trades(np.sign(rsi(c, n) - 50))
IND = dict(TrendMagic=trend_magic, OTT=ott, AlphaTrend=alphatrend, MavilimW=mavilimw, ElderImpulse=elder, Alligator=alligator,
           T3=t3, VolStop=volstop, BBBreakout=bb_break, RSI50=rsi50)
if __name__ == '__main__':
    START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
    tt, tb, ta = load('20251002'); out = {}
    for tf in (300, 900, 3600):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values
        A = atr(H, L, C, 14); TS = m.ts.values + tf
        for name, fn in IND.items():
            rows = []
            for a, d, b in fn(O, H, L, C):
                if TS[a] < START or np.isnan(A[a]) or d == 0: continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                rows.append(dict(setup=name, i=i, dir=int(d), sl=(ta[i] if d > 0 else tb[i]) - d * 1.5 * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], S=1.5 * A[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']; out[(tf, name)] = x
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            print(f'M{tf//60:<3} {name:13s} n={len(x):5d} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R | Nov-Jun {p.R.mean():+.3f} ({len(p)}) Jul-Nov {q.R.mean():+.3f} ({len(q)})', flush=True)
    pickle.dump(out, open('ind10d.pkl', 'wb'))
