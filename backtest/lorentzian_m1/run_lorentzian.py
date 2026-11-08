#!/usr/bin/env python3
"""Lorentzian M1 · 4 configs pre-registered (C1-C4) · ใช้: run_lorentzian.py selection | holdout C#"""
import sys, json, datetime as dt
sys.path.insert(0, "/home/claude/gold/src")
from lorentzian_bt import *
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt

CFG = {"C1": dict(), "C2": dict(use_adx=True, adx_thr=20), "C3": dict(use_ema=True, ema_p=200),
       "C4": dict(sl_atr=1.5, min_sl=5.0)}
SEL = (dt.datetime(2025, 11, 1), dt.datetime(2026, 9, 1))
HOLD = (dt.datetime(2026, 9, 1), dt.datetime(2026, 11, 1))
OUT = "/home/claude/gold/out"; import os; os.makedirs(OUT, exist_ok=True)
TH = {1:"ม.ค.",2:"ก.พ.",3:"มี.ค.",4:"เม.ย.",5:"พ.ค.",6:"มิ.ย.",7:"ก.ค.",8:"ส.ค.",9:"ก.ย.",10:"ต.ค.",11:"พ.ย.",12:"ธ.ค."}

mode = sys.argv[1]
names = list(CFG) if mode == "selection" else [sys.argv[2]]
a, b = SEL if mode == "selection" else HOLD
T, O, H, L, C = load_tf(dt.date(2025, 10, 1), dt.date(2026, 11, 1), 1)
print(len(C), "M1 bars", T[0], "->", T[-1]); assert T[0] < a - dt.timedelta(days=20)
res = {}; sig_cache = {}
for nm in names:
    p = P(**CFG[nm])
    key = (p.use_adx, p.use_ema)
    if key not in sig_cache: sig_cache[key] = signals(T, O, H, L, C, p)
    r = backtest(T, O, H, L, C, sig_cache[key], p, a, b)
    s = stats(r["trades"]); tr = r["trades"]
    mon = {}
    for t in tr:
        k = f"{TH[t['close'].month]}{str(t['close'].year)[2:]}"; mon.setdefault(k, [0, 0.0]); mon[k][0] += 1; mon[k][1] += t["pl"]
    halves = {}
    mid = a + (b - a)/2
    for lab, cond in (("H1", lambda t: t["open"] < mid), ("H2", lambda t: t["open"] >= mid)):
        halves[lab] = stats([t for t in tr if cond(t)])
    tR = None
    if nm == "C4":
        R = np.array([t["pl"]/(t["risk"]*100*0.01) for t in tr if t["risk"]])
        tR = float(R.mean()/R.std(ddof=1)*math.sqrt(len(R))) if len(R) > 2 else None
    days = max(1, (min(b, r["busted"] or b) - a).days*5/7)
    res[nm] = dict(stats={k: (float(v) if v == v else None) for k, v in s.items()}, dd=r["dd"], busted=str(r["busted"]) if r["busted"] else None,
                   per_day=s["n"]/days, monthly=mon, halves={h: dict(n=v["n"], net=float(v["net"]), pf=float(v["pf"])) for h, v in halves.items()},
                   tR=tR, cost=s["n"]*p.spread, exits={x: sum(1 for t in tr if t["reason"] == x) for x in set(t["reason"] for t in tr)})
    print(nm, json.dumps(res[nm], ensure_ascii=False, default=str))
    x = [c[0] for c in r["curve"]]; y = [c[1] for c in r["curve"]]
    plt.plot(x[::30], y[::30], label=f"{nm}: {s["n"]} trades, ${s['net']:+.0f}, PF {s['pf']:.2f}")
plt.axhline(300, color="gray", lw=0.6); plt.axhline(0, color="red", lw=0.6)
plt.title(f"Lorentzian M1 equity ({mode}) · spread $0.28 · 0.01 lot · deposit $300"); plt.legend(fontsize=8); plt.xticks(rotation=30); plt.tight_layout()
plt.savefig(f"{OUT}/lorentzian_m1_{mode}.png", dpi=110)
json.dump(res, open(f"{OUT}/lorentzian_m1_{mode}.json", "w"), ensure_ascii=False, indent=1, default=str)
