# Compounding portfolio simulation on a trade list (entry ts, exit ts, R).
import numpy as np, pandas as pd
def simulate(tr, rcol, xcol, risk=0.01, start=300.0, max_open=0.04, halt=0.45, dd_half=0.25, dd_q=0.40, daily_stop=0.06):
    ev = []
    tr = tr.dropna(subset=[rcol]).sort_values('ts')
    for k, r in enumerate(tr.itertuples()):
        ev.append((r.ts, 1, k)); ev.append((getattr(r, xcol), 0, k))
    ev.sort()
    rs = tr[rcol].values
    bal = peak = start; open_ = {}; curve = []; maxdd = 0; halted = False
    day = None; day_bal = bal; day_stop = False; taken = 0
    for ts, kind, k in ev:
        d = int((ts + 2 * 3600) // 86400)
        if d != day: day, day_bal, day_stop = d, bal, False
        if kind == 0:
            if k in open_:
                bal += open_.pop(k) * rs[k]
                peak = max(peak, bal); dd = 1 - bal / peak; maxdd = max(maxdd, dd)
                curve.append((ts, bal))
                if dd >= halt: halted = True
                if bal <= day_bal * (1 - daily_stop): day_stop = True
            continue
        if halted or day_stop: continue
        dd = 1 - bal / peak
        f = risk * (0.25 if dd >= dd_q else 0.5 if dd >= dd_half else 1.0)
        if sum(open_.values()) + f * bal > max_open * bal: continue
        open_[k] = f * bal; taken += 1
    return dict(final=bal, ret=bal / start - 1, maxdd=maxdd, trades=taken, halted=halted), pd.DataFrame(curve, columns=['ts', 'bal'])
