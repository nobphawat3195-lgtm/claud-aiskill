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

# ---- Batch 6 (2026-11-21): PMO, Awesome Oscillator, TSI, MAMA/FAMA (passed) + Ichimoku, Chande Kroll, MA Cross (grade C) ----
hh = lambda x, n: S(x).rolling(n).max().values
ll = lambda x, n: S(x).rolling(n).min().values
def st(x): return sar_trades(np.nan_to_num(np.sign(x)))

def ichimoku(o, h, l, c, a=9, b=26, d=52):                        # TradingView built-in Ichimoku Cloud
    tk, kj = (hh(h, a) + ll(l, a)) / 2, (hh(h, b) + ll(l, b)) / 2
    sa, sb = (tk + kj) / 2, (hh(h, d) + ll(l, d)) / 2
    ca, cb = np.r_[np.full(b - 1, np.nan), sa[:-(b - 1)]], np.r_[np.full(b - 1, np.nan), sb[:-(b - 1)]]   # cloud displaced 26 bars (offset 25)
    top, bot = np.fmax(ca, cb), np.fmin(ca, cb)
    return sar_trades(hold(np.where((c > top) & (tk > kj), 1, np.where((c < bot) & (tk < kj), -1, 0))))
def awesome(o, h, l, c):                                          # Bill Williams Awesome Oscillator zero line
    m = (h + l) / 2; return st(sma(m, 5) - sma(m, 34))
def tsi(o, h, l, c, r=25, s=13, g=13):                             # True Strength Index vs signal
    m = np.diff(c, prepend=c[0]); t = 100 * ema(ema(m, r), s) / np.where(ema(ema(abs(m), r), s) == 0, 1, ema(ema(abs(m), r), s))
    return st(t - ema(t, g))
def pmo(o, h, l, c, a=35, b=20, g=10):                             # DecisionPoint Price Momentum Oscillator vs signal
    roc = np.r_[0, c[1:] / c[:-1] - 1] * 100
    cs = lambda x, n: S(x).ewm(alpha=2 / n, adjust=False).mean().values
    p = cs(10 * cs(roc, a), b); return st(p - ema(p, g))
def rvi(o, h, l, c, n=10):                                         # Relative Vigor Index vs signal
    sw = lambda x: (x + 2 * np.r_[x[0], x[:-1]] + 2 * np.r_[x[:2], x[:-2]] + np.r_[x[:3], x[:-3]]) / 6
    num, den = S(sw(c - o)).rolling(n).sum().values, S(sw(h - l)).rolling(n).sum().values
    r = num / np.where(den == 0, 1e-9, den); return st(r - sw(r))
def andean(o, h, l, c, n=50, g=9):                                  # alexgrover Andean Oscillator: bull vs bear
    a = 2 / (n + 1); N = len(c); u1 = u2 = d1 = d2 = None; bull = np.zeros(N); bear = np.zeros(N)
    for i in range(N):
        C, O = c[i], o[i]
        if i == 0: u1 = d1 = C; u2 = d2 = C * C
        u1 = max(C, O, u1 - (u1 - C) * a); u2 = max(C * C, O * O, u2 - (u2 - C * C) * a)
        d1 = min(C, O, d1 + (C - d1) * a); d2 = min(C * C, O * O, d2 + (C * C - d2) * a)
        bull[i] = np.sqrt(max(d2 - d1 * d1, 0)); bear[i] = np.sqrt(max(u2 - u1 * u1, 0))
    return st(bull - bear)
def chande_kroll(o, h, l, c, p=10, x=1, q=9):                      # Chande Kroll Stop (built-in): close beyond both stops
    a = rma(np.maximum(h - l, np.maximum(abs(h - np.r_[c[0], c[:-1]]), abs(l - np.r_[c[0], c[:-1]]))), p)
    ss, sl_ = hh(hh(h, p) - x * a, q), ll(ll(l, p) + x * a, q)
    return sar_trades(hold(np.where((c > ss) & (c > sl_), 1, np.where((c < ss) & (c < sl_), -1, 0))))
def nadaraya(o, h, l, c, hb=8.0, r=8.0, x0=25, W=200):             # jdehorty Nadaraya-Watson rational quadratic kernel, colour change
    w = (1 + np.arange(W) ** 2 / (hb ** 2 * 2 * r)) ** -r
    y = np.convolve(c, w, 'full')[:len(c)] / np.convolve(np.ones(len(c)), w, 'full')[:len(c)]; y[:x0] = np.nan
    return st(np.r_[0, np.diff(y)])
def ma_cross(o, h, l, c, f=9, s=18):                               # built-in strategy "MovingAvg2Line Cross"
    return st(sma(c, f) - sma(c, s))
def mama(o, h, l, c, fl=0.5, sl=0.05):                             # Ehlers MESA Adaptive MA (LazyBear port): MAMA vs FAMA
    src = (h + l) / 2; N = len(c); sm = np.zeros(N); dt = np.zeros(N); q1 = np.zeros(N); i1 = np.zeros(N); ji = np.zeros(N); jq = np.zeros(N)
    i2 = np.zeros(N); q2 = np.zeros(N); re = np.zeros(N); im = np.zeros(N); p = np.zeros(N); spp = np.zeros(N); ph = np.zeros(N)
    ma = np.zeros(N); fa = np.zeros(N)
    for t in range(N):
        sm[t] = (4 * src[t] + 3 * src[t - 1] + 2 * src[t - 2] + src[t - 3]) / 10 if t >= 3 else src[t]
        if t < 6: ma[t] = fa[t] = src[t]; continue
        k = 0.075 * p[t - 1] + 0.54
        hil = lambda x: 0.0962 * x[t] + 0.5769 * x[t - 2] - 0.5769 * x[t - 4] - 0.0962 * x[t - 6]
        dt[t] = hil(sm) * k; q1[t] = hil(dt) * k; i1[t] = dt[t - 3]; ji[t] = hil(i1) * k; jq[t] = hil(q1) * k
        i2[t] = i1[t] - jq[t]; q2[t] = q1[t] + ji[t]; i2[t] = 0.2 * i2[t] + 0.8 * i2[t - 1]; q2[t] = 0.2 * q2[t] + 0.8 * q2[t - 1]
        re[t] = i2[t] * i2[t - 1] + q2[t] * q2[t - 1]; im[t] = i2[t] * q2[t - 1] - q2[t] * i2[t - 1]
        re[t] = 0.2 * re[t] + 0.8 * re[t - 1]; im[t] = 0.2 * im[t] + 0.8 * im[t - 1]
        pp = 360 / np.degrees(np.arctan(im[t] / re[t])) if im[t] != 0 and re[t] != 0 else p[t - 1]
        if p[t - 1] > 0: pp = min(max(pp, 0.67 * p[t - 1]), 1.5 * p[t - 1])
        pp = min(pp, 50)
        pp = max(pp, 6); p[t] = 0.2 * pp + 0.8 * p[t - 1]; spp[t] = 0.33 * p[t] + 0.67 * spp[t - 1]
        ph[t] = np.degrees(np.arctan(q1[t] / i1[t])) if i1[t] != 0 else ph[t - 1]
        dp = max(ph[t - 1] - ph[t], 1); al = min(max(fl / dp, sl), fl)
        ma[t] = al * src[t] + (1 - al) * ma[t - 1]; fa[t] = 0.5 * al * ma[t] + (1 - 0.5 * al) * fa[t - 1]
    return st(ma - fa)

