# 10 popular TradingView buy/sell indicators (author defaults), signals on bar close (bid bars), common execution:
# entry next tick (ask/bid), SL 1.5 x ATR(14), exit on the opposite signal (stop-and-reverse) or SL. Latest year, real ticks.
import sys, os, time, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
S = pd.Series
def ema(x, n): return S(x).ewm(span=n, adjust=False).mean().values
def rma(x, n): return S(x).ewm(alpha=1 / n, adjust=False).mean().values
def sma(x, n): return S(x).rolling(n).mean().values
def tr_(h, l, c): pc = np.r_[c[0], c[:-1]]; return np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
def atr(h, l, c, n): return rma(tr_(h, l, c), n)
def rsi(c, n):
    d = np.diff(c, prepend=c[0]); u = rma(np.maximum(d, 0), n); v = rma(np.maximum(-d, 0), n)
    return 100 - 100 / (1 + u / np.where(v == 0, 1e-12, v))
def wma(x, n):
    w = np.arange(1, n + 1); return S(x).rolling(n).apply(lambda a: (a * w).sum() / w.sum(), raw=True).values
def hma(x, n): return wma(2 * wma(x, n // 2) - wma(x, n), int(np.sqrt(n)))
def flips(state):                                   # +1/-1 events where state changes to a new non-zero value
    ev = np.zeros(len(state)); prev = 0
    for i, s in enumerate(state):
        if s != 0 and s != prev: ev[i] = s; prev = s
    return ev
def ut_bot(h, l, c, a=1, n=10):
    nl = a * atr(h, l, c, n); tr = np.zeros(len(c)); ev = np.zeros(len(c))
    for i in range(1, len(c)):
        p = tr[i - 1]
        if c[i] > p and c[i - 1] > p: tr[i] = max(p, c[i] - nl[i])
        elif c[i] < p and c[i - 1] < p: tr[i] = min(p, c[i] + nl[i])
        else: tr[i] = c[i] - nl[i] if c[i] > p else c[i] + nl[i]
        if c[i] > tr[i] and c[i - 1] <= tr[i - 1]: ev[i] = 1
        elif c[i] < tr[i] and c[i - 1] >= tr[i - 1]: ev[i] = -1
    return ev
def supertrend(h, l, c, n=10, m=3):
    src = (h + l) / 2; a = atr(h, l, c, n); up = src - m * a; dn = src + m * a; t = np.ones(len(c)); 
    for i in range(1, len(c)):
        u1, d1 = up[i - 1], dn[i - 1]
        if c[i - 1] > u1: up[i] = max(up[i], u1)
        if c[i - 1] < d1: dn[i] = min(dn[i], d1)
        t[i] = 1 if t[i - 1] == -1 and c[i] > d1 else (-1 if t[i - 1] == 1 and c[i] < u1 else t[i - 1])
    return flips(t)
def smoothrng(x, t, m): return ema(ema(np.abs(np.diff(x, prepend=x[0])), t), t * 2 - 1) * m
def rngfilt_sig(c, r):
    f = np.zeros(len(c)); f[0] = c[0]; up = dn = 0; cond = 0; ev = np.zeros(len(c))
    for i in range(1, len(c)):
        p = f[i - 1]
        f[i] = (p if c[i] - r[i] < p else c[i] - r[i]) if c[i] > p else (p if c[i] + r[i] > p else c[i] + r[i])
        if f[i] > p: up += 1; dn = 0
        elif f[i] < p: dn += 1; up = 0
        lc = c[i] > f[i] and c[i] != c[i - 1] and up > 0; sc = c[i] < f[i] and c[i] != c[i - 1] and dn > 0
        new = 1 if lc else (-1 if sc else cond)
        if new != cond and new != 0: ev[i] = new
        cond = new
    return ev
def range_filter(h, l, c): return rngfilt_sig(c, smoothrng(c, 100, 3.0))
def twin_range(h, l, c): return rngfilt_sig(c, (smoothrng(c, 27, 1.6) + smoothrng(c, 55, 2.0)) / 2)
def chandelier(h, l, c, n=22, m=3):
    a = m * atr(h, l, c, n); hh = S(c).rolling(n).max().values - a; ll = S(c).rolling(n).min().values + a
    ls, ss = hh.copy(), ll.copy(); d = np.ones(len(c))
    for i in range(1, len(c)):
        lp = ls[i - 1] if not np.isnan(ls[i - 1]) else ls[i]; sp = ss[i - 1] if not np.isnan(ss[i - 1]) else ss[i]
        if c[i - 1] > lp: ls[i] = max(ls[i], lp)
        if c[i - 1] < sp: ss[i] = min(ss[i], sp)
        d[i] = 1 if c[i] > sp else (-1 if c[i] < lp else d[i - 1])
    return flips(d)
def halftrend(h, l, c, amp=2, dev=2):
    hp = S(h).rolling(amp).max().values; lp = S(l).rolling(amp).min().values; hm = sma(h, amp); lm = sma(l, amp)
    trend = 0; nxt = 0; maxl = l[0]; minh = h[0]; st = np.zeros(len(c))
    for i in range(1, len(c)):
        if np.isnan(hp[i]) or np.isnan(hm[i]): continue
        if nxt == 1:
            maxl = max(lp[i], maxl)
            if hm[i] < maxl and c[i] < l[i - 1]: trend = 1; nxt = 0; minh = hp[i]
        else:
            minh = min(hp[i], minh)
            if lm[i] > minh and c[i] > h[i - 1]: trend = 0; nxt = 1; maxl = lp[i]
        st[i] = 1 if trend == 0 else -1
    return flips(st)
def ssl_hybrid(h, l, c, n=60):
    eh, el = hma(h, n), hma(l, n); s = np.zeros(len(c)); v = 0
    for i in range(len(c)):
        if not np.isnan(eh[i]):
            v = 1 if c[i] > eh[i] else (-1 if c[i] < el[i] else v)
        s[i] = v
    return flips(s)
def qqe_line(c, rp=6, sf=5, q=3.0):
    wp = rp * 2 - 1; rm = ema(rsi(c, rp), sf); ar = np.abs(np.diff(rm, prepend=rm[0])); dar = ema(ema(ar, wp), wp) * q
    lb = np.zeros(len(c)); sb = np.zeros(len(c)); tr = np.ones(len(c)); tl = np.zeros(len(c))
    for i in range(1, len(c)):
        nl, ns = rm[i] - dar[i], rm[i] + dar[i]
        lb[i] = max(lb[i - 1], nl) if rm[i - 1] > lb[i - 1] and rm[i] > lb[i - 1] else nl
        sb[i] = min(sb[i - 1], ns) if rm[i - 1] < sb[i - 1] and rm[i] < sb[i - 1] else ns
        up = (rm[i] > sb[i - 1]) != (rm[i - 1] > sb[i - 1] if i > 1 else rm[i - 1] > sb[i - 1]) and rm[i] > sb[i - 1]
        x1 = (lb[i - 1] > rm[i]) and (lb[i - 2] <= rm[i - 1] if i > 1 else False)
        tr[i] = 1 if (rm[i] > sb[i - 1] and rm[i - 1] <= (sb[i - 2] if i > 1 else sb[i - 1])) else (-1 if x1 else tr[i - 1])
        tl[i] = lb[i] if tr[i] == 1 else sb[i]
    return rm, tl
def qqe_mod(h, l, c):
    rm1, tl1 = qqe_line(c, 6, 5, 3.0); rm2, _ = qqe_line(c, 6, 5, 1.61)
    x = tl1 - 50; basis = sma(x, 50); dv = 0.35 * S(x).rolling(50).std(ddof=0).values
    g = (rm2 - 50 > 3) & (rm1 - 50 > basis + dv); r = (rm2 - 50 < -3) & (rm1 - 50 < basis - dv)
    return flips(np.where(g, 1, np.where(r, -1, 0)))
def squeeze(h, l, c, n=20):
    b = sma(c, n); sd = S(c).rolling(n).std(ddof=0).values; kr = sma(tr_(h, l, c), n)
    on = (b - 2 * sd > b - 1.5 * kr) & (b + 2 * sd < b + 1.5 * kr); off = (b - 2 * sd < b - 1.5 * kr) & (b + 2 * sd > b + 1.5 * kr)
    y = c - ((S(h).rolling(n).max().values + S(l).rolling(n).min().values) / 2 + b) / 2
    xs = np.arange(n); val = S(y).rolling(n).apply(lambda a: np.polyval(np.polyfit(xs, a, 1), n - 1), raw=True).values
    ev = np.zeros(len(c)); pos = 0
    for i in range(1, len(c)):
        if off[i] and on[i - 1] and not np.isnan(val[i]): pos = 1 if val[i] > 0 else -1; ev[i] = pos
        elif pos != 0 and np.sign(val[i]) == -pos: ev[i] = 9; pos = 0          # 9 = exit only (momentum turned)
    return ev
def lorentzian(h, l, c, nb=8, mbb=2000):
    hlc3 = (h + l + c) / 3
    def norm(x):
        lo = np.minimum.accumulate(np.nan_to_num(x, nan=np.inf)); hi = np.maximum.accumulate(np.nan_to_num(x, nan=-np.inf))
        return (x - lo) / np.maximum(hi - lo, 1e-10)
    esa = ema(hlc3, 10); de = ema(np.abs(hlc3 - esa), 10); w1 = ema((hlc3 - esa) / (0.015 * de), 11); w2 = sma(w1, 4)
    tp = hlc3; md = S(tp).rolling(20).apply(lambda a: np.abs(a - a.mean()).mean(), raw=True).values
    cci = (tp - sma(tp, 20)) / (0.015 * md)
    up = np.r_[0, np.diff(h)]; dn = np.r_[0, -np.diff(l)]; pdm = np.where((up > dn) & (up > 0), up, 0); mdm = np.where((dn > up) & (dn > 0), dn, 0)
    a20 = rma(tr_(h, l, c), 20); pdi = 100 * rma(pdm, 20) / a20; mdi = 100 * rma(mdm, 20) / a20
    adx = rma(100 * np.abs(pdi - mdi) / np.maximum(pdi + mdi, 1e-10), 20)
    F = np.nan_to_num(np.column_stack([rsi(c, 14) / 100, norm(w1 - w2), norm(cci), adx / 100, rsi(c, 9) / 100]))
    y = np.r_[np.zeros(4), np.sign(c[4:] - c[:-4])]                     # label: price direction over the last 4 bars
    # filters: volatility (ATR1 > ATR10), regime (KLMF slope >= -0.1), kernel regression (h=8, r=8, start 25) rising
    vol = atr(h, l, c, 1) > atr(h, l, c, 10)
    src = (h + l + c + c) / 4; o4 = src; v1 = np.zeros(len(c)); v2 = np.zeros(len(c)); k = np.zeros(len(c)); k[0] = o4[0]
    for i in range(1, len(c)):
        v1[i] = 0.2 * (o4[i] - o4[i - 1]) + 0.8 * v1[i - 1]; v2[i] = 0.1 * (h[i] - l[i]) + 0.8 * v2[i - 1]
        om = abs(v1[i] / v2[i]) if v2[i] else 0; al = (-om ** 2 + np.sqrt(om ** 4 + 16 * om ** 2)) / 8; k[i] = al * o4[i] + (1 - al) * k[i - 1]
    sl_ = np.abs(np.diff(k, prepend=k[0])); es = ema(sl_, 200); reg = (sl_ - es) / np.where(es == 0, 1e-10, es) >= -0.1
    wk = (1 + np.arange(27) ** 2 / (8 ** 2 * 2 * 8)) ** -8.0
    yh = np.convolve(c, wk, 'full')[:len(c)] / np.convolve(np.ones(len(c)), wk, 'full')[:len(c)]
    bull = np.r_[False, yh[1:] > yh[:-1]]; bear = np.r_[False, yh[1:] < yh[:-1]]
    sig = np.zeros(len(c)); s = 0; ev = np.zeros(len(c))
    for i in range(30, len(c)):
        lo = max(0, i - mbb); X = F[lo:i]; Y = y[lo:i]                        # history before bar i
        d = np.log1p(np.abs(X - F[i])).sum(1)
        last = -1.0; ds = []; ls = []
        for j in range(len(d)):
            if d[j] >= last and j % 4:
                last = d[j]; ds.append(d[j]); ls.append(Y[j])
                if len(ds) > nb: last = ds[round(nb * 3 / 4)]; ds.pop(0); ls.pop(0)
        pred = sum(ls); fa = vol[i] and reg[i]
        ns = 1 if pred > 0 and fa else (-1 if pred < 0 and fa else s)
        if ns != s and ns != 0 and ((ns == 1 and bull[i]) or (ns == -1 and bear[i])): ev[i] = ns
        s = ns
    return ev
IND = dict(UTBot=ut_bot, SuperTrend=supertrend, RangeFilter=range_filter, TwinRange=twin_range, Chandelier=chandelier,
           HalfTrend=halftrend, SSLHybrid=ssl_hybrid, QQEMod=qqe_mod, Squeeze=squeeze, Lorentzian=lorentzian)
if __name__ == '__main__':
    START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
    tt, tb, ta = load('20251002'); out = {}
    for tf in (300, 900, 3600):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); H, L, C = m.h.values, m.l.values, m.c.values
        A = atr(H, L, C, 14); TS = m.ts.values + tf
        for name, fn in IND.items():
            if name == 'Lorentzian' and tf == 300: continue                 # too slow on M5 in Python; M15/H1 only
            t0 = time.time(); ev = fn(H, L, C)
            idx = [i for i in np.flatnonzero(ev) if TS[i] >= START]
            rows = []
            for a, b in zip(idx, idx[1:] + [len(m) - 1]):
                if ev[a] == 9: continue
                i = int(np.searchsorted(tt, TS[a])); d = int(ev[a])
                if i >= len(tt) - 2: continue
                rows.append(dict(setup=name, i=i, dir=d, sl=(ta[i] if d > 0 else tb[i]) - d * 1.5 * A[a], texit=TS[b], ts=TS[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']); x['R'] = x['r0.0']; x['S'] = 1.5 * A[[int(np.searchsorted(TS, t)) for t in x.ts]]
            out[(tf, name)] = x
            a_, b_ = x[x.ts < SPLIT], x[x.ts >= SPLIT]
            print(f'M{tf//60:<3} {name:11s} n={len(x):5d} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+7.1f}R | Nov-Jun {a_.R.mean():+.3f} ({len(a_)}) Jul-Nov {b_.R.mean():+.3f} ({len(b_)}) | SLmed {x.S.median():5.1f} | {time.time()-t0:.0f}s', flush=True)
    pickle.dump(out, open('ind10.pkl', 'wb'))
