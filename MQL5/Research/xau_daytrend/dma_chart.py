# EA v5.00 (DM_A) on $300 Standard: equity per year (fresh $300 each year) + monthly P/L.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
import matplotlib; matplotlib.use('Agg'); import matplotlib.pyplot as plt, matplotlib.dates as mdates
src = open('dma_monthly.py').read().split("for title, s0, s1, src in")[0]
exec(src)                                   # builds allr (real ticks for the last year, M1 before) and run()
years = [('Jan 2024 - Oct 2024 (M1)', '2023-11-01', '2024-11-01'),
         ('Nov 2024 - Oct 2025 (M1)', '2024-11-01', '2025-11-01'),
         ('Nov 2025 - Nov 2026 (real ticks)', '2025-11-01', '2026-11-14')]
plt.rcParams.update({'text.usetex': False, 'axes.formatter.use_mathtext': False, 'font.size': 10, 'axes.spines.top': False, 'axes.spines.right': False})
fig, ax = plt.subplots(2, 3, figsize=(16, 8.5), gridspec_kw={'height_ratios': [2.2, 1]})
rows = []
for c, (title, s0, s1) in enumerate(years):
    tr = allr[(pd.to_datetime(allr.ts, unit='s') >= s0) & (pd.to_datetime(allr.ts, unit='s') < s1)]
    g, d, h = run(tr)
    d = d[~d.skip]; t = pd.to_datetime(d.ts, unit='s')
    eq = np.r_[300, d['eq'].values]; tt = pd.DatetimeIndex([t.iloc[0] - pd.Timedelta(days=1)]).append(pd.DatetimeIndex(t))
    peak = np.maximum.accumulate(eq); dd = (eq / peak - 1) * 100
    a = ax[0, c]
    a.plot(tt, eq, color='#1f6feb', lw=1.8, label='Balance')
    a.fill_between(tt, eq, peak, color='#d1242f', alpha=0.18, label='Drawdown from peak')
    a.axhline(300, color='grey', ls='--', lw=0.8)
    a.set_title(f'{title}\nUSD 300 -> {eq[-1]:,.0f} ({eq[-1]-300:+,.0f}) | max DD {(-dd.min()):.0f}% | {len(d)} trades', fontsize=10)
    a.set_ylabel('USD'); a.xaxis.set_major_formatter(mdates.DateFormatter('%b %y')); a.grid(alpha=.25)
    if c == 0: a.legend(loc='upper left', fontsize=8, frameon=False)
    b = ax[1, c]
    cols = ['#1a7f37' if v >= 0 else '#d1242f' for v in g.profit]
    b.bar(range(len(g)), g.profit, color=cols)
    for k, (v, n) in enumerate(zip(g.profit, g.trades)):
        b.text(k, v + (6 if v >= 0 else -6), f'{v:+.0f}\n{n}t', ha='center', va='bottom' if v >= 0 else 'top', fontsize=7)
    b.set_xticks(range(len(g))); b.set_xticklabels([m[2:] for m in g.index], rotation=45, fontsize=8)
    b.axhline(0, color='grey', lw=0.8); b.set_ylabel('Monthly P/L $'); b.grid(axis='y', alpha=.25)
    lim = max(abs(g.profit).max() * 1.45, 50); b.set_ylim(-lim, lim)
    rows.append(g.assign(year=title))
fig.suptitle('XAU DMA EA v5.00 (DM_A) - USD 300 Standard, risk 3%, skip if 0.01 lot > 5% risk', fontsize=13, y=0.995)
fig.tight_layout()
out = '/home/user/claud-aiskill/MQL5/Research/xau_daytrend/dma_v5_equity_300usd.png'
fig.savefig(out, dpi=110); print(out)
pd.concat(rows).to_csv('/home/user/claud-aiskill/MQL5/Research/xau_daytrend/dma_v5_monthly_300usd.csv')
