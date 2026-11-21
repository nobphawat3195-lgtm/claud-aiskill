# Batch 9 — second scalping round M1 / M5 / M15: price-action / level / session ideas instead of oscillators.
# Same pre-registered rules as scalp8.py: entries 07:00-20:00 UTC (signal bar close), SL 1 x ATR14, TP 1.5R, time exit 48 bars,
# one trade at a time; variants N (no filter) / F (SSL HMA60 H1 direction). Also reports the edge before spread.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, ema
from fast_tf import ssl_state
from scalp8 import ev, sequential, START, END, SPLIT
S = pd.Series

def daily_hl(m, H, L, C):
    day = m.ts.values // 86400; d = pd.DataFrame(dict(day=day, h=H, l=L, c=C)).groupby('day').agg(h=('h', 'max'), l=('l', 'min'), c=('c', 'last'))
    prev = d.shift(1); return prev.h.reindex(day).values, prev.l.reindex(day).values, prev.c.reindex(day).values, day
def first_per_day(sig, day):
    out = np.zeros(len(sig)); seen = set()
    for i in np.flatnonzero(sig):
        k = (day[i], int(sig[i]))
        if k not in seen: seen.add(k); out[i] = sig[i]
    return out
def pdhl_break(m, O, H, L, C):                                    # previous-day high/low breakout (first close beyond, per side per day)
    ph, pl, pc, day = daily_hl(m, H, L, C); return first_per_day(ev(C > ph, C < pl), day)
def turtle_soup(m, O, H, L, C):                                   # sweep of previous-day high/low that closes back inside -> fade
    ph, pl, pc, day = daily_hl(m, H, L, C); return first_per_day(ev((L < pl) & (C > pl), (H > ph) & (C < ph)), day)
def asian_break(m, O, H, L, C):                                   # 00:00-07:00 UTC range, first close outside 07:00-12:00
    ts = m.ts.values; sec = ts % 86400; day = ts // 86400; out = np.zeros(len(C)); cur = None; tf = ts[1] - ts[0]
    for i in range(len(C)):
        if day[i] != cur: cur = day[i]; hi, lo, done = -1e18, 1e18, False
        if sec[i] < 7 * 3600: hi = max(hi, H[i]); lo = min(lo, L[i]); continue
        if not done and sec[i] + tf <= 12 * 3600:
            if C[i] > hi: out[i] = 1; done = True
            elif C[i] < lo: out[i] = -1; done = True
    return out
def inside_bar(m, O, H, L, C):                                    # inside bar, then close beyond the mother bar within 3 bars
    out = np.zeros(len(C))
    for i in range(2, len(C) - 3):
        if H[i] < H[i - 1] and L[i] > L[i - 1]:
            for j in range(i + 1, i + 4):
                if C[j] > H[i - 1]: out[j] = 1; break
                if C[j] < L[i - 1]: out[j] = -1; break
    return out
def three_bar(m, O, H, L, C):                                     # three strong same-direction bars (body > 0.5 ATR) -> continuation
    a = atr(H, L, C, 14); b = C - O; up = (b > .5 * a) & (C > np.r_[C[0], C[:-1]]); dn = (-b > .5 * a) & (C < np.r_[C[0], C[:-1]])
    u3 = up & np.r_[False, up[:-1]] & np.r_[False, False, up[:-2]]; d3 = dn & np.r_[False, dn[:-1]] & np.r_[False, False, dn[:-2]]
    return ev(u3, d3)
def vol_expansion(m, O, H, L, C):                                 # range > 2 ATR14, close in the outer 25% -> continuation
    a = np.r_[np.nan, atr(H, L, C, 14)[:-1]]; r = H - L; pos = (C - L) / np.maximum(r, 1e-9)
    return ev((r > 2 * a) & (pos > .75), (r > 2 * a) & (pos < .25))
def pivot_reject(m, O, H, L, C):                                  # classic daily pivots: wick through S1/R1 and close back
    ph, pl, pc, day = daily_hl(m, H, L, C); p = (ph + pl + pc) / 3; s1, r1 = 2 * p - ph, 2 * p - pl
    return first_per_day(ev((L < s1) & (C > s1), (H > r1) & (C < r1)), day)
