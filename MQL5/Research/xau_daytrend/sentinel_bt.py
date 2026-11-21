# XAU SENTINEL v1.00 backtest: engines H1 HMA60 (no filter), M15 HMA320 +D1 EMA20, M5 HMA960 +D1 EMA20; SL 1.5 ATR; exit on flip.
# Latest year, real ticks. Sizing from realized equity at entry (engines overlap), DD halt 50% on closed equity.
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt
from bt import load, execute
o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); o3 = pickle.load(open('ssl_opt3.pkl', 'rb'))
ENG = {'H1': o2[(3600, 60, None, 1.5)], 'M15': o2[(900, 320, 20, 1.5)], 'M5': o3[(300, 960, 20, 1.5)]}
tt, tb, ta = load('20251002')
def reexec(x, slip):
    y = execute(tt, tb, ta, x[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].copy(), tps=(0.0,), slip=slip).dropna(subset=['r0.0'])
    y['R'] = y['r0.0']; y['S'] = x.loc[y.index, 'S']; return y
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
MODES = {'มาตรฐาน M15+H1': ['M15', 'H1'], 'ไม้เยอะ M5+M15+H1': ['M5', 'M15', 'H1']}
RISK = {'ต่ำ 0.5%': .005, 'กลาง 0.75%': .0075, 'สูง 1%': .01, 'สูงสุด 1.5%': .015}
rows = []; curves = {}
for slip in (0.0, 0.10):
    E = ENG if slip == 0 else {k: reexec(v, slip) for k, v in ENG.items()}
    for mn, ks in MODES.items():
        for rn, f in RISK.items():
            eq, mdd, n, sk, mon, cv, st, by = run({k: E[k] for k in ks}, f)
            rows.append(dict(slip=slip, acct='Cent', mode=mn, risk=rn, end=eq, DD=mdd, trades=n, lose_m=sum(v < 0 for v in mon.values()), halted=st is not None))
            if slip == 0 and rn == 'กลาง 0.75%': curves[mn] = (cv, mon, by)
        if slip == 0:
            for rn, f in (('กลาง 0.75%', .0075),):
                eq, mdd, n, sk, mon, cv, st, by = run({k: E[k] for k in ks}, f, cent=False)
                rows.append(dict(slip=slip, acct='Standard', mode=mn, risk=rn, end=eq, DD=mdd, trades=n, lose_m=sum(v < 0 for v in mon.values()), halted=st is not None, skipped=sk))
r = pd.DataFrame(rows); pd.set_option('display.width', 220); print(r.round(2).to_string(index=False))
for mn, (cv, mon, by) in curves.items():
    print(f'\n{mn} risk 0.75% monthly USD (Cent USD 300):'); bal = 300
    for k, v in sorted(mon.items()): bal += v; print(f'  {k} {v:+8.1f}  balance {bal:8.1f}')
    print('  by engine:', {k: round(v, 1) for k, v in by.items()})
plt.figure(figsize=(10, 4.5))
for mn, (cv, _, _) in curves.items():
    t, e = zip(*cv); plt.plot(pd.to_datetime(t, unit='s'), e, label=('Standard mode M15+H1' if 'M5' not in mn else 'High-freq mode M5+M15+H1') + ', risk 0.75%')
plt.axhline(300, color='gray', lw=.8); plt.legend(); plt.grid(alpha=.3); plt.ylabel('USD (Cent account, start 300)')
plt.title('XAU SENTINEL v1.00 backtest, real ticks Nov 2025 - Nov 2026'); plt.tight_layout()
plt.savefig('/home/user/claud-aiskill/MQL5/Docs/sentinel/XAU_SENTINEL_equity.png', dpi=120)
r.to_csv('/home/user/claud-aiskill/MQL5/Docs/sentinel/XAU_SENTINEL_backtest.csv', index=False)
