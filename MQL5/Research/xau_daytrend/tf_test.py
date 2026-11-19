# maker-tung/xauusd-trend-follow (XAUUSD_TrendFollow.mq5) default settings, ported. H1, long only, latest year, real ticks.
# Signal bar k = last closed H1 bar; entry at the first tick after its close (ask); SL 1.25 ATR, TP 6 ATR (= 4.8R), 60-bar time exit,
# one position at a time. Baseline: same filter (close > EMA200 and ADX >= 20) but entering on every bar, no trigger.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, ema, execute
from grok_rep_lib import adx

START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251002')
h = bars(tt, tb, ta, 3600).reset_index(drop=True)
c, hi, lo = h.c.values, h.h.values, h.l.values
pc = np.r_[c[0], c[:-1]]
tr = np.maximum(hi - lo, np.maximum(abs(hi - pc), abs(lo - pc)))
atr = pd.Series(tr).rolling(14).mean().values                          # MT5 iATR = SMA of TR
adxv, _ = adx(hi, lo, c, 14)
e200, e9, e21 = ema(c, 200), ema(c, 9), ema(c, 21)
e12, e26 = ema(c, 12), ema(c, 26)
macd = e12 - e26; sig = pd.Series(macd).rolling(9).mean().values       # MT5 iMACD signal line = SMA
ll = pd.Series(lo).rolling(5).min().values; hh = pd.Series(hi).rolling(5).max().values
rawk = 100 * (c - ll) / np.where(hh - ll > 0, hh - ll, np.nan)
K = pd.Series(rawk).rolling(3).mean().values; Dd = pd.Series(K).rolling(3).mean().values
up = lambda a, b, k: a[k] > b[k] and a[k - 1] <= b[k - 1]
ts_close = h.ts.values + 3600
def run(trigger, name, tp_atr=6.0, sl_atr=1.25):
    rows = []; busy = -1
    for k in range(210, len(h) - 1):
        if ts_close[k] < START or ts_close[k] < busy: continue
        if np.isnan(atr[k]) or np.isnan(adxv[k]): continue
        if not (c[k] > e200[k] and adxv[k] >= 20): continue
        if trigger and not (up(macd, sig, k) or (up(K, Dd, k) and K[k] < 60) or up(e9, e21, k)): continue
        i = int(np.searchsorted(tt, ts_close[k]))
        if i >= len(tt) - 5: break
        rows.append(dict(setup=name, i=i, dir=1, sl=ta[i] - sl_atr * atr[k], texit=ts_close[k] + 60 * 3600, ts=ts_close[k], tp_atr=tp_atr / sl_atr))
        if trigger: busy = ts_close[k] + 3600 * 1                     # placeholder; real busy applied after execute
    return pd.DataFrame(rows)
def execute_seq(s, trig):
    x = execute(tt, tb, ta, s.drop(columns='tp_atr'), tps=(float(s.tp_atr.iloc[0]),))
    x['R'] = x.iloc[:, -2]; x['x'] = x.iloc[:, -1]; x = x.dropna(subset=['R'])
    x['S'] = (ta[x.i] - x.sl)
    if trig:                                                           # one position at a time
        keep = []; busy = -1
        for idx, r in x.iterrows():
            if r.ts < busy: continue
            keep.append(idx); busy = r['x']
        x = x.loc[keep]
    return x
def sim(x, f=.02, cap=.06, start=300.):
    eq = pk = start; mdd = 0; n = 0; mon = {}
    for r in x.itertuples():
        lots = np.floor(eq * f / (r.S * 100) / .01 + 1e-9) * .01
        if lots < .01:
            if r.S / eq > cap: continue
            lots = .01
        eq += lots * 100 * r.S * r.R; n += 1; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
        m = pd.Timestamp(r.ts, unit='s').strftime('%y-%m'); mon[m] = mon.get(m, 0) + lots * 100 * r.S * r.R
        if mdd >= .48: break
    return eq, mdd, n, mon
def report(x, name):
    a, b = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    t_ = x.R.mean() / x.R.std() * np.sqrt(len(x)) if len(x) > 1 else 0
    eq, mdd, n, mon = sim(x)
    print(f'{name}: trades {len(x)} | win {(x.R > 0).mean():.0%} | avg {x.R.mean():+.3f}R | sum {x.R.sum():+.1f}R | t {t_:.2f} | '
          f'Nov-Jun {a.R.sum():+.1f}R ({len(a)}) | Jul-Nov {b.R.sum():+.1f}R ({len(b)}) | SL med ${x.S.median():.1f}')
    print(f'   $300 Standard (2%, cap 6%): -> ${eq:,.0f} ({eq-300:+,.0f}) | taken {n} | DD {mdd:.0%} | $/month: ' + ' '.join(f'{k}:{v:+.0f}' for k, v in sorted(mon.items())))
for tp, sl, nm in [(6.0, 1.25, 'C1 default (SL1.25 TP6)'), (3.0, 1.25, 'C2 TP3'), (6.0, 2.0, 'C3 SL2.0 TP6')]:
    report(execute_seq(run(True, nm, tp, sl), True), nm)
b = execute_seq(run(False, 'baseline', 6.0, 1.25).iloc[::6].reset_index(drop=True), False)       # every 6th qualifying bar (limits overlap)
print(f'BASELINE filter only, every 6th bar long (n={len(b)}): avg {b.R.mean():+.3f}R | win {(b.R > 0).mean():.0%} | sum {b.R.sum():+.1f}R')
