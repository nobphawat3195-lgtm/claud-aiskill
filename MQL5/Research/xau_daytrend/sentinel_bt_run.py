import numpy as np, pandas as pd
def run(parts, f, cent=True, halt=.50, cap=.055):
    x = pd.concat([p.assign(eng=k) for k, p in parts.items()]).sort_values('ts'); x['xe'] = x['x0.0']
    closed = []; skipped = 0; stop_t = None
    for r in x.itertuples():
        if stop_t is not None and r.ts >= stop_t: break
        e0 = 300 + sum(p for t, p, _ in closed if t <= r.ts)
        if cent: lots = e0 * f / (r.S * 100)                                  # Cent: 0.01 lot = USD 0.01 per USD 1 move -> fine sizing
        else:
            lots = np.floor(e0 * f / (r.S * 100) / .01 + 1e-9) * .01
            if lots < .01:
                if r.S / e0 > cap: skipped += 1; continue
                lots = .01
        closed.append((r.xe, lots * 100 * r.S * r.R, r.eng))
        # halt check on closed equity so far
        eq = 300; pk = 300
        for t, p, _ in sorted(closed):
            eq += p; pk = max(pk, eq)
            if 1 - eq / pk >= halt: stop_t = t; break
    eq = pk = 300.; mdd = 0; mon = {}; curve = [(pd.Timestamp('2025-11-03').timestamp(), 300.)]; by = {}
    for t, p, e in sorted(closed):
        if stop_t is not None and t > stop_t: continue
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk); curve.append((t, eq))
        k = pd.Timestamp(t, unit='s').strftime('%Y-%m'); mon[k] = mon.get(k, 0) + p; by[e] = by.get(e, 0) + p
    return eq, mdd, len(closed), skipped, mon, curve, stop_t, by
