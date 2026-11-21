# XAU StraddleReverse (v4.40 source logic, v4.60 settings from the user's report) tick simulator on Dukascopy real ticks.
# Flat & in window: Buy Stop ask+D / Sell Stop bid-D (SL each, no TP), placed once and left until hit.
# One fills -> the other stays as the reverse trap; trap trails at bid-GAP (long) / ask+GAP (short), only toward price.
# Trap fills -> old position closed at the same price, new opposite position with SL. No trap after a flip until
# profit >= REVSTART, then trap at bid-GAP / ask+GAP and trails. SL hit -> cooldown, SL count per day; max -> stop for the day.
# Window end -> close everything (InpCloseAllAtSessionEnd=true). Lot 0.01 fixed -> P/L USD = price move.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
def run(tt, tb, ta, days, win=(19*60, 20*60+30), D=1.0, SL=12.0, REV=2.5, GAP=2.4, COOL=300, MAXSL=2, MAXSPR=0.6, slip=0.0, atrok=None):
    trades = []
    for d0 in days:
        s, e = d0 + win[0] * 60, d0 + win[1] * 60
        i0, i1 = np.searchsorted(tt, s), np.searchsorted(tt, e)
        if i1 - i0 < 100: continue
        T, B, A = tt[i0:i1], tb[i0:i1], ta[i0:i1]
        pos = 0; ent = 0.0; sl = 0.0; trap = None; bs = ss = None; cool = 0; nsl = 0; et = 0
        for k in range(len(T)):
            t, b, a = T[k], B[k], A[k]
            if pos == 0:
                if bs is not None:
                    if a >= bs:
                        pos, ent, et = 1, max(bs, a) + slip, t; sl = ent - SL; trap = ss; bs = ss = None
                    elif b <= ss:
                        pos, ent, et = -1, min(ss, b) - slip, t; sl = ent + SL; trap = bs; bs = ss = None
                    else: continue
                else:
                    if t < cool or nsl >= MAXSL or a - b > MAXSPR: continue
                    if atrok is not None and not atrok(t): continue
                    bs, ss = a + D, b - D; continue
            # manage position
            if pos == 1:
                if b <= sl:
                    trades.append((et, t, 1, b - slip - ent, 'SL')); pos = 0; cool = t + COOL; nsl += 1; trap = None; continue
                if trap is not None and b <= trap:
                    px = min(trap, b) - slip; trades.append((et, t, 1, px - ent, 'REV'))
                    pos, ent, et = -1, px, t; sl = ent + SL; trap = None; continue
                if trap is None:
                    if b - ent >= REV: trap = b - GAP
                elif b - GAP > trap: trap = b - GAP
            else:
                if a >= sl:
                    trades.append((et, t, -1, ent - a - slip, 'SL')); pos = 0; cool = t + COOL; nsl += 1; trap = None; continue
                if trap is not None and a >= trap:
                    px = max(trap, a) + slip; trades.append((et, t, -1, ent - px, 'REV'))
                    pos, ent, et = 1, px, t; sl = ent - SL; trap = None; continue
                if trap is None:
                    if ent - a >= REV: trap = a + GAP
                elif a + GAP < trap: trap = a + GAP
        if pos != 0:                                          # session end: close all
            b, a = B[-1], A[-1]
            trades.append((et, T[-1], pos, (b - slip - ent) if pos > 0 else (ent - a - slip), 'END'))
    return pd.DataFrame(trades, columns=['ts', 'x', 'dir', 'pnl', 'why'])
