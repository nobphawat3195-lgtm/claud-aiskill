# Standard account: latest year only (Nov 2025 - Nov 2026, the trader's starting point today), various starting balances.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
E = pickle.load(open('port2y.pkl', 'rb')); F = pickle.load(open('fast_tf.pkl', 'rb')); N = pickle.load(open('ind11.pkl', 'rb'))
Q = {k: E[k] for k in ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']}
SIX = {**Q, 'PMO H4': N[('PMO', 14400)], 'AO H4': N[('AwesomeOsc', 14400)]}
SEV = {**SIX, 'AO M30F': F[('AO', 1800, 'DF')]}
SPLIT = pd.Timestamp('2025-11-01').timestamp()
def sim(parts, f, base, cap, cent=False, halt=.70):
    x = pd.concat([p.assign(eng=k) for k, p in parts.items()]); x = x[x.ts >= SPLIT].sort_values('ts'); x['xe'] = x['x0.0']
    closed = []; sk = 0; stop = None
    for r in x.itertuples():
        if stop is not None and r.ts >= stop: break
        e0 = base + sum(p for t, p in closed if t <= r.ts)
        if cent: lots = e0 * f / (r.S * 100)
        else:
            lots = np.floor(e0 * f / (r.S * 100) / .01 + 1e-9) * .01
            if lots < .01:
                if .01 * r.S * 100 / e0 > cap: sk += 1; continue
                lots = .01
        closed.append((r.xe, lots * 100 * r.S * r.R))
        eq = pk = base
        for t, p in sorted(closed):
            eq += p; pk = max(pk, eq)
            if 1 - eq / pk >= halt: stop = t; break
    eq = pk = base; mdd = 0
    for t, p in sorted(closed):
        if stop is not None and t > stop: continue
        eq += p; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
    return eq, mdd, len(closed), sk, stop
for nm, P in (('QUARTET', Q), ('HEXA', SIX), ('TURBO', SEV)):
    for base in (300, 1000, 2000, 3000, 5000):
        out = []
        for cap, cl in ((.055, 'cap5.5'), (1.0, 'always')):
            eq, dd, n, sk, st = sim(P, .01, base, cap)
            out.append(f'{cl}: ${eq:,.0f} ({(eq/base-1):+.0%}) DD {dd:.0%} trades {n} skip {sk}' + (' HALT' if st else ''))
        print(f'{nm:7s} start ${base:>5,} risk 1% | ' + ' | '.join(out), flush=True)
    eq, dd, n, sk, st = sim(P, .01, 300, 1, cent=True); print(f'{nm:7s} CENT $300 1% latest year: ${eq:,.0f} DD {dd:.0%}', flush=True)
