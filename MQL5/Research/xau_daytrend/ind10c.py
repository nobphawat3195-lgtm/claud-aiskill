# Third batch: 10 TradingView indicators (author/built-in defaults). Same execution as ind10/ind10b.
import sys, os, time, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import ema, rma, sma, atr, tr_
from ind10b import sar_trades, hold, cross_up, cross_dn
S = pd.Series
def wma(x, n):
    w = np.arange(1, n + 1, dtype=float); y = np.convolve(x, w[::-1], 'full')[n - 1:len(x)] / w.sum(); return np.r_[np.full(n - 1, np.nan), y]
def hma(x, n): return wma(2 * wma(x, n // 2) - wma(x, n), int(round(np.sqrt(n))))
def hull_suite(o, h, l, c, n=55):
    m = hma(c, n); return sar_trades(np.nan_to_num(np.sign(m - np.r_[np.nan, np.nan, m[:-2]])))
def keltner(o, h, l, c, n=20, k=2.0, an=10):
    mid = ema(c, n); a = atr(h, l, c, an); up, lo = mid + k * a, mid - k * a
    return sar_trades(hold(np.where(cross_up(c, up), 1, np.where(cross_dn(c, lo), -1, 0))))
def aroon(o, h, l, c, n=14):
    hb = S(h).rolling(n + 1).apply(lambda a: n - (n - np.argmax(a)), raw=True).values
    lb = S(l).rolling(n + 1).apply(lambda a: n - (n - np.argmin(a)), raw=True).values
    up, dn = 100 * hb / n, 100 * lb / n
    return sar_trades(hold(np.where(cross_up(up, dn), 1, np.where(cross_dn(up, dn), -1, 0))))
def vortex(o, h, l, c, n=14):
    vp = np.abs(h - np.r_[l[0], l[:-1]]); vm = np.abs(l - np.r_[h[0], h[:-1]]); t = tr_(h, l, c)
    sp, sm, st = S(vp).rolling(n).sum().values, S(vm).rolling(n).sum().values, S(t).rolling(n).sum().values
    a, b = sp / st, sm / st
    return sar_trades(hold(np.where(cross_up(a, b), 1, np.where(cross_dn(a, b), -1, 0))))
def coral(o, h, l, c, sm=21, cd=0.4):
    di = (sm - 1) / 2 + 1; c1 = 2 / (di + 1); c2 = 1 - c1
    c3 = 3 * (cd * cd + cd ** 3); c4 = -3 * (2 * cd * cd + cd + cd ** 3); c5 = 3 * cd + 1 + cd ** 3 + 3 * cd * cd
    i = np.zeros((6, len(c))); bf = np.zeros(len(c))
    for t in range(len(c)):
        prev = i[:, t - 1] if t else np.zeros(6); src = c[t]
        for k in range(6): i[k, t] = c1 * src + c2 * prev[k]; src = i[k, t]
        bf[t] = -cd ** 3 * i[5, t] + c3 * i[4, t] + c4 * i[3, t] + c5 * i[2, t]
    return sar_trades(np.sign(np.r_[0, np.diff(bf)]))
def zlt(o, h, l, c, n=70, mult=1.2):
    lag = (n - 1) // 2; z = ema(c + (c - np.r_[np.full(lag, c[0]), c[:-lag]]), n)
    vol = S(atr(h, l, c, n)).rolling(n * 3).max().values * mult
    return sar_trades(hold(np.where(cross_up(c, z + vol), 1, np.where(cross_dn(c, z - vol), -1, 0))))
def pp_supertrend(o, h, l, c, prd=2, f=3.0, an=10):
    a = atr(h, l, c, an); n = len(c); center = np.nan; tu = np.zeros(n); td = np.zeros(n); tr = np.ones(n)
    for i in range(n):
        j = i - prd
        if j >= prd:
            if h[j] == h[j - prd:j + prd + 1].max(): center = h[j] if np.isnan(center) else (center * 2 + h[j]) / 3
            elif l[j] == l[j - prd:j + prd + 1].min(): center = l[j] if np.isnan(center) else (center * 2 + l[j]) / 3
        if np.isnan(center) or i == 0: tr[i] = tr[i - 1] if i else 1; continue
        up, dn = center - f * a[i], center + f * a[i]
        tu[i] = max(up, tu[i - 1]) if c[i - 1] > tu[i - 1] else up
        td[i] = min(dn, td[i - 1]) if c[i - 1] < td[i - 1] and td[i - 1] else dn
        tr[i] = 1 if c[i] > td[i - 1] and td[i - 1] else (-1 if c[i] < tu[i - 1] else tr[i - 1])
    return sar_trades(tr)
def fisher(o, h, l, c, n=9):
    hl = (h + l) / 2; mx = S(hl).rolling(n).max().values; mn = S(hl).rolling(n).min().values
    v = 0.0; fi = np.zeros(len(c))
    for i in range(len(c)):
        if np.isnan(mx[i]) or mx[i] == mn[i]: fi[i] = fi[i - 1] if i else 0; continue
        v = 0.66 * ((hl[i] - mn[i]) / (mx[i] - mn[i]) - 0.5) + 0.67 * v; v = min(max(v, -0.999), 0.999)
        fi[i] = 0.5 * np.log((1 + v) / (1 - v)) + 0.5 * (fi[i - 1] if i else 0)
    return sar_trades(np.sign(fi - np.r_[0, fi[:-1]]))
def kama(o, h, l, c, n=10, fast=2, slow=30):
    ch = np.abs(c - np.r_[np.full(n, c[0]), c[:-n]]); vo = S(np.abs(np.diff(c, prepend=c[0]))).rolling(n).sum().values
    er = np.where(vo > 0, ch / vo, 0); sc = (er * (2 / (fast + 1) - 2 / (slow + 1)) + 2 / (slow + 1)) ** 2
    k = np.zeros(len(c)); k[0] = c[0]
    for i in range(1, len(c)): k[i] = k[i - 1] + (0 if np.isnan(sc[i]) else sc[i]) * (c[i] - k[i - 1])
    return sar_trades(np.sign(c - k))
def cci(o, h, l, c, n=20):
    tp = (h + l + c) / 3; m = sma(tp, n); md = S(tp).rolling(n).apply(lambda a: np.abs(a - a.mean()).mean(), raw=True).values
    x = (tp - m) / (0.015 * md)
    return sar_trades(hold(np.where(cross_up(x, np.full(len(x), 100.0)), 1, np.where(cross_dn(x, np.full(len(x), -100.0)), -1, 0))))
IND = dict(HullSuite=hull_suite, Keltner=keltner, Aroon=aroon, Vortex=vortex, Coral=coral, ZeroLagTrend=zlt,
           PivotSuperTrend=pp_supertrend, Fisher=fisher, KAMA=kama, CCI=cci)
if __name__ == '__main__':
    START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
    tt, tb, ta = load('20251002'); out = {}
    for tf in (300, 900, 3600):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values
        A = atr(H, L, C, 14); TS = m.ts.values + tf
        for name, fn in IND.items():
            t0 = time.time(); rows = []
            for a, d, b in fn(O, H, L, C):
                if TS[a] < START or np.isnan(A[a]) or d == 0: continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                rows.append(dict(setup=name, i=i, dir=int(d), sl=(ta[i] if d > 0 else tb[i]) - d * 1.5 * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], S=1.5 * A[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']; out[(tf, name)] = x
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            print(f'M{tf//60:<3} {name:15s} n={len(x):5d} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+7.1f}R | Nov-Jun {p.R.mean():+.3f} ({len(p)}) Jul-Nov {q.R.mean():+.3f} ({len(q)}) | {time.time()-t0:.0f}s', flush=True)
    pickle.dump(out, open('ind10c.pkl', 'wb'))
