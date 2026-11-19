# Replication of XAU Growth EA v4.10 core modules (ORB_A, DM_A, DM_L, ASIA_B, LON_A) at v4.10 parameters,
# on Dukascopy M1 bid/ask. Exness server = GMT+0 -> broker days are UTC days, Sunday merged into Monday.
# All modules hold to the daily flat (20:30 UTC, 20:00 Friday; minus 1h in US DST), no TP, SL fixed at entry.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, datetime as dt
from bt import bars, ema, execute, us_dst, eu_dst
from m1 import load_m1

def wilder(x, n): return pd.Series(x).ewm(alpha=1 / n, adjust=False).mean().values
def tr_(h, l, c):
    pc = np.r_[c[0], c[:-1]]; return np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
def adx(h, l, c, n=14):
    up = np.r_[0, np.diff(h)]; dn = np.r_[0, -np.diff(l)]
    pdm = np.where((up > dn) & (up > 0), up, 0.0); mdm = np.where((dn > up) & (dn > 0), dn, 0.0)
    atr = wilder(tr_(h, l, c), n); pdi = 100 * wilder(pdm, n) / atr; mdi = 100 * wilder(mdm, n) / atr
    dx = 100 * abs(pdi - mdi) / np.maximum(pdi + mdi, 1e-9); return wilder(dx, n), atr

t, b, a = load_m1()
h1 = bars(t, b, a, 3600); h1['adx'], h1['atrw'] = adx(h1.h.values, h1.l.values, h1.c.values)
m5 = bars(t, b, a, 300); m15 = bars(t, b, a, 900)
m15['atr'] = pd.Series(tr_(m15.h.values, m15.l.values, m15.c.values)).rolling(14).mean().values   # MT5 iATR = SMA(TR)
# broker days: UTC date, Sunday merged into Monday
def tday(ts):
    d = pd.to_datetime(ts, unit='s'); return (d + pd.to_timedelta((d.dt.weekday == 6).astype(int), unit='D')).dt.date
for df in (h1, m5, m15): df['td'] = tday(df.ts).values
D = m5.groupby('td').agg(o=('o', 'first'), h=('h', 'max'), l=('l', 'min'), c=('c', 'last'))
D['ema50'] = ema(D.c.values, 50)
days = list(D.index)
h1i = h1.set_index('ts')
rows = []
def H1_closed_at(sec):          # last H1 bar that closed at or before `sec`
    j = np.searchsorted(h1.ts.values + 3600, sec, side='right') - 1; return h1.iloc[j] if j >= 0 else None
