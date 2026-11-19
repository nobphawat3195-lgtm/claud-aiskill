"""Tearsheet + monthly table from a trade list.

Input CSV columns: close_time (UTC, any pandas-parsable format) and pnl (account currency), optional
start balance via --start. Writes an HTML tearsheet (quantstats) and prints the monthly P/L table.
Usage: python report.py trades.csv --start 300 --out report.html --title "XMS v2.90 $300"
"""
import argparse
import pandas as pd
import quantstats as qs


def daily_returns(trades: pd.DataFrame, start: float) -> pd.Series:
    t = trades.copy()
    t['close_time'] = pd.to_datetime(t['close_time'], utc=True).dt.tz_localize(None)
    t = t.sort_values('close_time')
    pnl = t.set_index('close_time')['pnl'].resample('D').sum()
    eq = start + pnl.cumsum()
    prev = eq.shift(1).fillna(start)
    return (pnl / prev).rename('strategy')


def monthly_table(trades: pd.DataFrame, start: float) -> pd.DataFrame:
    t = trades.copy()
    t['close_time'] = pd.to_datetime(t['close_time'], utc=True).dt.tz_localize(None)
    t = t.sort_values('close_time'); t['m'] = t.close_time.dt.to_period('M')
    g = t.groupby('m').agg(trades=('pnl', 'size'), profit=('pnl', 'sum'), wins=('pnl', lambda x: int((x > 0).sum())))
    g['end'] = start + g.profit.cumsum(); g['start'] = g.end - g.profit; g['pct'] = 100 * g.profit / g.start
    return g[['trades', 'wins', 'start', 'profit', 'pct', 'end']].round(1)


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('csv'); ap.add_argument('--start', type=float, default=300.0)
    ap.add_argument('--out', default='report.html'); ap.add_argument('--title', default='Strategy')
    a = ap.parse_args()
    tr = pd.read_csv(a.csv)
    print(monthly_table(tr, a.start).to_string())
    qs.reports.html(daily_returns(tr, a.start), output=a.out, title=a.title)
    print('wrote', a.out)
