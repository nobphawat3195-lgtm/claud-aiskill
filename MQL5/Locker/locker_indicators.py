# XAU indicator LOCKER — self-contained Python ports of every indicator that passed the XAUUSD tests (2026-11-20).
# Each function takes numpy arrays (o, h, l, c) of CLOSED bars and returns trades as a list of (entry_bar, dir, exit_bar)
# or an event array (+1/-1 at flips). Rules used in all tests: enter next tick after the signal bar closes, SL 1.5 x ATR(14),
# exit/reverse on the opposite signal, no TP. Status and best timeframe: see LOCKER.md.
import numpy as np, pandas as pd
S = pd.Series
def ema(x, n): return S(x).ewm(span=n, adjust=False).mean().values
def rma(x, n): return S(x).ewm(alpha=1 / n, adjust=False).mean().values
def sma(x, n): return S(x).rolling(n).mean().values
def tr_(h, l, c): pc = np.r_[c[0], c[:-1]]; return np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
def atr(h, l, c, n): return rma(tr_(h, l, c), n)
def wma(x, n):
    w = np.arange(1, n + 1); return S(x).rolling(n).apply(lambda a: (a * w).sum() / w.sum(), raw=True).values
def hma(x, n): return wma(2 * wma(x, n // 2) - wma(x, n), int(np.sqrt(n)))
def flips(state):                                   # +1/-1 events where state changes to a new non-zero value
    ev = np.zeros(len(state)); prev = 0
    for i, s in enumerate(state):
        if s != 0 and s != prev: ev[i] = s; prev = s
    return ev
def cross_up(a, b): return np.r_[False, (a[1:] > b[1:]) & (a[:-1] <= b[:-1])]
def cross_dn(a, b): return cross_up(b, a)
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
def ssl_hybrid(h, l, c, n=60):
    eh, el = hma(h, n), hma(l, n); s = np.zeros(len(c)); v = 0
    for i in range(len(c)):
        if not np.isnan(eh[i]):
            v = 1 if c[i] > eh[i] else (-1 if c[i] < el[i] else v)
        s[i] = v
    return flips(s)
def kst(o, h, l, c):
    roc = lambda k: (c / np.r_[np.full(k, c[0]), c[:-k]] - 1) * 100
    k = sma(roc(10), 10) + 2 * sma(roc(15), 10) + 3 * sma(roc(20), 10) + 4 * sma(roc(30), 15)
    return sar_trades(np.nan_to_num(np.sign(k - sma(k, 9))))
def coral(o, h, l, c, sm=21, cd=0.4):
    di = (sm - 1) / 2 + 1; c1 = 2 / (di + 1); c2 = 1 - c1
    c3 = 3 * (cd * cd + cd ** 3); c4 = -3 * (2 * cd * cd + cd + cd ** 3); c5 = 3 * cd + 1 + cd ** 3 + 3 * cd * cd
    i = np.zeros((6, len(c))); bf = np.zeros(len(c))
    for t in range(len(c)):
        prev = i[:, t - 1] if t else np.zeros(6); src = c[t]
        for k in range(6): i[k, t] = c1 * src + c2 * prev[k]; src = i[k, t]
        bf[t] = -cd ** 3 * i[5, t] + c3 * i[4, t] + c4 * i[3, t] + c5 * i[2, t]
    return sar_trades(np.sign(np.r_[0, np.diff(bf)]))
def gann_hilo(o, h, l, c, hp=13, lp=21):
    hi = np.r_[np.nan, sma(h, hp)[:-1]]; lo = np.r_[np.nan, sma(l, lp)[:-1]]
    return sar_trades(hold(np.where(c > hi, 1, np.where(c < lo, -1, 0))))
def itrend(o, h, l, c, a=0.07):
    src = (h + l) / 2; n = len(c); it = np.zeros(n)
    for i in range(n):
        if i < 7: it[i] = (src[i] + 2 * src[max(i - 1, 0)] + src[max(i - 2, 0)]) / 4
        else: it[i] = (a - a * a / 4) * src[i] + 0.5 * a * a * src[i - 1] - (a - 0.75 * a * a) * src[i - 2] + 2 * (1 - a) * it[i - 1] - (1 - a) ** 2 * it[i - 2]
    trig = 2 * it - np.r_[it[0], it[0], it[:-2]]; return sar_trades(np.sign(trig - it))
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
def macd(o, h, l, c):
    m = ema(c, 12) - ema(c, 26); hist = m - ema(m, 9); return sar_trades(np.sign(hist))
def aroon(o, h, l, c, n=14):
    hb = S(h).rolling(n + 1).apply(lambda a: n - (n - np.argmax(a)), raw=True).values
    lb = S(l).rolling(n + 1).apply(lambda a: n - (n - np.argmin(a)), raw=True).values
    up, dn = 100 * hb / n, 100 * lb / n
    return sar_trades(hold(np.where(cross_up(up, dn), 1, np.where(cross_dn(up, dn), -1, 0))))
def cci(o, h, l, c, n=20):
    tp = (h + l + c) / 3; m = sma(tp, n); md = S(tp).rolling(n).apply(lambda a: np.abs(a - a.mean()).mean(), raw=True).values
    x = (tp - m) / (0.015 * md)
    return sar_trades(hold(np.where(cross_up(x, np.full(len(x), 100.0)), 1, np.where(cross_dn(x, np.full(len(x), -100.0)), -1, 0))))
def hma_round(x, n):                                 # Hull Suite test used round(sqrt(n)) and a convolution WMA
    w = np.arange(1, n + 1, dtype=float); f = lambda v, k: np.r_[np.full(k - 1, np.nan), np.convolve(v, np.arange(k, 0, -1.0), 'full')[k - 1:len(v)] / (k * (k + 1) / 2)]
    return f(2 * f(x, n // 2) - f(x, n), int(round(np.sqrt(n))))
def hull_suite(o, h, l, c, n=55):
    m = hma_round(c, n); return sar_trades(np.nan_to_num(np.sign(m - np.r_[np.nan, np.nan, m[:-2]])))
