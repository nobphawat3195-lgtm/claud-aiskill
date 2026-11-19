# Candidate session setups. Every signal is evaluated on a CLOSED M5 bar and filled
# at the first tick after it (column i1). All times UTC; London/NY windows shift with DST.
import numpy as np, pandas as pd

def _emit(rows, m5, k, setup, d, sl, texit):
    rows.append((setup, int(m5.i1.values[k]), d, sl, texit, m5.ts.values[k]))

def gen(m5, P=None):
    P = P or {}
    rows = []
    c, h, l, o = m5.c.values, m5.h.values, m5.l.values, m5.o.values
    e20, atr, atra = m5.ema20.values, m5.atr.values, m5.atr_avg.values
    m15e, tr, adr = m5.m15ema50.values, m5.trend.values, m5.adr.values
    mn, wd, us, eu, ts = m5.mn.values, m5.wd.values, m5.us.values, m5.eu.values, m5.ts.values
    dates = m5.date.values
    flat = P.get('flat', 20 * 60 + 30)                      # winter flat time, shifts with US DST

    # per-day state
    cur = None
    for k in range(2, len(m5)):
        if dates[k] != cur:
            cur = dates[k]
            asia_h = asia_l = None
            orb_h = orb_l = None
            done = set()
            day0 = ts[k] - mn[k] * 60
        if wd[k] >= 5 or np.isnan(tr[k]) or np.isnan(atr[k]) or np.isnan(adr[k]) or tr[k] == 0:
            continue
        T, A = int(tr[k]), atr[k]
        endm = mn[k] + 5                                    # bar close minute
        texit = day0 + (flat - us[k]) * 60
        lon0, ny0 = 7 * 60 - eu[k], 13 * 60 + 30 - us[k]

        # --- Asian box 00:00-06:00
        if mn[k] < 360:
            asia_h = h[k] if asia_h is None else max(asia_h, h[k])
            asia_l = l[k] if asia_l is None else min(asia_l, l[k])
        # --- NY opening range 15 min
        if ny0 <= mn[k] < ny0 + 15:
            orb_h = h[k] if orb_h is None else max(orb_h, h[k])
            orb_l = l[k] if orb_l is None else min(orb_l, l[k])

        def pullback(name, w0, w1, maxsl=2.0, need_m15=True):
            if not (w0 <= endm <= w1) or name in done: return
            if need_m15 and (np.isnan(m15e[k]) or (c[k] - m15e[k]) * T <= 0): return
            if T > 0 and l[k] <= e20[k] < c[k] and c[k] > o[k]:
                sl = min(l[k], l[k - 1]) - 0.3 * A
                if c[k] - sl <= maxsl * A: _emit(rows, m5, k, name, 1, sl, texit); done.add(name)
            elif T < 0 and h[k] >= e20[k] > c[k] and c[k] < o[k]:
                sl = max(h[k], h[k - 1]) + 0.3 * A
                if sl - c[k] <= maxsl * A: _emit(rows, m5, k, name, -1, sl, texit); done.add(name)

        # 1) NY pullback in D1 trend
        pullback('NY_PB', ny0, ny0 + 210)
        # 2) Asia pullback in D1 trend (01:00-06:00)
        pullback('ASIA_PB', 60, 360)
        # 3) London pullback in D1 trend (first 3.5h)
        pullback('LON_PB', lon0, lon0 + 210)

        # 4) London breakout of Asian box in D1 trend
        if asia_h is not None and lon0 <= endm <= lon0 + 210 and 'LON_BRK' not in done:
            box = asia_h - asia_l
            if 0.15 * adr[k] <= box <= 0.6 * adr[k]:
                buf = 0.1 * A
                if T > 0 and c[k] > asia_h + buf and c[k - 1] <= asia_h + buf:
                    sl = max((asia_h + asia_l) / 2, c[k] - 1.5 * A)
                    _emit(rows, m5, k, 'LON_BRK', 1, sl, texit); done.add('LON_BRK')
                elif T < 0 and c[k] < asia_l - buf and c[k - 1] >= asia_l - buf:
                    sl = min((asia_h + asia_l) / 2, c[k] + 1.5 * A)
                    _emit(rows, m5, k, 'LON_BRK', -1, sl, texit); done.add('LON_BRK')

        # 5) NY ORB in D1 trend
        if orb_h is not None and ny0 + 15 <= mn[k] and endm <= ny0 + 120 and 'NY_ORB' not in done:
            if T > 0 and c[k] > orb_h and c[k - 1] <= orb_h:
                sl = max(orb_l, c[k] - 2 * A); _emit(rows, m5, k, 'NY_ORB', 1, sl, texit); done.add('NY_ORB')
            elif T < 0 and c[k] < orb_l and c[k - 1] >= orb_l:
                sl = min(orb_h, c[k] + 2 * A); _emit(rows, m5, k, 'NY_ORB', -1, sl, texit); done.add('NY_ORB')

        # 6) Asia open momentum: first hour after 00:00 closes in trend direction beyond 0.5 ATR
        if endm == 60 and 'ASIA_MOM' not in done:
            day_open = o[k - 11] if mn[k - 11] == 0 else None
            if day_open is not None:
                mv = c[k] - day_open
                if T > 0 and mv > 0.5 * A:
                    _emit(rows, m5, k, 'ASIA_MOM', 1, c[k] - 1.5 * A, texit); done.add('ASIA_MOM')
                elif T < 0 and mv < -0.5 * A:
                    _emit(rows, m5, k, 'ASIA_MOM', -1, c[k] + 1.5 * A, texit); done.add('ASIA_MOM')

    return pd.DataFrame(rows, columns=['setup', 'i', 'dir', 'sl', 'texit', 'ts'])
