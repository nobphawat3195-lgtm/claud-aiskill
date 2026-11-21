# "Scalping-frequency" search: can the passed trend engines trade more often on M5 / M15 / M30?
# 2 years (Nov 2024 - Nov 2026) Dukascopy M1 bid/ask (4 pseudo-ticks/min). SL 1.5 x ATR(14) of the TF, reverse on the opposite signal, no TP.
# Variants per TF:
#   D   = author defaults on the TF, no filter (M30 only; M5/M15 defaults already lose, see multi_tf.py / ind11.py)
#   DF  = author defaults + mothership filter: enter only in the direction of SSL HMA60 on H4 (QUARTET engine 4)
#   HF  = periods x half of (60 / TF minutes) (M5 x6, M15 x2) + the same H4 filter  -> lookback between the TF default and the H1 version
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from m1 import load_m1
from bt import bars, execute
from ind10 import atr, sma
from ind10b import sar_trades, hold
from ind10c import coral, wma as cwma
from ind10e import gann_hilo, itrend
from ind11 import awesome, tsi, pmo, mama, ma_cross, evlist
def hma(x, n): return cwma(2 * cwma(x, n // 2) - cwma(x, n), int(np.sqrt(n)))
def ssl_state(h, l, c, n=60):
    eh, el = hma(h, n), hma(l, n); return hold(np.where(c > eh, 1, np.where(c < el, -1, 0)))
def kst_k(o, h, l, c, k=1):
    roc = lambda n: (c / np.r_[np.full(n, c[0]), c[:-n]] - 1) * 100
    v = sma(roc(10 * k), 10 * k) + 2 * sma(roc(15 * k), 10 * k) + 3 * sma(roc(20 * k), 10 * k) + 4 * sma(roc(30 * k), 15 * k)
    return sar_trades(np.nan_to_num(np.sign(v - sma(v, 9 * k))))
IND = {  # name: f(k) -> fn(O,H,L,C)
    'KST':    lambda k: (lambda O, H, L, C: kst_k(O, H, L, C, k)),
    'Coral':  lambda k: (lambda O, H, L, C: coral(O, H, L, C, sm=21 * k)),
    'Gann':   lambda k: (lambda O, H, L, C: gann_hilo(O, H, L, C, 13 * k, 21 * k)),
    'SSL':    lambda k: (lambda O, H, L, C: sar_trades(ssl_state(H, L, C, 60 * k))),
    'ITrend': lambda k: (lambda O, H, L, C: itrend(O, H, L, C, a=0.07 / k)),
    'PMO':    lambda k: (lambda O, H, L, C: pmo(O, H, L, C, 35 * k, 20 * k, 10 * k)),
    'AO':     lambda k: (lambda O, H, L, C: sar_trades(np.nan_to_num(np.sign(sma((H + L) / 2, 5 * k) - sma((H + L) / 2, 34 * k))))),
    'TSI':    lambda k: (lambda O, H, L, C: tsi(O, H, L, C, 25 * k, 13 * k, 13 * k)),
    'MAMA':   lambda k: (lambda O, H, L, C: mama(O, H, L, C, 0.5 / k, 0.05 / k)),
    'MACross':lambda k: (lambda O, H, L, C: ma_cross(O, H, L, C, 9 * k, 18 * k))}
PLAN = {300: [('DF', 1, True), ('HF', 6, True)], 900: [('DF', 1, True), ('HF', 2, True)], 1800: [('D', 1, False), ('DF', 1, True)]}
START = pd.Timestamp('2024-11-01').timestamp(); END = pd.Timestamp('2026-11-13').timestamp(); SPLIT = pd.Timestamp('2025-11-01').timestamp()
if __name__ == '__main__':
    tt, tb, ta = load_m1('20240801', '20261114'); rng = np.random.default_rng(0); res = []; trades = {}
    h4 = bars(tt, tb, ta, 14400).reset_index(drop=True); h4ts = h4.ts.values + 14400; h4st = ssl_state(h4.h.values, h4.l.values, h4.c.values)
    for tf, variants in PLAN.items():
        m = bars(tt, tb, ta, tf).reset_index(drop=True); O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values; A = atr(H, L, C, 14); TS = m.ts.values + tf
        j = np.searchsorted(h4ts, TS, side='right') - 1; F = np.where(j >= 0, h4st[np.clip(j, 0, None)], 0)
        for vn, k, filt in variants:
            for nm, mk in IND.items():
                rows = []
                for a, d, b in evlist(mk(k)(O, H, L, C)):
                    if TS[a] < START or TS[a] >= END or np.isnan(A[a]) or d == 0 or (filt and d != F[a]): continue
                    i = int(np.searchsorted(tt, TS[a]))
                    if i >= len(tt) - 2: continue
                    e = ta[i] if d > 0 else tb[i]
                    rows.append(dict(setup=nm, i=i, dir=int(d), sl=e - d * 1.5 * A[a], texit=min(TS[min(b, len(m) - 1)], END), ts=TS[a], S=1.5 * A[a]))
                x = execute(tt, tb, ta, pd.DataFrame(rows), tps=(0.0,)).dropna(subset=['r0.0']).reset_index(drop=True); x['R'] = x['r0.0']
                mid = (ta[x.i] + tb[x.i]) / 2; f = x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(); f['dir'] = -x.dir; f['sl'] = 2 * np.asarray(mid) - x.sl.values
                Rf = execute(tt, tb, ta, f, tps=(0.0,))['r0.0'].fillna(0).values; drw = np.where(rng.random((3000, len(x))) < .5, x.R.values, Rf).sum(1)
                p, q = x[x.ts < SPLIT], x[x.ts >= SPLIT]; tfn = f'M{tf//60}'
                hold_h = ((x['x0.0'] - x.ts) / 3600).median()
                r = dict(ind=nm, tf=tfn, var=vn, k=k, n=len(x), per_month=round(len(x) / 24.4, 1), hold_h=hold_h, avgR=x.R.mean(), sumR=x.R.sum(),
                         y1=p.R.mean(), y2=q.R.mean(), rnd=(drw < x.R.sum()).mean(), longs=x.R[x.dir > 0].sum(), shorts=x.R[x.dir < 0].sum(), sl_usd=x.S.median())
                res.append(r); trades[(nm, tf, vn)] = x
                print(f"{nm:8s} {tfn:4s} {vn:2s} n={r['n']:5d} ({r['per_month']:5.1f}/mo, hold {hold_h:5.1f}h, SL {r['sl_usd']:4.1f}$) avg {r['avgR']:+.3f}R sum {r['sumR']:+7.1f}R | y1 {r['y1']:+.3f} y2 {r['y2']:+.3f} | random {r['rnd']:6.1%} | L {r['longs']:+6.1f} S {r['shorts']:+6.1f}", flush=True)
    pd.DataFrame(res).to_csv('fast_tf.csv', index=False); pickle.dump(trades, open('fast_tf.pkl', 'wb'))
