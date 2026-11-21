import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bt import load
from opt_ind import optimise
from ind10d import ott, mavilimw
tt, tb, ta = load('20251002')
r1 = optimise('OTT (percent x10)', lambda O, H, L, C, n: ott(O, H, L, C, pct=n / 10), 14, tt, tb, ta)
pickle.dump({'OTT': r1}, open('opt_ott.pkl', 'wb'))