for k, d in enumerate(days):
    if k < 60 or pd.Timestamp(d).weekday() >= 5: continue
    prev = days[k - 1]; day0 = pd.Timestamp(d).tz_localize(None).timestamp()
    us = 3600 if us_dst(d) else 0; eu = 3600 if eu_dst(d) else 0
    flat = day0 + (20 * 3600 if pd.Timestamp(d).weekday() == 4 else 20 * 3600 + 1800) - us
    ema_prev = D.ema50.iloc[k - 1]                    # D1 EMA50 at shift 1
    g5 = m5[(m5.td == d) & (m5.ts >= day0)]
    g15 = m15[(m15.td == d) & (m15.ts >= day0)]
    def entry_i(sec): return int(np.searchsorted(t, sec))
    # --- ORB_A (M5 signal, range 00:00-01:00, signals 01:05..06:00, each side once, max 2/day, SL 1.75 ATR(H1))
    rng = g5[g5.ts < day0 + 3600]
    if len(rng):
        hi, lo = rng.h.max(), rng.l.min(); upd = dnd = False
        for r in g5[(g5.ts + 300 >= day0 + 3900) & (g5.ts + 300 < day0 + 6 * 3600)].itertuples():
            dd = 0
            if not upd and r.c > hi: upd = True; dd = 1
            elif not dnd and r.c < lo: dnd = True; dd = -1
            if dd:
                hb = H1_closed_at(r.ts + 300)
                rows.append(('ORB_A', entry_i(r.ts + 300), dd, r.c - dd * float(os.environ.get('ORBK', 1.75)) * hb.atrw, flat, r.ts + 300, d))
            if upd and dnd: break
    # --- DM_A (01:00, ADX(H1)<25, sign(H1 close - previous day open), SL 1.0 ATR)
    hb = H1_closed_at(day0 + 3600)
    if hb is not None and hb.adx < 25 and hb.c != D.o.iloc[k - 1]:
        dd = 1 if hb.c > D.o.iloc[k - 1] else -1
        rows.append(('DM_A', entry_i(day0 + 3600), dd, hb.c - dd * float(os.environ.get('DMAK', 1.0)) * hb.atrw, flat, day0 + 3600, d))
    # --- DM_L (07:00, sign(H1 close - today open), SL 1.5 ATR)
    hb = H1_closed_at(day0 + 7 * 3600)
    if hb is not None and hb.c != D.o.iloc[k]:
        dd = 1 if hb.c > D.o.iloc[k] else -1
        rows.append(('DM_L', entry_i(day0 + 7 * 3600), dd, hb.c - dd * 1.5 * hb.atrw, flat, day0 + 7 * 3600, d))
    # --- ASIA_B (M15 close beyond previous day high/low in D1-EMA direction, 00:30-06:00, SL bar extreme -/+ 1 ATR(M15), 1/day)
    pdh, pdl = D.h.iloc[k - 1], D.l.iloc[k - 1]
    for r in g15[(g15.ts + 900 >= day0 + 1800) & (g15.ts + 900 <= day0 + 6 * 3600)].itertuples():
        dd = 1 if r.c > ema_prev else -1
        if dd > 0 and r.c > pdh: rows.append(('ASIA_B', entry_i(r.ts + 900), 1, r.l - r.atr, flat, r.ts + 900, d)); break
        if dd < 0 and r.c < pdl: rows.append(('ASIA_B', entry_i(r.ts + 900), -1, r.h + r.atr, flat, r.ts + 900, d)); break
    # --- LON_A (box 00:00-London open, M15 close beyond in D1 direction within 300 min, SL min/max(mid, c -/+ 1 ATR15), 1/day)
    lon = day0 + 7 * 3600 - eu
    box = g5[g5.ts < lon]
    if len(box):
        bh, bl = box.h.max(), box.l.min(); mid = (bh + bl) / 2
        for r in g15[(g15.ts + 900 > lon) & (g15.ts + 900 < lon + 300 * 60)].itertuples():
            dd = 1 if r.c > ema_prev else -1
            if dd > 0 and r.c > bh: rows.append(('LON_A', entry_i(r.ts + 900), 1, min(mid, r.c - r.atr), flat, r.ts + 900, d)); break
            if dd < 0 and r.c < bl: rows.append(('LON_A', entry_i(r.ts + 900), -1, max(mid, r.c + r.atr), flat, r.ts + 900, d)); break
s = pd.DataFrame(rows, columns=['setup', 'i', 'dir', 'sl', 'texit', 'ts', 'date']).dropna()
r = execute(t, b, a, s, tps=(0.0,))
# one open position per module: drop signals that start before the previous trade of the same module closed
keep = []
for m, g in r.sort_values('ts').groupby('setup'):
    busy = -1
    for idx, x in g.iterrows():
        if x.ts < busy: continue
        keep.append(idx); busy = x['x0.0']
r = r.loc[keep]
dtt = pd.to_datetime(r.ts, unit='s')
r['period'] = np.select([dtt < '2024-11-01', dtt < '2025-11-01', dtt < '2026-05-12', dtt < '2026-10-01'],
                        ['PRE Y1 23/24', 'PRE Y2 24/25', 'PRE Y3a 25/26', 'GROK DEV'], 'GROK HO')
pd.set_option('display.width', 200)
print('sum R (count) by module and period')
p = r.pivot_table(index='setup', columns='period', values='r0.0', aggfunc='sum').round(1)
n = r.pivot_table(index='setup', columns='period', values='r0.0', aggfunc='size')
print(p.astype(str) + ' (' + n.astype(str) + ')')
print('\nwin rate / median SL $ by module (all periods)')
e = np.where(r.dir > 0, a[r.i], b[r.i]); r['sl_usd'] = (e - r.sl) * r.dir
print(r.groupby('setup').agg(win=('r0.0', lambda x: (x > 0).mean()), sl_med=('sl_usd', 'median')).round(2))
r.to_pickle(os.environ.get('OUT', 'grok_rep.pkl'))
