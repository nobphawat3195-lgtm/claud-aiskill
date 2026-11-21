# 10 more TradingView indicators (author/built-in defaults). Signals on bar close (bid bars), entry next tick, SL 1.5 ATR(14).
# Each indicator returns (entries: list of (bar, dir, exit_bar)). SAR types exit at the next opposite signal.
import sys, os, time, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
from ind10 import ema, rma, sma, atr, rsi, tr_
S = pd.Series
def sar_trades(st):                                   # state array (+1/-1/0): enter on change, exit at next change
    ch = np.flatnonzero((st != np.r_[0, st[:-1]]) & (st != 0)); out = []
    for a, b in zip(ch, np.r_[ch[1:], len(st) - 1]): out.append((a, int(st[a]), b))
    return out
def hold(st):                                          # forward-fill non-zero signals into a state
    v = 0; o = np.zeros(len(st))
    for i, s in enumerate(st):
        if s: v = s
        o[i] = v
    return o
def cross_up(a, b): return np.r_[False, (a[1:] > b[1:]) & (a[:-1] <= b[:-1])]
def cross_dn(a, b): return cross_up(b, a)
def wavetrend(o, h, l, c):
    ap = (h + l + c) / 3; esa = ema(ap, 10); d = ema(np.abs(ap - esa), 10); ci = (ap - esa) / (0.015 * np.where(d == 0, 1e-9, d))
    w1 = ema(ci, 21); w2 = sma(w1, 4)
    return sar_trades(hold(np.where(cross_up(w1, w2) & (w1 < -53), 1, np.where(cross_dn(w1, w2) & (w1 > 53), -1, 0))))
def bb_strategy(o, h, l, c):
    b = sma(c, 20); sd = S(c).rolling(20).std(ddof=0).values; up, lo = b + 2 * sd, b - 2 * sd
    return sar_trades(hold(np.where(cross_up(c, lo), 1, np.where(cross_dn(c, up), -1, 0))))
def rsi2(o, h, l, c):
    r = rsi(c, 2); m200 = sma(c, 200); m5 = sma(c, 5); out = []; i = 200
    while i < len(c) - 1:
        d = 1 if (c[i] > m200[i] and r[i] < 10) else (-1 if (c[i] < m200[i] and r[i] > 90) else 0)
        if d:
            j = i + 1
            while j < len(c) - 1 and not ((d > 0 and c[j] > m5[j]) or (d < 0 and c[j] < m5[j])): j += 1
            out.append((i, d, j)); i = j
        i += 1
    return out
def stochrsi(o, h, l, c):
    r = rsi(c, 14); lo = S(r).rolling(14).min().values; hi = S(r).rolling(14).max().values
    k = sma(100 * (r - lo) / np.where(hi - lo == 0, 1e-9, hi - lo), 3); d = sma(k, 3)
    return sar_trades(hold(np.where(cross_up(k, d) & (k < 20), 1, np.where(cross_dn(k, d) & (k > 80), -1, 0))))
def donchian(o, h, l, c):
    hh = S(h).rolling(20).max().shift(1).values; ll = S(l).rolling(20).min().shift(1).values
    xl = S(l).rolling(10).min().shift(1).values; xh = S(h).rolling(10).max().shift(1).values; out = []; i = 21
    while i < len(c) - 1:
        d = 1 if c[i] > hh[i] else (-1 if c[i] < ll[i] else 0)
        if d:
            j = i + 1
            while j < len(c) - 1 and not ((d > 0 and c[j] < xl[j]) or (d < 0 and c[j] > xh[j])): j += 1
            out.append((i, d, j)); i = j
        i += 1
    return out
def macd(o, h, l, c):
    m = ema(c, 12) - ema(c, 26); hist = m - ema(m, 9); return sar_trades(np.sign(hist))
def psar(o, h, l, c, st=0.02, inc=0.02, mx=0.2):
    n = len(c); tr = np.zeros(n); up = True; af = st; ep = h[0]; s = l[0]
    for i in range(1, n):
        s = s + af * (ep - s)
        if up:
            s = min(s, l[i - 1], l[i - 2] if i > 1 else l[i - 1])
            if l[i] < s: up = False; s = ep; ep = l[i]; af = st
            elif h[i] > ep: ep = h[i]; af = min(af + inc, mx)
        else:
            s = max(s, h[i - 1], h[i - 2] if i > 1 else h[i - 1])
            if h[i] > s: up = True; s = ep; ep = h[i]; af = st
            elif l[i] < ep: ep = l[i]; af = min(af + inc, mx)
        tr[i] = 1 if up else -1
    return sar_trades(tr)
def smoothed_ha(o, h, l, c, n1=10, n2=10):
    O, H, L, C = ema(o, n1), ema(h, n1), ema(l, n1), ema(c, n1); hc = (O + H + L + C) / 4; ho = np.zeros(len(c)); ho[0] = (O[0] + C[0]) / 2
    for i in range(1, len(c)): ho[i] = (ho[i - 1] + hc[i - 1]) / 2
    return sar_trades(np.sign(ema(hc, n2) - ema(ho, n2)))
def dmi(o, h, l, c):
    up = np.r_[0, np.diff(h)]; dn = np.r_[0, -np.diff(l)]; pdm = np.where((up > dn) & (up > 0), up, 0); mdm = np.where((dn > up) & (dn > 0), dn, 0)
    a = rma(tr_(h, l, c), 14); p = 100 * rma(pdm, 14) / a; m = 100 * rma(mdm, 14) / a; adx = rma(100 * np.abs(p - m) / np.maximum(p + m, 1e-9), 14)
    return sar_trades(hold(np.where(cross_up(p, m) & (adx > 20), 1, np.where(cross_dn(p, m) & (adx > 20), -1, 0))))
def vixfix(o, h, l, c):
    hc = S(c).rolling(22).max().values; w = (hc - l) / hc * 100
    mid = sma(w, 20); ub = mid + 2 * S(w).rolling(20).std(ddof=0).values; rh = S(w).rolling(50).max().values * 0.85
    sig = (w >= ub) | (w >= rh); out = []; i = 60
    while i < len(c) - 11:
        if sig[i] and not sig[i - 1]: out.append((i, 1, i + 10)); i += 10
        i += 1
    return out
IND = dict(WaveTrend=wavetrend, BBStrategy=bb_strategy, RSI2=rsi2, StochRSI=stochrsi, Donchian=donchian, MACD=macd,
           PSAR=psar, SmoothHA=smoothed_ha, DMI=dmi, VixFix=vixfix)
if __name__ == '__main__':
    START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
    tt, tb, ta = load('20251002'); out = {}
    for tf in (300, 900, 3600):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values
        A = atr(H, L, C, 14); TS = m.ts.values + tf
        for name, fn in IND.items():
            t0 = time.time(); rows = []
            for a, d, b in fn(O, H, L, C):
                if TS[a] < START or np.isnan(A[a]): continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                rows.append(dict(setup=name, i=i, dir=d, sl=(ta[i] if d > 0 else tb[i]) - d * 1.5 * A[a], texit=TS[min(b, len(m) - 1)], ts=TS[a], S=1.5 * A[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']; out[(tf, name)] = x
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            print(f'M{tf//60:<3} {name:10s} n={len(x):5d} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+7.1f}R | Nov-Jun {p.R.mean():+.3f} ({len(p)}) Jul-Nov {q.R.mean():+.3f} ({len(q)}) | SLmed {x.S.median():5.1f} | {time.time()-t0:.0f}s', flush=True)
    pickle.dump(out, open('ind10b.pkl', 'wb'))
