# Fifth batch: 10 TradingView indicators (author/built-in defaults). Same execution as earlier batches.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import ema, sma, atr
from ind10b import sar_trades, hold, cross_up, cross_dn
S = pd.Series
def gann_hilo(o, h, l, c, hp=13, lp=21):
    hi = np.r_[np.nan, sma(h, hp)[:-1]]; lo = np.r_[np.nan, sma(l, lp)[:-1]]
    return sar_trades(hold(np.where(c > hi, 1, np.where(c < lo, -1, 0))))
def lsma(o, h, l, c, n=25):
    x = np.arange(n, dtype=float); xm = x.mean(); w = (x - xm) / ((x - xm) ** 2).sum()
    slope = np.r_[np.full(n - 1, np.nan), np.convolve(c, w[::-1], 'valid')]; mean = sma(c, n)
    ls = mean + slope * (n - 1 - xm); return sar_trades(np.nan_to_num(np.sign(c - ls)))
def alma(x, n, off=0.85, sig=6):
    m = off * (n - 1); s = n / sig; w = np.exp(-((np.arange(n) - m) ** 2) / (2 * s * s)); w /= w.sum()
    return np.r_[np.full(n - 1, np.nan), np.convolve(x, w[::-1], 'valid')]
def trendilo(o, h, l, c, n=50):
    pch = np.r_[0, np.diff(c)] / c * 100; av = alma(pch, n); rms = np.sqrt(S(av ** 2).rolling(n).sum().values / n)
    return sar_trades(hold(np.where(av > rms, 1, np.where(av < -rms, -1, 0))))
def stc(o, h, l, c, cyc=10, fl=23, slw=50, f=0.5):
    m = ema(c, fl) - ema(c, slw); n = len(c); f1 = np.zeros(n); pf = np.zeros(n); f2 = np.zeros(n); pff = np.zeros(n)
    v1 = S(m).rolling(cyc).min().values; v2 = S(m).rolling(cyc).max().values - v1
    for i in range(n):
        f1[i] = (m[i] - v1[i]) / v2[i] * 100 if v2[i] > 0 else (f1[i - 1] if i else 0)
        pf[i] = pf[i - 1] + f * (f1[i] - pf[i - 1]) if i else f1[i]
    v3 = S(pf).rolling(cyc).min().values; v4 = S(pf).rolling(cyc).max().values - v3
    for i in range(n):
        f2[i] = (pf[i] - v3[i]) / v4[i] * 100 if v4[i] > 0 else (f2[i - 1] if i else 0)
        pff[i] = pff[i - 1] + f * (f2[i] - pff[i - 1]) if i else f2[i]
    return sar_trades(hold(np.where(cross_up(pff, np.full(n, 25.)), 1, np.where(cross_dn(pff, np.full(n, 75.)), -1, 0))))
def trix(o, h, l, c, n=18):
    t = ema(ema(ema(np.log(c), n), n), n); return sar_trades(np.sign(np.r_[0, np.diff(t)]))
def itrend(o, h, l, c, a=0.07):
    src = (h + l) / 2; n = len(c); it = np.zeros(n)
    for i in range(n):
        if i < 7: it[i] = (src[i] + 2 * src[max(i - 1, 0)] + src[max(i - 2, 0)]) / 4
        else: it[i] = (a - a * a / 4) * src[i] + 0.5 * a * a * src[i - 1] - (a - 0.75 * a * a) * src[i - 2] + 2 * (1 - a) * it[i - 1] - (1 - a) ** 2 * it[i - 2]
    trig = 2 * it - np.r_[it[0], it[0], it[:-2]]; return sar_trades(np.sign(trig - it))
def mcginley(o, h, l, c, n=14):
    mg = np.zeros(len(c)); mg[0] = c[0]
    for i in range(1, len(c)): mg[i] = mg[i - 1] + (c[i] - mg[i - 1]) / (n * (c[i] / mg[i - 1]) ** 4)
    return sar_trades(np.sign(c - mg))
def kst(o, h, l, c):
    roc = lambda k: (c / np.r_[np.full(k, c[0]), c[:-k]] - 1) * 100
    k = sma(roc(10), 10) + 2 * sma(roc(15), 10) + 3 * sma(roc(20), 10) + 4 * sma(roc(30), 15)
    return sar_trades(np.nan_to_num(np.sign(k - sma(k, 9))))
def laguerre(o, h, l, c, g=0.5):
    n = len(c); L = np.zeros((4, n)); lr = np.zeros(n)
    for i in range(n):
        p = L[:, i - 1] if i else np.full(4, c[0])
        L[0, i] = (1 - g) * c[i] + g * p[0]; L[1, i] = -g * L[0, i] + p[0] + g * p[1]
        L[2, i] = -g * L[1, i] + p[1] + g * p[2]; L[3, i] = -g * L[2, i] + p[2] + g * p[3]
        cu = max(L[0, i] - L[1, i], 0) + max(L[1, i] - L[2, i], 0) + max(L[2, i] - L[3, i], 0)
        cd = max(L[1, i] - L[0, i], 0) + max(L[2, i] - L[1, i], 0) + max(L[3, i] - L[2, i], 0)
        lr[i] = cu / (cu + cd) if cu + cd else (lr[i - 1] if i else 0.5)
    return sar_trades(hold(np.where(cross_up(lr, np.full(n, .2)), 1, np.where(cross_dn(lr, np.full(n, .8)), -1, 0))))
def jma(o, h, l, c, n=7, phase=50, power=2):
    pr = 0.5 if phase < -100 else (2.5 if phase > 100 else phase / 100 + 1.5)
    b = 0.45 * (n - 1) / (0.45 * (n - 1) + 2); a = b ** power; e0 = e1 = e2 = j = 0.0; out = np.zeros(len(c))
    for i in range(len(c)):
        e0 = (1 - a) * c[i] + a * e0; e1 = (c[i] - e0) * (1 - b) + b * e1
        e2 = (e0 + pr * e1 - j) * (1 - a) ** 2 + a * a * e2; j = e2 + j; out[i] = j
    return sar_trades(np.sign(np.r_[0, np.diff(out)]))
IND = dict(GannHiLo=gann_hilo, LSMA=lsma, Trendilo=trendilo, STC=stc, TRIX=trix, ITrend=itrend, McGinley=mcginley, KST=kst, LaguerreRSI=laguerre, JMA=jma)
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
            print(f'M{tf//60:<3} {name:12s} n={len(x):5d} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R | Nov-Jun {p.R.mean():+.3f} ({len(p)}) Jul-Nov {q.R.mean():+.3f} ({len(q)})', flush=True)
    pickle.dump(out, open('ind10e.pkl', 'wb'))
