# NadirAliOfficial/engulfing-zone-ea (PriceAction_EngulfingZone_EA.mq5), defaults, ported. M5, latest year, real ticks.
# Event k = M5 bar k just closed (EA's new-candle OnTick). Order of work per event (as in OnTick):
#   1) pending signal from the previous event + no open position -> open at the ask now (SL = zone edge -/+ buffer, TP 1:1)
#   2) clear flags, 3) spread check, 4) ManageZones (invalidate / price-has-left), 5) trend + engulfing + swing -> create zone or set pending.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute

START = pd.Timestamp('2025-11-03').timestamp(); SPLIT = pd.Timestamp('2026-07-01').timestamp()
tt, tb, ta = load('20251102')
m = bars(tt, tb, ta, 300).reset_index(drop=True)
O, H, L, C = m.o.values, m.h.values, m.l.values, m.c.values
END = m.ts.values + 300
LB, NSW, EXIT_N = 3, 4, 3
def run(max_spread, buffer, name):
    swH, swL = [], []                                   # confirmed swing bar indices
    bull = dict(active=False); bear = dict(active=False)
    pend = None; busy = -1; trades = []; zones = 0; skipped_spread = 0
    for k in range(30, len(m) - 3):
        ts_ev = END[k]
        if ts_ev < START - 86400:
            j = k - LB
            if H[j] > H[j - LB:j].max() and H[j] > H[j + 1:j + LB + 1].max(): swH.append(j)
            if L[j] < L[j - LB:j].min() and L[j] < L[j + 1:j + LB + 1].min(): swL.append(j)
            continue
        i = int(np.searchsorted(tt, ts_ev)); spread = ta[i] - tb[i]
        # swing confirmation at j = k - LB (strict, as DetectSwingHigh/Low)
        j = k - LB
        if H[j] > H[j - LB:j].max() and H[j] > H[j + 1:j + LB + 1].max(): swH.append(j)
        if L[j] < L[j - LB:j].min() and L[j] < L[j + 1:j + LB + 1].min(): swL.append(j)
        # 1) open pending trade
        if pend is not None and ts_ev >= busy:
            z, d = pend
            if spread <= max_spread:
                if d > 0: sl = z['lo'] - buffer; risk = ta[i] - sl
                else: sl = z['hi'] + buffer; risk = sl - tb[i]
                if risk > 0:
                    s = pd.DataFrame([dict(setup=name, i=i, dir=d, sl=sl, texit=ts_ev + 3 * 86400, ts=ts_ev)])
                    x = execute(tt, tb, ta, s, tps=(1.0,))
                    if not np.isnan(x['r1.0'].iloc[0]):
                        trades.append(dict(ts=ts_ev, x=x['x1.0'].iloc[0], R=x['r1.0'].iloc[0], S=risk, dir=d)); busy = x['x1.0'].iloc[0]; z['taken'] = True
        pend = None
        # 3) spread gate happens before signals but after ManageZones in the EA
        for z, d in ((bull, 1), (bear, -1)):
            if not z['active']: continue
            if d > 0 and C[k] < z['lo'] or d < 0 and C[k] > z['hi']: z['active'] = False; continue
            if not z['left']:
                outside = C[k] > z['hi'] if d > 0 else C[k] < z['lo']
                z['out'] = z['out'] + 1 if outside else 0
                if z['out'] >= EXIT_N: z['left'] = True
        if spread > max_spread: skipped_spread += 1; continue
        # trend from last NSW swings (bars at least LB back)
        hs = [x for x in swH if x <= k - LB and k - x < 200][-NSW:][::-1]; ls = [x for x in swL if x <= k - LB and k - x < 200][-NSW:][::-1]
        if len(hs) < NSW or len(ls) < NSW: continue
        ph, pl = H[hs], L[ls]
        up = all(ph[a] > ph[a + 1] for a in range(NSW - 1)) and all(pl[a] > pl[a + 1] for a in range(NSW - 1))
        dn = all(ph[a] < ph[a + 1] for a in range(NSW - 1)) and all(pl[a] < pl[a + 1] for a in range(NSW - 1))
        bull_eng = C[k] > O[k] and C[k - 1] < O[k - 1] and O[k] <= C[k - 1] and C[k] >= O[k - 1]
        bear_eng = C[k] < O[k] and C[k - 1] > O[k - 1] and O[k] >= C[k - 1] and C[k] <= O[k - 1]
        at_low = any(j2 in swL for j2 in (k - 3, k - 4, k - 5)); at_high = any(j2 in swH for j2 in (k - 3, k - 4, k - 5))
        for z, d, eng, at, tr in ((bull, 1, bull_eng, at_low, up), (bear, -1, bear_eng, at_high, dn)):
            if not (tr and eng and at): continue
            if z['active']:
                if z['left'] and not z.get('taken') and L[k] >= z['lo'] and H[k] <= z['hi']: pend = (z, d)
            else:
                z.update(active=True, hi=H[k], lo=L[k], left=False, out=0, taken=False); zones += 1
    x = pd.DataFrame(trades)
    return x, zones, skipped_spread
def report(x, name, zones, sk):
    if x.empty: print(f'{name}: zones {zones}, spread-skipped events {sk}: NO TRADES'); return
    a, b = x[x.ts < SPLIT], x[x.ts >= SPLIT]
    t_ = x.R.mean() / x.R.std() * np.sqrt(len(x)) if len(x) > 1 else 0
    eq = 300.
    for r in x.itertuples():
        lots = max(.01, np.floor(eq / 1000 * .04 / .01) * .01); eq += lots * 100 * r.S * r.R
    print(f'{name}: zones {zones} | trades {len(x)} | win {(x.R > 0).mean():.0%} | avg {x.R.mean():+.3f}R | sum {x.R.sum():+.1f}R | t {t_:.2f} | '
          f'Nov-Jun {a.R.sum():+.1f}R ({len(a)}) | Jul-Nov {b.R.sum():+.1f}R ({len(b)}) | SL med ${x.S.median():.2f} | native lots: $300 -> ${eq:,.0f}')
for ms, buf, nm in [(0.50, 0.50, 'C1 2-digit reading (spread<=0.50, buffer 0.50)'), (99, 0.50, 'C2 no spread filter'), (0.05, 0.05, 'C3 3-digit reading (spread<=0.05, buffer 0.05)')]:
    x, z, sk = run(ms, buf, nm); report(x, nm, z, sk)
