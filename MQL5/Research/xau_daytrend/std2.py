import numpy as np, pandas as pd
df = pd.read_pickle('trend_re.pkl'); df = df[df.cfg.str.startswith('A_')].sort_values('ts')
def path(R, S, f, start=300., halt=.45):
    eq = pk = start; mdd = 0
    for r, s in zip(R, S):
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .40 else .5 if dd >= .25 else 1)
        lots = max(0.01, np.floor(eq * ff / (s * 100) / 0.01 + 1e-9) * 0.01)    # never below broker minimum
        eq += lots * 100 * s * r; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
        if mdd >= halt or eq <= 0: return max(eq, 0), mdd, True
    return eq, mdd, False
rng = np.random.default_rng(11)
print('Actual last-year sequence, $300 Standard (0.01 lot minimum)')
for cfg in ['A_sl0.10ADR', 'A_sl0.15ADR', 'A_sl0.20ADR', 'A_sl0.30ADR']:
    g = df[df.cfg == cfg]; R, S = g.r.values, g.sl_usd.values
    for f in (0.03, 0.05, 0.08):
        e, m, h = path(R, S, f)
        out = [path(R[idx], S[idx], f) for idx in (np.concatenate([np.arange(s, s+20) for s in rng.integers(0, len(R)-20, len(R)//20)]) for _ in range(3000))]
        E = np.array([x[0] for x in out]); H = np.array([x[2] for x in out]); M = np.array([x[1] for x in out])
        print(f'{cfg} f={f:.0%}: actual ${e:,.0f} DD {m:.0%}{" HALT" if h else ""} | bootstrap median ${np.median(E):,.0f} p10 ${np.percentile(E,10):,.0f} p90 ${np.percentile(E,90):,.0f} P(halt) {H.mean():.0%} medDD {np.median(M):.0%}')
