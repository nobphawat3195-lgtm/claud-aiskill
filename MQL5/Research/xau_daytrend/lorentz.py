# Machine Learning: Lorentzian Classification (jdehorty, v2.0) ported from the user-supplied Pine source.
# Features: RSI14, WT(10,11), CCI20, ADX20, RSI9 (MLExtensions normalisations). Label (as in source): src[4] < src[0] -> short (-1),
# src[4] > src[0] -> long (+1). ANN: every 4th bar skipped (i % 4 != 0), lastDistance logic, k = 8, window = last 2000 bars (rolling).
# Filters: volatility (ATR1 > ATR10), regime (KLMF slope >= -0.1), kernel rationalQuadratic(h8, r8, x25) rising/falling.
# Entry: new signal + kernel agrees. Exit (default strict): after 4 bars, or earlier on an opposite new signal.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from numba import njit
from bt import load, bars, execute
from ind10 import ema, rma, sma, atr, rsi, tr_
S = pd.Series
@njit(cache=True)
def ann(F, Y, nb, mbb, start):
    n = F.shape[0]; pred = np.zeros(n)
    for t in range(start, n):
        lo = max(0, t - mbb + 1); last = -1.0; ds = np.empty(0); ls = np.empty(0)
        dl = []; ll = []
        for i in range(lo, t):                      # training bars strictly before t (labels of bar i known at i)
            if (i - lo) % 4 == 0: continue
            d = 0.0
            for k in range(F.shape[1]): d += np.log(1 + abs(F[t, k] - F[i, k]))
            if d >= last:
                last = d; dl.append(d); ll.append(Y[i])
                if len(dl) > nb:
                    last = dl[int(round(nb * 3 / 4))]; dl.pop(0); ll.pop(0)
        s = 0.0
        for v in ll: s += v
        pred[t] = s
    return pred
def features(h, l, c):
    hlc3 = (h + l + c) / 3
    def norm(x):
        lo = np.minimum.accumulate(np.nan_to_num(x, nan=np.inf)); hi = np.maximum.accumulate(np.nan_to_num(x, nan=-np.inf))
        return (x - lo) / np.maximum(hi - lo, 1e-10)
    esa = ema(hlc3, 10); de = ema(np.abs(hlc3 - esa), 10); w1 = ema((hlc3 - esa) / (0.015 * de), 11); w2 = sma(w1, 4)
    md = S(c).rolling(20).apply(lambda a: np.abs(a - a.mean()).mean(), raw=True).values; cci = (c - sma(c, 20)) / (0.015 * md)
    up = np.r_[0, np.diff(h)]; dn = np.r_[0, -np.diff(l)]
    pdm = np.where((up > dn) & (up > 0), up, 0); mdm = np.where((dn > up) & (dn > 0), dn, 0); t = tr_(h, l, c)
    trs = np.zeros(len(c)); ps = np.zeros(len(c)); ms = np.zeros(len(c))
    for i in range(1, len(c)):                      # MLExtensions n_adx: Wilder sums, then rma(dx)
        trs[i] = trs[i - 1] - trs[i - 1] / 20 + t[i]; ps[i] = ps[i - 1] - ps[i - 1] / 20 + pdm[i]; ms[i] = ms[i - 1] - ms[i - 1] / 20 + mdm[i]
    dip = ps / np.maximum(trs, 1e-10) * 100; dim = ms / np.maximum(trs, 1e-10) * 100
    adx = rma(np.abs(dip - dim) / np.maximum(dip + dim, 1e-10) * 100, 20)
    return np.nan_to_num(np.column_stack([rsi(c, 14) / 100, norm(w1 - w2), norm(cci), adx / 100, rsi(c, 9) / 100]))
def lorentz_signals(o, h, l, c, label_sign=1, mbb=2000):
    F = features(h, l, c); n = len(c)
    c4 = np.r_[np.full(4, c[0]), c[:-4]]
    Y = np.where(c4 < c, -1.0, np.where(c4 > c, 1.0, 0.0)) * label_sign          # source: src[4] < src[0] -> short
    pred = ann(F, Y, 8, mbb, 300)
    vol = atr(h, l, c, 1) > atr(h, l, c, 10)
    o4 = (o + h + l + c) / 4; v1 = np.zeros(n); v2 = np.zeros(n); k = np.zeros(n); k[0] = o4[0]
    for i in range(1, n):
        v1[i] = 0.2 * (o4[i] - o4[i - 1]) + 0.8 * v1[i - 1]; v2[i] = 0.1 * (h[i] - l[i]) + 0.8 * v2[i - 1]
        om = abs(v1[i] / v2[i]) if v2[i] else 0; al = (-om ** 2 + np.sqrt(om ** 4 + 16 * om ** 2)) / 8; k[i] = al * o4[i] + (1 - al) * k[i - 1]
    sl_ = np.abs(np.diff(k, prepend=k[0])); es = ema(sl_, 200); reg = (sl_ - es) / np.where(es == 0, 1e-10, es) >= -0.1
    wk = (1 + np.arange(27) ** 2 / (8 ** 2 * 2 * 8)) ** -8.0
    yh = np.convolve(c, wk, 'full')[:n] / np.convolve(np.ones(n), wk, 'full')[:n]
    bull = np.r_[False, yh[1:] > yh[:-1]]; bear = np.r_[False, yh[1:] < yh[:-1]]
    sig = np.zeros(n); s = 0
    for i in range(n):
        if pred[i] > 0 and vol[i] and reg[i]: s = 1
        elif pred[i] < 0 and vol[i] and reg[i]: s = -1
        sig[i] = s
    ch = np.r_[False, sig[1:] != sig[:-1]]
    out = []; i = 300
    while i < n - 5:                                   # entry on new signal + kernel; exit after 4 bars or opposite new signal
        if ch[i] and ((sig[i] == 1 and bull[i]) or (sig[i] == -1 and bear[i])):
            d = int(sig[i]); j = i + 4
            for q in range(i + 1, i + 4):
                if ch[q] and sig[q] == -d: j = q; break
            out.append((i, d, j)); i = j; continue
        i += 1
    return out, pred
if __name__ == '__main__':
    START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
    tt, tb, ta = load('20251002'); rng = np.random.default_rng(0)
    for tf in (3600, 900, 300):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
        for ls, lab in ((1, 'source label'), (-1, 'flipped label')):
            ev, pred = lorentz_signals(O, H, L, C, ls)
            for slk, sl_lab in ((50.0, 'no SL (source)'), (1.5, 'SL 1.5 ATR')):
                rows = []
                for a, d, b in ev:
                    if TS[a] < START: continue
                    i = int(np.searchsorted(tt, TS[a]))
                    if i >= len(tt) - 2: continue
                    rows.append(dict(setup='LDC', i=i, dir=d, sl=(ta[i] if d > 0 else tb[i]) - d * slk * A[a], texit=TS[b], ts=TS[a], a=A[a]))
                if not rows: print(f'M{tf//60} {lab} {sl_lab}: no trades'); continue
                x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0'])
                x['R'] = x['r0.0'] * slk / 1.5                                     # in 1.5-ATR units
                mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
                Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values * slk / 1.5; drw = np.where(rng.random((5000, len(x))) < .5, x.R.values, Rf).sum(1)
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]
                print(f'M{tf//60:<3} {lab:13s} {sl_lab:15s} n={len(x):5d} ({len(x)/12.4:4.0f}/mo) win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R | Nov-Jun {p.R.mean():+.3f} Jul-Nov {q.R.mean():+.3f} | random {(drw<x.R.sum()).mean():.1%}', flush=True)
