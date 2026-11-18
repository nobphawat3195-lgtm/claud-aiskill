import numpy as np, pandas as pd
K = pd.read_pickle('anytf_trades.pkl')
def setup(name):
    sl = float(name.split('_sl')[1].split('_')[0]); r = K[name].copy(); r['sl'] = sl; r['cfg'] = name; return r
def sim(tr, f, start=300., halt=.45):
    ev = sorted([(x.ts, 1, i) for i, x in enumerate(tr.itertuples())] + [(x.x, 0, i) for i, x in enumerate(tr.itertuples())])
    R, S = tr.r.values, tr.sl.values; eq = pk = start; mdd = 0; open_ = {}; n = 0
    for ts, kind, i in ev:
        if kind == 0:
            if i in open_:
                eq += open_.pop(i) * 100 * S[i] * R[i]; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
                if mdd >= halt or eq <= 0: return max(eq, 0), mdd, True, n
            continue
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .4 else .5 if dd >= .25 else 1)
        open_[i] = max(0.01, np.floor(eq * ff / (S[i] * 100) / 0.01 + 1e-9) * 0.01); n += 1
    return eq, mdd, False, n
combos = {'H4_BO_D1_sl9_tp3': ['H4_BO_D1_sl9_tp3'], 'H4_PB_D1_sl12_tp2': ['H4_PB_D1_sl12_tp2'],
          'H4_BO_OWN_sl12_tp3': ['H4_BO_OWN_sl12_tp3'], 'BO_D1 + PB_D1': ['H4_BO_D1_sl9_tp3', 'H4_PB_D1_sl12_tp2']}
rng = np.random.default_rng(5)
for nm, parts in combos.items():
    tr = pd.concat([setup(p) for p in parts]).sort_values('ts').reset_index(drop=True)
    for f in (0.03, 0.05):
        e, m, h, n = sim(tr, f)
        boots = []
        for _ in range(2000):   # resample weeks to keep overlapping trades together
            wk = (tr.ts // (7 * 86400)).values; uw = np.unique(wk); pick = rng.choice(uw, len(uw))
            parts_ = []; off = 0
            for w in pick:
                g = tr[wk == w].copy(); base = g.ts.min()
                g['ts'] = g.ts - base + off; g['x'] = g.x - base + off; off += 7 * 86400; parts_.append(g)
            boots.append(sim(pd.concat(parts_).reset_index(drop=True), f))
        E = np.array([x[0] for x in boots]); H = np.array([x[2] for x in boots]); M = np.array([x[1] for x in boots])
        print(f'{nm:20s} f={f:.0%} trades/day {len(tr)/260:.2f} | actual ${e:,.0f} DD {m:.0%}{" HALT" if h else ""} | boot median ${np.median(E):,.0f} p10 ${np.percentile(E,10):,.0f} p90 ${np.percentile(E,90):,.0f} P(halt) {H.mean():.0%} P(loss) {(E<300).mean():.0%} medDD {np.median(M):.0%}')
