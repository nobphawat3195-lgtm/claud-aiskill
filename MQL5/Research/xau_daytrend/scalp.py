# M5 scalp grid on the most recent year. SL = 1.0 x ATR(M5) from the fill price so a 0.01 lot
# on a $300 Standard account risks roughly 1-3%. Train: 2025-11-01..2026-06-30, test: 2026-07-01..end.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, itertools
from bt import prepare, bars, ema
from m1 import load_m1

SPLIT = pd.Timestamp('2026-07-01').timestamp()
START = pd.Timestamp('2025-11-01').timestamp()

def rsi(x, n):
    d = np.diff(x, prepend=x[0]); up = pd.Series(np.maximum(d, 0)).ewm(alpha=1/n, adjust=False).mean()
    dn = pd.Series(np.maximum(-d, 0)).ewm(alpha=1/n, adjust=False).mean()
    return (100 - 100 / (1 + up / dn.replace(0, np.nan))).values

def features(t, b, a):
    m5 = prepare(t, b, a)
    c = m5.c.values
    sd = pd.Series(c).rolling(20).std().values
    m5['bbu'] = m5.ema20 + 2 * sd; m5['bbl'] = m5.ema20 - 2 * sd     # EMA-centred band
    m5['rsi'] = rsi(c, 7)
    m5['hh'] = pd.Series(m5.h).rolling(12).max().shift(1).values
    m5['ll'] = pd.Series(m5.l).rolling(12).min().shift(1).values
    h1 = bars(t, b, a, 3600); h1['e50'] = ema(h1.c.values, 50)
    j = np.searchsorted(h1.ts.values + 3600, m5.ts.values + 300, side='right') - 1
    m5['h1tr'] = np.where(j >= 0, np.sign(h1.c.values[np.clip(j, 0, None)] - h1.e50.values[np.clip(j, 0, None)]), np.nan)
    return m5

def signals(m5, tf, entry, sess):
    c, o, h, l = m5.c.values, m5.o.values, m5.h.values, m5.l.values
    e20, atr, mn, us, eu, wd = m5.ema20.values, m5.atr.values, m5.mn.values, m5.us.values, m5.eu.values, m5.wd.values
    trd = {'D1': m5.trend.values, 'H1': m5.h1tr.values, 'NONE': np.ones(len(m5))}[tf]
    endm = mn + 5
    lon0, ny0 = 7 * 60 - eu, 13 * 60 + 30 - us
    win = {'ASIA': (endm >= 30) & (endm <= 360),
           'LON': (endm >= lon0) & (endm <= lon0 + 240),
           'NY': (endm >= ny0) & (endm <= ny0 + 240),
           'ALL': (endm >= 30) & (endm <= 20 * 60 - us)}[sess]
    ok = win & (wd < 5) & ~np.isnan(atr) & ~np.isnan(trd) & (m5.ts.values >= START)
    pc, pl, ph = np.r_[c[0], c[:-1]], np.r_[l[0], l[:-1]], np.r_[h[0], h[:-1]]
    if entry == 'PB':
        lg = (l <= e20) & (c > e20) & (c > o); sh = (h >= e20) & (c < e20) & (c < o)
    elif entry == 'BO':
        lg = (c > m5.hh.values) & (pc <= m5.hh.values); sh = (c < m5.ll.values) & (pc >= m5.ll.values)
    else:  # FADE: close back inside the band after poking outside, RSI extreme
        r = m5.rsi.values
        lg = (pl < m5.bbl.values) & (c > m5.bbl.values) & (r < 40); sh = (ph > m5.bbu.values) & (c < m5.bbu.values) & (r > 60)
    if tf != 'NONE':
        lg &= trd > 0; sh &= trd < 0
    k = np.flatnonzero(ok & (lg | sh))
    d = np.where(lg[k], 1, -1)
    return pd.DataFrame({'k': k, 'dir': d, 'i': m5.i1.values[k], 'ts': m5.ts.values[k] + 300, 'atr': atr[k],
                         'send': m5.ts.values[k] - mn[k] * 60 + (20 * 60 + 30 - us[k]) * 60})

def run(t, b, a, sig, tps, hold_bars, slip=0.0):
    """SL = 1 ATR from fill, TP = tp x SL, exit at min(hold, session end). One position at a time per config."""
    res = {tp: [] for tp in tps}
    for tp in tps:
        busy = -1.0; out = []
        for i, d, ts, A, send in zip(sig.i.values, sig.dir.values, sig.ts.values, sig.atr.values, sig.send.values):
            if ts < busy: continue
            e = (a[i] if d > 0 else b[i]) + d * slip
            risk = A; te = min(ts + hold_bars * 300, send)
            j1 = np.searchsorted(t, te)
            if j1 <= i + 1: continue
            px = (b[i + 1:j1] if d > 0 else a[i + 1:j1]) - d * slip
            adv = (px - e) * d
            hs = np.flatnonzero(adv <= -risk); ht = np.flatnonzero(adv >= tp * risk)
            ks = hs[0] if len(hs) else 10**9; kt = ht[0] if len(ht) else 10**9
            k = min(ks, kt, len(adv) - 1)
            out.append((ts, t[i + 1 + k], adv[k] / risk, risk))
            busy = t[i + 1 + k]
        res[tp] = pd.DataFrame(out, columns=['ts', 'x', 'r', 'sl_usd'])
    return res

if __name__ == '__main__':
    t, b, a = load_m1('20250701')
    m5 = features(t, b, a)
    rows = []; keep = {}
    for tf, en, se in itertools.product(['D1', 'H1', 'NONE'], ['PB', 'BO', 'FADE'], ['ASIA', 'LON', 'NY', 'ALL']):
        if en != 'FADE' and tf == 'NONE': continue          # breakout/pullback without a trend filter = coin flip
        sig = signals(m5, tf, en, se)
        for hold in (12, 24):
            res = run(t, b, a, sig, (1.0, 1.5, 2.0), hold)
            for tp, r in res.items():
                if not len(r): continue
                tr, te = r[r.ts < SPLIT], r[r.ts >= SPLIT]
                name = f'{tf}_{en}_{se}_tp{tp}_h{hold}'
                keep[name] = r
                rows.append(dict(cfg=name, n_train=len(tr), R_train=tr.r.sum(), avg_train=tr.r.mean(),
                                 n_test=len(te), R_test=te.r.sum(), avg_test=te.r.mean(),
                                 per_day=len(r) / 260, sl_med=r.sl_usd.median()))
    df = pd.DataFrame(rows).sort_values('R_train', ascending=False)
    pd.set_option('display.width', 220); pd.set_option('display.max_rows', 300)
    print(df.round(3).to_string(index=False))
    df.to_pickle('scalp_grid.pkl'); pd.to_pickle(keep, 'scalp_trades.pkl')
