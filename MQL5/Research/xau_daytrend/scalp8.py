# Batch 8 — scalping round on M1 / M5 / M15 (pre-registered, skill xau-ea-loop).
# 2 years Dukascopy M1 bid/ask (4 pseudo-ticks/min). Entries only when the signal bar closes 07:00-20:00 UTC.
# Exit (scalping): SL 1 x ATR14 of the TF, TP 1.5R, or time exit after 48 bars. One open trade per strategy (later signals skipped).
# Variants: N = no trend filter; F = only in the direction of SSL HMA60 on H1.
# Scalping gate: random >= 95%, both years positive, avg R > +0.05 after spread, >= 40 trades/month.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, ema, sma, rma, rsi
from ind10b import hold, cross_up, cross_dn
from fast_tf import ssl_state
S = pd.Series

def ev(long_, short_): return np.where(long_, 1, np.where(short_, -1, 0))
def ema_cross(m, O, H, L, C):
    e9, e21, e50 = ema(C, 9), ema(C, 21), ema(C, 50); return ev(cross_up(e9, e21) & (C > e50), cross_dn(e9, e21) & (C < e50))
def slingshot(m, O, H, L, C):                                       # CM Sling Shot System (ChrisMoody): EMA38/62 pullback re-entry
    f, s = ema(C, 38), ema(C, 62); pc = np.r_[C[0], C[:-1]]; pf = np.r_[f[0], f[:-1]]
    return ev((f > s) & (pc < pf) & (C > f), (f < s) & (pc > pf) & (C < f))
def stoch_pb(m, O, H, L, C):                                         # Stochastic 5/3/3 cross from <20 / >80 with EMA50 side
    k = 100 * (C - S(L).rolling(5).min().values) / np.maximum(S(H).rolling(5).max().values - S(L).rolling(5).min().values, 1e-9)
    k = sma(k, 3); d = sma(k, 3); e50 = ema(C, 50)
    return ev(cross_up(k, d) & (np.r_[k[0], k[:-1]] < 20) & (C > e50), cross_dn(k, d) & (np.r_[k[0], k[:-1]] > 80) & (C < e50))
