# Any-timeframe grid for a $300 Standard account, last year only.
# Fixed-dollar SL (0.01 lot = $1 per $1): $6/$9/$12 = 2/3/4% of $300. TP 1/2/3 x SL. Max hold 48 bars,
# forced exit Friday 20:00 UTC (no weekend holding). One position at a time per config.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, itertools
from bt import bars, ema, atr, prepare
from m1 import load_m1

START = pd.Timestamp('2025-11-01').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
TF = {'M15': 900, 'H1': 3600, 'H4': 14400}

def tf_frame(t, b, a, sec, d1trend):
    x = bars(t, b, a, sec)
    x['e20'] = ema(x.c.values, 20); x['e50'] = ema(x.c.values, 50)
    sd = pd.Series(x.c).rolling(20).std().values
    x['bbu'] = x.e20 + 2 * sd; x['bbl'] = x.e20 - 2 * sd
    x['dch'] = pd.Series(x.h).rolling(20).max().shift(1).values
    x['dcl'] = pd.Series(x.l).rolling(20).min().shift(1).values
    x['end'] = x.ts + sec
    # D1 trend known at bar close (prev completed 22:00-UTC day)
    x['d1'] = d1trend(x.end.values)
    return x

def signals(x, entry, trend):
    c, o, h, l = x.c.values, x.o.values, x.h.values, x.l.values
    pc = np.r_[c[0], c[:-1]]; pl = np.r_[l[0], l[:-1]]; ph = np.r_[h[0], h[:-1]]
    up = (c > x.e50.values) if trend == 'OWN' else (x.d1.values > 0)
    dn = (c < x.e50.values) if trend == 'OWN' else (x.d1.values < 0)
    if entry == 'PB':
        lg = (l <= x.e20.values) & (c > x.e20.values) & (c > o) & up
        sh = (h >= x.e20.values) & (c < x.e20.values) & (c < o) & dn
    elif entry == 'BO':
        lg = (c > x.dch.values) & (pc <= x.dch.values) & up
        sh = (c < x.dcl.values) & (pc >= x.dcl.values) & dn
    else:   # MR: back inside the band, only in the trend direction (buy dips / sell rallies)
        lg = (pl < x.bbl.values) & (c > x.bbl.values) & up
        sh = (ph > x.bbu.values) & (c < x.bbu.values) & dn
    wd = pd.to_datetime(x.end, unit='s').dt.weekday.values
    hr = pd.to_datetime(x.end, unit='s').dt.hour.values
    ok = (x.end.values >= START) & (wd < 5) & ~((wd == 4) & (hr >= 19)) & ~np.isnan(x.d1.values)
    k = np.flatnonzero(ok & (lg | sh))
    return x.end.values[k], np.where(lg[k], 1, -1)

def run(t, b, a, ts, dirs, sl, tp, hold_sec):
    out = []; busy = -1
    for s, d in zip(ts, dirs):
        if s < busy: continue
        i = np.searchsorted(t, s)
        if i >= len(t) - 2: break
        fri = (s // 86400) * 86400 + ((4 - pd.Timestamp(s, unit='s').weekday()) % 7) * 86400 + 20 * 3600
        te = min(s + hold_sec, fri)
        j1 = np.searchsorted(t, te)
        if j1 <= i + 1: continue
        e = a[i] if d > 0 else b[i]
        adv = ((b[i+1:j1] if d > 0 else a[i+1:j1]) - e) * d
        hs = np.flatnonzero(adv <= -sl); ht = np.flatnonzero(adv >= tp * sl)
        k = min(hs[0] if len(hs) else 10**9, ht[0] if len(ht) else 10**9, len(adv) - 1)
        out.append((s, t[i + 1 + k], adv[k] / sl)); busy = t[i + 1 + k]
    return pd.DataFrame(out, columns=['ts', 'x', 'r'])

if __name__ == '__main__':
    t, b, a = load_m1('20250501')
    m5 = prepare(t, b, a)
    d1key = ((m5.ts.values + 2 * 3600) // 86400)
    tr_by_day = pd.Series(m5.trend.values, index=d1key).groupby(level=0).first()
    d1trend = lambda end: tr_by_day.reindex(((end - 1 + 2 * 3600) // 86400)).values
    rows = []; keep = {}
    for tfn, sec in TF.items():
        x = tf_frame(t, b, a, sec, d1trend)
        for entry, trend in itertools.product(['PB', 'BO', 'MR'], ['OWN', 'D1']):
            ts, dirs = signals(x, entry, trend)
            for sl, tp in itertools.product((6.0, 9.0, 12.0), (1.0, 2.0, 3.0)):
                r = run(t, b, a, ts, dirs, sl, tp, 48 * sec)
                if not len(r): continue
                name = f'{tfn}_{entry}_{trend}_sl{int(sl)}_tp{int(tp)}'; keep[name] = r
                tr, te = r[r.ts < SPLIT], r[r.ts >= SPLIT]
                rows.append(dict(cfg=name, n=len(r), per_day=round(len(r) / 260, 2), R_train=tr.r.sum(), R_test=te.r.sum(),
                                 avgR=r.r.mean(), win=(r.r > 0).mean()))
    df = pd.DataFrame(rows)
    pd.set_option('display.width', 200); pd.set_option('display.max_rows', 400)
    both = df[(df.R_train > 0) & (df.R_test > 0)].sort_values('R_test', ascending=False)
    print(f'configs {len(df)} | positive in train {int((df.R_train > 0).sum())} | positive in train AND test {len(both)}')
    print(both.round(3).to_string(index=False))
    print('\nby timeframe: share positive in both'); df['tf'] = df.cfg.str.split('_').str[0]
    print(df.assign(both=(df.R_train > 0) & (df.R_test > 0)).groupby('tf').both.mean().round(2).to_string())
    df.to_pickle('anytf_grid.pkl'); pd.to_pickle(keep, 'anytf_trades.pkl')
