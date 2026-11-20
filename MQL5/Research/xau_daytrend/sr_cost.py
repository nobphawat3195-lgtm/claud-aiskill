import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
exec(open('sr_test.py').read().split('x = rep(')[0])
for s in (0.10, 0.15, 0.20, 0.25):
    rep(run(tt, tb, tb + s, days), f'base, spread fixed {s:.2f}')