def vwap_cross(m, O, H, L, C):                                       # daily session VWAP (tick-count proxy = equal weight) cross with EMA50 side
    day = (m.ts.values // 86400); tp = (H + L + C) / 3
    vw = S(tp).groupby(day).cumsum().values / S(np.ones(len(tp))).groupby(day).cumsum().values; e50 = ema(C, 50)
    return ev(cross_up(C, vw) & (C > e50), cross_dn(C, vw) & (C < e50))
def bb_fade(m, O, H, L, C):                                          # Bollinger 20/2 re-entry (mean reversion)
    mid = sma(C, 20); sd = S(C).rolling(20).std(ddof=0).values; up, lo = mid + 2 * sd, mid - 2 * sd
    pc = np.r_[C[0], C[:-1]]; plo = np.r_[lo[0], lo[:-1]]; pup = np.r_[up[0], up[:-1]]
    return ev((pc < plo) & (C > lo), (pc > pup) & (C < up))
def rsi_fade(m, O, H, L, C):                                         # RSI 7 crosses back above 30 / below 70
    r = rsi(C, 7); return ev(cross_up(r, np.full(len(r), 30.)), cross_dn(r, np.full(len(r), 70.)))
def supertrend(m, O, H, L, C, n=10, k=3.0):
    a = rma(np.maximum(H - L, np.maximum(abs(H - np.r_[C[0], C[:-1]]), abs(L - np.r_[C[0], C[:-1]]))), n); hl = (H + L) / 2
    up, dn = hl - k * a, hl + k * a; tr = np.ones(len(C)); fu, fd = up.copy(), dn.copy()
    for i in range(1, len(C)):
        fu[i] = max(up[i], fu[i - 1]) if C[i - 1] > fu[i - 1] else up[i]
        fd[i] = min(dn[i], fd[i - 1]) if C[i - 1] < fd[i - 1] else dn[i]
        tr[i] = 1 if C[i] > fd[i - 1] else (-1 if C[i] < fu[i - 1] else tr[i - 1])
    ch = np.r_[0, np.diff(tr)]; return ev(ch > 0, ch < 0)
def keltner_bo(m, O, H, L, C):                                       # Keltner EMA20 ± 1.5 ATR10 breakout
    mid = ema(C, 20); a = rma(np.maximum(H - L, abs(H - np.r_[C[0], C[:-1]])), 10)
    return ev(cross_up(C, mid + 1.5 * a), cross_dn(C, mid - 1.5 * a))
def orb(m, O, H, L, C, r0, r1, last):                                # opening-range breakout, one trade per day
    ts = m.ts.values; sec = ts % 86400; day = ts // 86400; out = np.zeros(len(C)); cur = None; hi = lo = None; done = False
    for i in range(len(C)):
        if day[i] != cur: cur = day[i]; hi, lo = -1e18, 1e18; done = False
        if r0 <= sec[i] < r1: hi = max(hi, H[i]); lo = min(lo, L[i]); continue
        end = sec[i] + (ts[1] - ts[0])
        if not done and sec[i] >= r1 and end <= last and hi > -1e17:
            if C[i] > hi: out[i] = 1; done = True
            elif C[i] < lo: out[i] = -1; done = True
    return out
STRATS = dict(EMA9_21=ema_cross, SlingShot=slingshot, StochPB=stoch_pb, VWAP=vwap_cross, BBFade=bb_fade, RSI7Fade=rsi_fade,
              SuperTrend=supertrend, KeltnerBO=keltner_bo,
              NY_ORB=lambda m, O, H, L, C: orb(m, O, H, L, C, 13.5 * 3600, 14 * 3600, 17 * 3600),
              London_ORB=lambda m, O, H, L, C: orb(m, O, H, L, C, 7 * 3600, 8 * 3600, 12 * 3600))
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
def sequential(x):
    keep = []; busy = -1
    for r in x.itertuples():
        if r.ts >= busy: keep.append(r.Index); busy = r.xe
    return x.loc[keep]
if __name__ == '__main__':
    tt, tb, ta = load_m1('20240801', '20261114'); rng = np.random.default_rng(0); res = []; trades = {}
    h1 = bars(tt, tb, ta, 3600).reset_index(drop=True); h1ts = h1.ts.values + 3600; h1st = ssl_state(h1.h.values, h1.l.values, h1.c.values)
    for tf in (60, 300, 900):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
        j = np.searchsorted(h1ts, TS, side='right') - 1; Fd = np.where(j >= 0, h1st[np.clip(j, 0, None)], 0); hour = (TS % 86400) / 3600
        for nm, fn in STRATS.items():
            E = fn(m, O, H, L, C); base = np.flatnonzero(E)
            for vn in ('N', 'F'):
                rows = []
                for a in base:
                    d = int(E[a])
                    if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or not (7 <= hour[a] < 20) or (vn == 'F' and d != Fd[a]): continue
                    i = int(np.searchsorted(tt, TS[a]))
                    if i >= len(tt) - 2: continue
                    e = ta[i] if d > 0 else tb[i]
                    rows.append(dict(setup=nm, i=i, dir=d, sl=e - d * A[a], texit=TS[a] + 48 * tf, ts=TS[a], S=A[a]))
                if len(rows) < 20: continue
                x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(1.5,)).dropna(subset=['r1.5']).reset_index(drop=True); x['R'] = x['r1.5']; x['xe'] = x['x1.5']
                x = sequential(x).reset_index(drop=True)
                mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
                Rf = execute(tt, tb, ta, f, tps=(1.5,))['r1.5'].fillna(0).values; drw = np.where(rng.random((3000, len(x))) < .5, x.R.values, Rf).sum(1)
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; tfn = f'M{tf//60}'
                r = dict(ind=nm, tf=tfn, var=vn, n=len(x), per_month=round(len(x) / 24.4, 1), hold_min=((x.xe - x.ts) / 60).median(), win=(x.R > 0).mean(),
                         avgR=x.R.mean(), sumR=x.R.sum(), y1=p.R.mean(), y2=q.R.mean(), rnd=(drw < x.R.sum()).mean(),
                         longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum(), sl_usd=x.S.median())
                res.append(r); trades[(nm, tf, vn)] = x
                print(f"{nm:10s} {tfn:4s} {vn} n={r['n']:5d} ({r['per_month']:5.1f}/mo, hold {r['hold_min']:5.0f}m, SL {r['sl_usd']:4.1f}$, win {r['win']:.0%}) avg {r['avgR']:+.3f}R sum {r['sumR']:+7.1f}R | y1 {r['y1']:+.3f} y2 {r['y2']:+.3f} | random {r['rnd']:6.1%} | L {r['longs']:+6.1f} S {r['shorts']:+6.1f}", flush=True)
    pd.DataFrame(res).to_csv('scalp8.csv', index=False); pickle.dump(trades, open('scalp8.pkl', 'wb'))
