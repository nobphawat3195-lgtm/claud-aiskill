# Real-tick verification of DT_0100 (SL 0.3 ADR, exit 20:30 UTC) vs the M1 result, trade by trade.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, prepare, execute
from m1 import load_m1
def signals(t, b, a, d0):
    m5 = prepare(t, b, a); rows = []
    for d, g in m5.groupby('date'):
        g = g[g.wd < 5]
        if str(d).replace('-', '') < d0 or g.trend.isna().all(): continue
        x = g[g.mn + 5 == 60]
        if not len(x) or np.isnan(x.trend.iloc[0]): continue
        T = int(x.trend.iloc[0]); adr = x.adr.iloc[0]; day0 = x.ts.iloc[0] - x.mn.iloc[0] * 60
        rows.append(('DT', int(x.i1.iloc[0]), T, x.c.iloc[0] - T * 0.3 * adr, day0 + (20 * 60 + 30 - x.us.iloc[0]) * 60, x.ts.iloc[0], str(d)))
    s = pd.DataFrame(rows, columns=['setup', 'i', 'dir', 'sl', 'texit', 'ts', 'date'])
    return execute(t, b, a, s, tps=(0.0,))
d0 = sys.argv[1] if len(sys.argv) > 1 else '20260101'
# trend/ADR need ~60 days of history before d0: use M1 for warmup on both, but execute on ticks
import glob
have = sorted(os.path.basename(f)[:8] for f in glob.glob(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'days', '*.npz')))
# earliest day of the contiguous recent block (no calendar gap > 4 days)
dd = pd.to_datetime(pd.Series(have)); gaps = dd.diff().dt.days.fillna(0).values
start = have[int(np.flatnonzero(gaps > 4)[-1])] if (gaps > 4).any() else have[0]
tt, tb, ta = load(start)
d0 = max(d0, start)
mt, mb, ma = load_m1()
cut = tt[0]
# hybrid series: M1 pseudo-ticks before tick coverage, real ticks after (signals use the same bars)
k = np.searchsorted(mt, cut)
ht, hb, ha = np.r_[mt[:k], tt], np.r_[mb[:k], tb], np.r_[ma[:k], ta]
rt = signals(ht, hb, ha, d0)
rm = signals(mt, mb, ma, d0)
m = rt.merge(rm, on='date', suffixes=('_tick', '_m1'))
print('days compared', len(m), 'from', d0)
print('same direction', (m.dir_tick == m.dir_m1).mean().round(3))
print('sum R  tick %.1f  |  M1 %.1f' % (m['r0.0_tick'].sum(), m['r0.0_m1'].sum()))
print('mean R tick %.3f  |  M1 %.3f' % (m['r0.0_tick'].mean(), m['r0.0_m1'].mean()))
print('win rate tick %.2f  |  M1 %.2f' % ((m['r0.0_tick'] > 0).mean(), (m['r0.0_m1'] > 0).mean()))
print('worst loss tick %.2fR | M1 %.2fR' % (m['r0.0_tick'].min(), m['r0.0_m1'].min()))
print('median |R diff| %.3f, 95th pct %.3f' % (np.median(abs(m['r0.0_tick'] - m['r0.0_m1'])), np.percentile(abs(m['r0.0_tick'] - m['r0.0_m1']), 95)))
m['month'] = m.date.str[:7]
print(m.groupby('month')[['r0.0_tick', 'r0.0_m1']].sum().round(1))
m.to_pickle('tickcheck.pkl')
