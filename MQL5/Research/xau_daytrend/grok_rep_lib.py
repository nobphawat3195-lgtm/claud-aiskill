# Replication of XAU Growth EA v4.10 core modules (ORB_A, DM_A, DM_L, ASIA_B, LON_A) at v4.10 parameters,
# on Dukascopy M1 bid/ask. Exness server = GMT+0 -> broker days are UTC days, Sunday merged into Monday.
# All modules hold to the daily flat (20:30 UTC, 20:00 Friday; minus 1h in US DST), no TP, SL fixed at entry.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd, datetime as dt
from bt import bars, ema, execute, us_dst, eu_dst
from m1 import load_m1

def wilder(x, n): return pd.Series(x).ewm(alpha=1 / n, adjust=False).mean().values
def tr_(h, l, c):
    pc = np.r_[c[0], c[:-1]]; return np.maximum(h - l, np.maximum(abs(h - pc), abs(l - pc)))
def adx(h, l, c, n=14):
    up = np.r_[0, np.diff(h)]; dn = np.r_[0, -np.diff(l)]
    pdm = np.where((up > dn) & (up > 0), up, 0.0); mdm = np.where((dn > up) & (dn > 0), dn, 0.0)
    atr = wilder(tr_(h, l, c), n); pdi = 100 * wilder(pdm, n) / atr; mdi = 100 * wilder(mdm, n) / atr
    dx = 100 * abs(pdi - mdi) / np.maximum(pdi + mdi, 1e-9); return wilder(dx, n), atr


def tday(ts):
    d = pd.to_datetime(ts, unit='s'); return (d + pd.to_timedelta((d.dt.weekday == 6).astype(int), unit='D')).dt.date
