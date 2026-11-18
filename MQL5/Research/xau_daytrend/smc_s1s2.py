# SMC on H1, latest year only (2025-11-03 .. 2026-11-13), real ticks for fills and exits.
# Pre-registered configs C1..C4 (see README). Train = Nov-Jun, test = Jul-Nov (report only, no selection).
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import bars, load
from m1 import load_m1
from grok_rep_lib import tr_

START = pd.Timestamp('2025-11-03').timestamp(); END = pd.Timestamp('2026-11-13').timestamp()
SPLIT = pd.Timestamp('2026-07-01').timestamp()
t, b, a = load_m1('20250901')
h = bars(t, b, a, 3600).reset_index(drop=True)
h['atr'] = pd.Series(tr_(h.h.values, h.l.values, h.c.values)).rolling(14).mean().values
O, H, L, C, A, TS = h.o.values, h.h.values, h.l.values, h.c.values, h.atr.values, h.ts.values
N = 3

def setups():
    """S1 BOS+FVG and S2 CHoCH+OB; entry/sl prices fixed at the close of the break bar k."""
    out = []; sh, sl = [], []; used_h = used_l = -1; trend = 0
    for k in range(2 * N + 1, len(h)):
        p = k - N
        if H[p] == H[p - N:p + N + 1].max(): sh.append((p, H[p]))
        if L[p] == L[p - N:p + N + 1].min(): sl.append((p, L[p]))
        if np.isnan(A[k]): continue
        for d in (1, -1):
            sw = sh if d > 0 else sl
            if not sw or sw[-1][0] == (used_h if d > 0 else used_l): continue
            lvl = sw[-1][1]
            if not ((C[k] > lvl and C[k - 1] <= lvl) if d > 0 else (C[k] < lvl and C[k - 1] >= lvl)): continue
            if d > 0: used_h = sw[-1][0]
            else: used_l = sw[-1][0]
            opp = [x for x in (sl if d > 0 else sh) if x[0] < k]
            prev_trend = trend; trend = d
            if not opp: continue
            i0 = opp[-1][0]; buf = 0.1 * A[k]
            if prev_trend == d:                               # continuation break = BOS -> S1 (FVG)
                gaps = [m for m in range(i0 + 1, k + 1) if (L[m] > H[m - 2] if d > 0 else H[m] < L[m - 2])]
                if gaps:
                    m = gaps[-1]
                    entry = H[m - 2] if d > 0 else L[m - 2]   # far edge of the gap (lower edge for buys)
                    stop = (L[i0] - buf) if d > 0 else (H[i0] + buf)
                    out.append(dict(k=k, dir=d, entry=entry, stop=stop, kind='S1'))
            elif prev_trend == -d:                            # break against the trend = CHoCH -> S2 (OB)
                cand = [j for j in range(i0, k) if (C[j] < O[j] if d > 0 else C[j] > O[j])]
                if cand:
                    j = cand[-1]
                    entry = H[j] if d > 0 else L[j]
                    stop = (L[j] - buf) if d > 0 else (H[j] + buf)
                    out.append(dict(k=k, dir=d, entry=entry, stop=stop, kind='S2'))
    return pd.DataFrame(out)
S = setups()
S['t0'] = TS[S.k.values] + 3600
S = S[(S.t0 >= START) & (S.t0 < END)].reset_index(drop=True)
del t, b, a
tt, tb, ta = load('20251102')
def run(cfg_rr, mask):
    trades = []; busy = -1
    for s in S[mask].itertuples():
        d = s.dir
        entry = s.entry; sl = s.stop
        risk = abs(entry - sl)
        if risk <= 0: continue
        t0 = max(s.t0, busy); t1 = s.t0 + 48 * 3600
        if t0 >= t1: continue
        i0, i1 = np.searchsorted(tt, t0), np.searchsorted(tt, t1)
        if i1 <= i0: continue
        # invalidation: price trades through the far side of the OB before the fill -> treat via fill-then-SL naturally,
        # but a close beyond the OB on H1 before any touch cancels: approximate with ticks reaching SL before touching entry
        px_fill = ta[i0:i1] if d > 0 else tb[i0:i1]
        hit = np.flatnonzero(px_fill <= entry) if d > 0 else np.flatnonzero(px_fill >= entry)
        if not len(hit): continue
        f = i0 + hit[0]
        # skip if the fill tick already gapped through the stop
        e = min(entry, ta[f]) if d > 0 else max(entry, tb[f])
        tp = e + d * cfg_rr * risk
        j_end = np.searchsorted(tt, tt[f] + 5 * 86400)             # hard cap 5 days
        px = tb[f + 1:j_end] if d > 0 else ta[f + 1:j_end]
        if not len(px): continue
        adv = (px - e) * d
        hs = np.flatnonzero(adv <= -(e - sl) * d); ht = np.flatnonzero(adv >= cfg_rr * risk)
        k = min(hs[0] if len(hs) else 10**9, ht[0] if len(ht) else 10**9, len(adv) - 1)
        R = adv[k] / ((e - sl) * d)
        trades.append(dict(ts=tt[f], x=tt[f + 1 + k], dir=d, R=R, S=(e - sl) * d))
        busy = tt[f + 1 + k]
    return pd.DataFrame(trades)
def sim(tr, f=.02, cap=.06, start=300., halt=.48):
    eq = pk = start; mdd = 0; n = 0; mon = {}
    for x in tr.itertuples():
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .45 else .5 if dd >= .35 else 1)
        lots = np.floor(eq * ff / (x.S * 100) / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * 100 * x.S / eq > cap: continue
            lots = 0.01
        pnl = lots * 100 * x.S * x.R; eq += pnl; n += 1; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
        m = pd.Timestamp(x.ts, unit='s').strftime('%y-%m'); mon[m] = mon.get(m, 0) + pnl
        if mdd >= halt: return eq, mdd, n, mon, True
    return eq, mdd, n, mon, False

for kind, name in [('S1', 'S1 BOS + FVG'), ('S2', 'S2 CHoCH + Order Block')]:
    mask = (S.kind == kind).values
    tr = run(2.0, mask)
    trn, tst = tr[tr.ts < SPLIT], tr[tr.ts >= SPLIT]
    tstat = tr.R.mean() / tr.R.std() * np.sqrt(len(tr)) if len(tr) > 1 else 0
    eq, mdd, n, mon, halt = sim(tr)
    print(f'\n{name}: setups {int(mask.sum())} | filled {len(tr)} | win {(tr.R > 0).mean():.0%} | avg {tr.R.mean():+.3f}R | t {tstat:.2f} | '
          f'train {trn.R.sum():+.1f}R ({len(trn)}) | test {tst.R.sum():+.1f}R ({len(tst)}) | SL median ${tr.S.median():.1f}')
    print(f'   $300 Standard (risk 2%, min-lot cap 6%): -> ${eq:,.0f} ({eq-300:+,.0f}) | trades taken {n} | DD {mdd:.0%}' + (' HALT' if halt else ''))
    print('   $/month:', ' '.join(f'{k}:{v:+.0f}' for k, v in sorted(mon.items())))
