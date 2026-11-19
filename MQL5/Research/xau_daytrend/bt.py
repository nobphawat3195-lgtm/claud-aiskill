# Tick-level research backtester for XAUUSD session setups.
# Signals: M5 bid bars built from Dukascopy ticks (UTC). Entry: first tick after bar close
# at ask (buy) / bid (sell). SL/TP/time exits checked on every tick with real bid/ask.
import sys, os, glob, datetime as dt
import numpy as np, pandas as pd

HERE = os.path.dirname(os.path.abspath(__file__))

def load(d0=None, d1=None):
    fs = sorted(glob.glob(os.path.join(HERE, 'days', '*.npz')))
    if d0: fs = [f for f in fs if os.path.basename(f)[:8] >= d0]
    if d1: fs = [f for f in fs if os.path.basename(f)[:8] < d1]
    T, B, A = [], [], []
    for f in fs:
        z = np.load(f); T.append(z['t']); B.append(z['b']); A.append(z['a'])
    t = np.concatenate(T); b = np.concatenate(B).astype(np.float64); a = np.concatenate(A).astype(np.float64)
    o = np.argsort(t, kind='stable')
    return t[o], b[o], a[o]

# ---------- DST helpers (UTC) ----------
def nth_sunday(y, m, n):
    if n > 0:
        d = dt.date(y, m, 1); d += dt.timedelta(days=(6 - d.weekday()) % 7)
        return d + dt.timedelta(days=7 * (n - 1))
    d = (dt.date(y + (m == 12), m % 12 + 1, 1) - dt.timedelta(days=1))
    return d - dt.timedelta(days=(d.weekday() + 1) % 7)
def us_dst(d): return nth_sunday(d.year, 3, 2) <= d < nth_sunday(d.year, 11, 1)
def eu_dst(d): return nth_sunday(d.year, 3, 0) <= d < nth_sunday(d.year, 10, 0)

# ---------- bars & indicators ----------
def bars(t, b, a, sec):
    k = (t // sec).astype(np.int64)
    idx = np.flatnonzero(np.r_[True, k[1:] != k[:-1]])
    end = np.r_[idx[1:], len(t)]
    df = pd.DataFrame({
        'ts': k[idx] * sec,
        'o': b[idx], 'c': b[end - 1],
        'h': np.maximum.reduceat(b, idx), 'l': np.minimum.reduceat(b, idx),
        'spr': np.maximum.reduceat(a - b, idx),
        'i0': idx, 'i1': end,          # tick index range; i1 = first tick after the bar
    })
    return df

def ema(x, n): return pd.Series(x).ewm(span=n, adjust=False).mean().values
def atr(df, n):
    pc = np.r_[df.c.values[0], df.c.values[:-1]]
    tr = np.maximum(df.h - df.l, np.maximum(abs(df.h - pc), abs(df.l - pc)))
    return pd.Series(tr).ewm(alpha=1 / n, adjust=False).mean().values

def prepare(t, b, a):
    m5 = bars(t, b, a, 300)
    m5['ema20'] = ema(m5.c.values, 20)
    m5['atr'] = atr(m5, 14)
    m5['atr_avg'] = pd.Series(m5.atr).rolling(20).mean().values
    m15 = bars(t, b, a, 900)
    m15['ema50'] = ema(m15.c.values, 50)
    # M15 value known at close of the M15 bar -> map to M5 bars that close at/after it
    m15_close = m15.ts.values + 900
    j = np.searchsorted(m15_close, m5.ts.values + 300, side='right') - 1
    m5['m15ema50'] = np.where(j >= 0, m15.ema50.values[np.clip(j, 0, None)], np.nan)
    # D1: trading day ends 22:00 UTC (approx NY close). Trend from previous completed day.
    day = ((t + 2 * 3600) // 86400).astype(np.int64)
    di = np.flatnonzero(np.r_[True, day[1:] != day[:-1]]); de = np.r_[di[1:], len(t)]
    d1 = pd.DataFrame({'day': day[di], 'c': b[de - 1], 'h': np.maximum.reduceat(b, di), 'l': np.minimum.reduceat(b, di)})
    d1['ema50'] = ema(d1.c.values, 50)
    d1['adr'] = (d1.h - d1.l).rolling(14).mean()
    d1['trend'] = np.sign(d1.c - d1.ema50)
    prev = d1.set_index('day')[['trend', 'adr', 'ema50', 'c']].shift(1)
    m5day = ((m5.ts.values + 2 * 3600) // 86400).astype(np.int64)
    m5['trend'] = prev.trend.reindex(m5day).values
    m5['adr'] = prev.adr.reindex(m5day).values
    ts = pd.to_datetime(m5.ts, unit='s', utc=True)
    m5['date'] = ts.dt.date
    m5['mn'] = ts.dt.hour * 60 + ts.dt.minute          # bar START minute of UTC day
    m5['wd'] = ts.dt.weekday
    dates = sorted(set(m5.date))
    usd = {d: us_dst(d) for d in dates}; eud = {d: eu_dst(d) for d in dates}
    m5['us'] = m5.date.map(usd).astype(int) * 60
    m5['eu'] = m5.date.map(eud).astype(int) * 60
    return m5

# ---------- execution ----------
def execute(t, b, a, sig, tps=(1.0, 1.5, 2.0, 3.0, 0.0), slip=0.0):
    """sig: DataFrame with i (tick idx of entry), dir, sl, texit (unix).
    Adds r<tp> (result in R, incl. real spread and `slip` $ per side) and x<tp> (exit unix time).
    tp=0 means no TP: exit at SL or at texit."""
    R = {tp: [] for tp in tps}; X = {tp: [] for tp in tps}
    for i, d, sl, te in zip(sig.i.values, sig.dir.values, sig.sl.values, sig.texit.values):
        e = (a[i] if d > 0 else b[i]) + d * slip
        risk = (e - sl) * d
        j1 = np.searchsorted(t, te)
        if risk <= 0 or j1 <= i + 1:
            for tp in tps: R[tp].append(np.nan); X[tp].append(np.nan)
            continue
        px = (b[i + 1:j1] if d > 0 else a[i + 1:j1]) - d * slip
        adv = (px - e) * d
        hs = np.flatnonzero(adv <= -risk); ks = hs[0] if len(hs) else None
        for tp in tps:
            kt = None
            if tp > 0:
                ht = np.flatnonzero(adv >= tp * risk); kt = ht[0] if len(ht) else None
            if ks is not None and (kt is None or ks <= kt): k = ks
            elif kt is not None: k = kt
            else: k = len(adv) - 1
            R[tp].append(adv[k] / risk); X[tp].append(t[i + 1 + k])
    res = sig.copy()
    for tp in tps: res[f'r{tp}'] = R[tp]; res[f'x{tp}'] = X[tp]
    return res