def round_bounce(m, O, H, L, C, step=10.0):                       # wick through a $10 round number and close back
    lv_dn = np.floor(C / step) * step; lv_up = lv_dn + step
    return ev((L < lv_dn) & (C > lv_dn + .1 * (H - L)) & (O > lv_dn), (H > lv_up) & (C < lv_up - .1 * (H - L)) & (O < lv_up))
def ha_ema(m, O, H, L, C):                                        # Heikin Ashi colour flip with EMA200 side
    hc = (O + H + L + C) / 4; ho = np.zeros(len(C)); ho[0] = (O[0] + C[0]) / 2
    for i in range(1, len(C)): ho[i] = (ho[i - 1] + hc[i - 1]) / 2
    bull = hc > ho; pb = np.r_[bull[0], bull[:-1]]; e = ema(C, 200)
    return ev(bull & ~pb & (C > e), ~bull & pb & (C < e))
def fractal_break(m, O, H, L, C):                                 # Williams fractal (5 bars, confirmed 2 bars later) breakout
    n = len(C); upf = np.full(n, np.nan); dnf = np.full(n, np.nan); lu = ld = np.nan
    for i in range(4, n):
        k = i - 2
        if H[k] > max(H[k - 2], H[k - 1], H[k + 1], H[k + 2]): lu = H[k]
        if L[k] < min(L[k - 2], L[k - 1], L[k + 1], L[k + 2]): ld = L[k]
        upf[i], dnf[i] = lu, ld
    pu, pd_ = np.r_[np.nan, upf[:-1]], np.r_[np.nan, dnf[:-1]]; pc = np.r_[C[0], C[:-1]]
    return ev((C > pu) & (pc <= pu), (C < pd_) & (pc >= pd_))
STRATS = dict(PDHL_Break=pdhl_break, TurtleSoup=turtle_soup, AsianBreak=asian_break, InsideBar=inside_bar, ThreeBar=three_bar,
              VolExpansion=vol_expansion, PivotReject=pivot_reject, Round10Bounce=round_bounce, HeikinAshi_EMA200=ha_ema, FractalBreak=fractal_break)
if __name__ == '__main__':
    tt, tb, ta = load_m1('20240801', '20261114'); rng = np.random.default_rng(0); res = []; trades = {}; sp = ta - tb
    h1 = bars(tt, tb, ta, 3600).reset_index(drop=True); h1ts = h1.ts.values + 3600; h1st = ssl_state(h1.h.values, h1.l.values, h1.c.values)
    for tf in (60, 300, 900):
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
        j = np.searchsorted(h1ts, TS, side='right') - 1; Fd = np.where(j >= 0, h1st[np.clip(j, 0, None)], 0); hour = (TS % 86400) / 3600
        for nm, fn in STRATS.items():
            E = fn(m, O, H, L, C); base = np.flatnonzero(np.nan_to_num(E))
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
                gross = x.R.values + sp[x.i.values] / x.S.values
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; tfn = f'M{tf//60}'
                r = dict(ind=nm, tf=tfn, var=vn, n=len(x), per_month=round(len(x) / 24.4, 1), hold_min=((x.xe - x.ts) / 60).median(), win=(x.R > 0).mean(),
                         avgR=x.R.mean(), grossR=gross.mean(), sumR=x.R.sum(), y1=p.R.mean(), y2=q.R.mean(), rnd=(drw < x.R.sum()).mean(),
                         longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum(), sl_usd=x.S.median())
                res.append(r); trades[(nm, tf, vn)] = x
                print(f"{nm:17s} {tfn:4s} {vn} n={r['n']:5d} ({r['per_month']:6.1f}/mo, hold {r['hold_min']:4.0f}m, SL {r['sl_usd']:4.1f}$, win {r['win']:.0%}) avg {r['avgR']:+.3f}R gross {r['grossR']:+.3f} | y1 {r['y1']:+.3f} y2 {r['y2']:+.3f} | random {r['rnd']:6.1%} | L {r['longs']:+7.1f} S {r['shorts']:+7.1f}", flush=True)
    pd.DataFrame(res).to_csv('scalp9.csv', index=False); pickle.dump(trades, open('scalp9.pkl', 'wb'))
