import sys, os, glob; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, execute
from m1 import load_m1
r = pd.read_pickle('grok_rep.pkl'); r = r[r.setup == 'DM_A'].dropna(subset=['r0.0']).sort_values('ts').reset_index(drop=True)
# real ticks for the last year, M1 before that
tt, tb, ta = load('20251102')
mt, mb, ma = load_m1()
cut = pd.Timestamp('2025-11-03').timestamp()
use_tick = (r.ts >= cut) & (r.ts < tt[-1] - 86400)
rt = r[use_tick].copy(); rt['i'] = np.searchsorted(tt, rt.ts.values)
x = execute(tt, tb, ta, rt[['setup', 'i', 'dir', 'sl', 'texit', 'ts']].reset_index(drop=True), tps=(0.0,))
rt['R'] = x['r0.0'].values; rt['x'] = x['x0.0'].values
rt['S'] = (np.where(rt.dir > 0, ta[rt.i], tb[rt.i]) - rt.sl) * rt.dir
rm = r[~use_tick].copy(); rm['R'] = rm['r0.0']; rm['x'] = rm['x0.0']
rm['S'] = (np.where(rm.dir > 0, ma[rm.i], mb[rm.i]) - rm.sl) * rm.dir
allr = pd.concat([rm, rt]).dropna(subset=['R', 'x', 'S']); allr = allr[allr.S > 0].sort_values('ts')
def run(tr, start=300., f=.03, cap=.05, halt=.45):
    eq = pk = start; rows = []; halted = False
    for x in tr.itertuples():               # one DM_A trade per day, closed the same day -> sequential
        if halted: break
        dd = 1 - eq / pk; ff = f * (.25 if dd >= .4 else .5 if dd >= .25 else 1)
        lots = np.floor(eq * ff / (x.S * 100) / 0.01 + 1e-9) * 0.01
        if lots < 0.01:
            if 0.01 * 100 * x.S / eq > cap: rows.append((x.ts, 0, 0.0, eq, True)); continue
            lots = 0.01
        pnl = lots * 100 * x.S * x.R; eq += pnl; pk = max(pk, eq)
        rows.append((x.ts, lots, pnl, eq, False))
        if 1 - eq / pk >= halt: halted = True
    d = pd.DataFrame(rows, columns=['ts', 'lots', 'pnl', 'eq', 'skip'])
    d['m'] = pd.to_datetime(d.ts, unit='s').dt.strftime('%Y-%m')
    g = d.groupby('m').agg(trades=('skip', lambda s: int((~s).sum())), skipped=('skip', 'sum'), wins=('pnl', lambda p: int((p > 0).sum())),
                           profit=('pnl', 'sum'), end=('eq', 'last'))
    g['start'] = g.end - g.profit; g['pct'] = 100 * g.profit / g.start
    return g, d, halted
for title, s0, s1, src in [('LAST YEAR (real ticks) Nov 2025 - Nov 2026', '2025-11-01', '2026-11-14', 'tick'),
                           ('Nov 2024 - Oct 2025 (M1)', '2024-11-01', '2025-11-01', 'm1'),
                           ('Nov 2023 - Oct 2024 (M1)', '2023-11-01', '2024-11-01', 'm1')]:
    tr = allr[(pd.to_datetime(allr.ts, unit='s') >= s0) & (pd.to_datetime(allr.ts, unit='s') < s1)]
    g, d, h = run(tr)
    print(f'\n=== {title}  start $300 -> ${d['eq'].iloc[-1]:,.0f}  ' + ('HALT' if h else ''))
    print(g[['trades', 'wins', 'skipped', 'start', 'profit', 'pct', 'end']].round(1).to_string())
    print(f'trades {int(g.trades.sum())} | per month avg {g.trades.mean():.1f} | win rate {g.wins.sum()/g.trades.sum():.0%} | profit ${g.profit.sum():,.0f} | avg/month ${g.profit.mean():,.0f} | losing months {(g.profit<0).sum()} of {len(g)}')
