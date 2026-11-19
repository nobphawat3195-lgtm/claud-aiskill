"""Compare a demo / live EA trade log with the backtest assumptions.

Reads the CSV written by the EAs in this repo (header contains time,event,...,req_price,fill_price,spread,...).
Rows with event OPEN* give execution quality; rows with event CLOSE give the net profit in their last field.

Usage: python compare_demo.py xau_dma_trades.csv --bt-spread 0.60 --bt-trades-month 7 --bt-slip 0.0 --start 300

Backtest reference values (Dukascopy real ticks, latest year): median spread about 0.53-0.66 USD,
no slippage assumed, XMS about 34 trades/month once the balance has grown, DM_A about 6-10.
Verdict thresholds are deliberately simple; they flag "look closer", they do not prove anything.
"""
import argparse
import csv
import statistics as st
from collections import Counter


def load(path):
    with open(path, newline='', encoding='utf-8-sig') as f:
        rows = list(csv.reader(f))
    head = [h.strip() for h in rows[0]]
    col = {h: i for i, h in enumerate(head)}
    opens, closes = [], []
    for r in rows[1:]:
        if len(r) < 3 or not r[1]:
            continue
        ev = r[1].strip().upper()
        if ev.startswith('OPEN'):
            def g(name):
                i = col.get(name)
                return float(r[i]) if i is not None and i < len(r) and r[i] not in ('', None) else None
            opens.append(dict(time=r[0], dir=int(float(r[col['dir']])) if r[col['dir']] else 0, lots=g('lots'),
                              req=g('req_price'), fill=g('fill_price'), spread=g('spread')))
        elif ev.startswith('CLOSE'):
            try:
                closes.append(dict(time=r[0], pnl=float(r[-1])))
            except ValueError:
                pass
    return opens, closes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('csv')
    ap.add_argument('--bt-spread', type=float, default=0.60, help='backtest median spread, USD per oz')
    ap.add_argument('--bt-trades-month', type=float, default=None, help='expected trades per month')
    ap.add_argument('--bt-slip', type=float, default=0.0, help='slippage assumed in the backtest, USD per oz')
    ap.add_argument('--start', type=float, default=300.0)
    a = ap.parse_args()
    opens, closes = load(a.csv)
    if not opens:
        print('no OPEN rows found; check the file'); return
    days = sorted({o['time'][:10] for o in opens})
    span = max(1, (len(days) and (int(days[-1][8:10]) - int(days[0][8:10]) + 1 + 30 * (int(days[-1][5:7]) - int(days[0][5:7])))))
    per_month = len(opens) / span * 30
    slip = [(o['fill'] - o['req']) * o['dir'] for o in opens if o['req'] and o['fill']]      # positive = worse than requested
    spr = [o['spread'] for o in opens if o['spread'] is not None]
    pnl = [c['pnl'] for c in closes]
    print(f'file: {a.csv}')
    print(f'trades opened {len(opens)} over ~{span} days  (~{per_month:.1f}/month) | closed {len(closes)}')
    if slip:
        print(f'slippage USD/oz: mean {st.mean(slip):+.3f}  median {st.median(slip):+.3f}  worst {max(slip):+.2f}  (backtest assumed {a.bt_slip:+.2f})')
    if spr:
        print(f'spread at entry USD: median {st.median(spr):.2f}  p90 {sorted(spr)[int(len(spr) * 0.9) - 1]:.2f}  max {max(spr):.2f}  (backtest median {a.bt_spread:.2f})')
    if pnl:
        wins = sum(p > 0 for p in pnl)
        print(f'closed P/L: sum {sum(pnl):+.2f}  win rate {wins / len(pnl):.0%}  best {max(pnl):+.2f}  worst {min(pnl):+.2f}  ({sum(pnl) / a.start:+.1%} of start)')
    print('\nChecks')
    flags = 0
    if spr and st.median(spr) > a.bt_spread * 1.5:
        print(f'  [!] median spread {st.median(spr):.2f} is {st.median(spr) / a.bt_spread:.1f}x the backtest: results will be worse than backtest'); flags += 1
    if slip and st.mean(slip) > 0.15:
        print(f'  [!] mean slippage {st.mean(slip):+.2f} USD/oz on top of the spread (backtest assumed {a.bt_slip:+.2f}): extra cost per trade, re-check the edge'); flags += 1
    if a.bt_trades_month and per_month < 0.5 * a.bt_trades_month:
        print(f'  [!] only {per_month:.1f} trades/month vs {a.bt_trades_month:.0f} expected: signals skipped (min-lot cap, spread guard, wrong server time/GMT offset?)'); flags += 1
    hours = Counter(int(o['time'][11:13]) for o in opens)
    print(f'  entry hours (server time): {dict(sorted(hours.items()))}  -> compare with the strategy windows; a constant shift = wrong InpServerGMTWinter')
    if not flags:
        print('  [ok] no red flags on spread, slippage or trade count')
    print('\nNote: 2-4 weeks is only ~15-40 trades. This tells you whether execution matches the backtest, not whether the strategy is profitable.')


if __name__ == '__main__':
    main()
