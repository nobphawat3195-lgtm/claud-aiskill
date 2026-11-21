# Batch 6: 10 more TradingView trend indicators (author / built-in defaults), tested as candidate QUARTET engines.
# 2 years (Nov 2024 - Nov 2026) on Dukascopy M1 bid/ask (4 pseudo-ticks/min); M15, H1, H4.
# Same rules as every batch: entry next tick after the signal bar closes, SL 1.5 x ATR(14), exit/reverse on the opposite signal, no TP.
# Pass = 2-year random-direction >= 95% and both years positive; grade A also needs longs and shorts positive and random >= 99.5%.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, ema, sma, rma
from ind10b import sar_trades, hold
S = pd.Series
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

IND = dict(Ichimoku=ichimoku, AwesomeOsc=awesome, TSI=tsi, PMO=pmo, RVI=rvi, Andean=andean, ChandeKroll=chande_kroll,
           NadarayaWatson=nadaraya, MACross9_18=ma_cross, MAMA_FAMA=mama)
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
def evlist(ev):
    if isinstance(ev, list): return ev
    idx = np.flatnonzero(ev); return [(a, int(ev[a]), b) for a, b in zip(idx, np.r_[idx[1:], len(ev) - 1])]
if __name__ == '__main__':
    tt, tb, ta = load_m1('20240801', '20261114'); rng = np.random.default_rng(0); res = []; trades = {}
    for tf in (900, 3600, 14400):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
        for nm, fn in IND.items():
            rows = []
            for a, d, b in evlist(fn(O, H, L, C)):
                if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or d == 0: continue
                i = int(np.searchsorted(tt, TS[a]))
                if i >= len(tt) - 2: continue
                e = ta[i] if d > 0 else tb[i]
                rows.append(dict(setup=nm, i=i, dir=int(d), sl=e - d * 1.5 * A[a], texit=min(TS[min(b, len(m) - 1)], END), ts=TS[a], S=1.5 * A[a]))
            x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']).reset_index(drop=True); x['R'] = x['r0.0']
            mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
            Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((4000, len(x))) < .5, x.R.values, Rf).sum(1)
            p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; tfn = f'M{tf//60}' if tf < 3600 else f'H{tf//3600}'
            r = dict(ind=nm, tf=tfn, n=len(x), per_month=round(len(x) / 24.4, 1), avgR=x.R.mean(), sumR=x.R.sum(), y1=p.R.mean(), y2=q.R.mean(),
                     rnd=(drw < x.R.sum()).mean(), longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum())
            res.append(r); trades[(nm, tf)] = x
            print(f"{nm:15s} {tfn:4s} n={r['n']:5d} ({r['per_month']:5.1f}/mo) avg {r['avgR']:+.3f}R sum {r['sumR']:+7.1f}R | y1 {r['y1']:+.3f} y2 {r['y2']:+.3f} | random {r['rnd']:6.1%} | L {r['longs']:+6.1f} S {r['shorts']:+6.1f}", flush=True)
    pd.DataFrame(res).to_csv('ind11.csv', index=False); pickle.dump(trades, open('ind11.pkl', 'wb'))
