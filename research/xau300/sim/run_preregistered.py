#!/usr/bin/env python3
"""Run the 4 pre-registered configs (see ../PREREGISTRATION.md) on Dukascopy M1 and write results/.
usage: python3 run_preregistered.py [--data DIR] [--out DIR]"""
import os, sys, json, argparse, datetime as dt
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xau300_sim as S

CONFIGS = {
    "E0_edge_fixed001": dict(fixed_lot=0.01, daily_loss_pct=0.0, max_dd_pct=0.0),
    "P1_safe_1pct": dict(risk_pct=1.0),
    "P2_balanced_2pct": dict(risk_pct=2.0),
    "P3_aggressive_5pct_research": dict(risk_pct=5.0),
}
START, END = dt.datetime(2025, 10, 31), dt.datetime(2026, 10, 31)
MID = dt.datetime(2026, 5, 1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=S.DATA_DIR)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results"))
    a = ap.parse_args(); os.makedirs(a.out, exist_ok=True)
    m1 = S.load_m1(dt.date(2025, 10, 1), dt.date(2026, 11, 1), a.data)
    d1 = S.daily_range_pct(m1)
    man = S.data_manifest(dt.date(2025, 10, 1), dt.date(2026, 11, 1), a.data)
    with open(os.path.join(a.out, "data_manifest.csv"), "w") as f:
        f.write("date,m1_bars,sha256_16\n"); [f.write(f"{d},{n},{h}\n") for d, n, h in man]
    out = {"period": [str(START), str(END)], "bars": len(m1), "first_bar": str(m1[0][0]), "last_bar": str(m1[-1][0]),
           "missing_days": [d for d, n, h in man if h == "MISSING"], "configs": {}}
    curves = {}
    for name, kw in CONFIGS.items():
        cfg = S.Cfg(**kw)
        full = S.run(m1, d1, cfg, START, END)
        s = S.summarize(full, cfg.spread)
        halves = {}
        for lab, (x, y) in {"H1_Nov25-Apr26": (START, MID), "H2_May26-Oct26": (MID, END)}.items():
            # halves re-run from $300 so each half stands alone
            h = S.summarize(S.run(m1, d1, cfg, x, y), cfg.spread)
            halves[lab] = {k: h[k] for k in ("trades", "net", "pf", "eq_dd_pct", "exp_r", "t_r", "halted")}
        s["halves"] = halves; s["config"] = kw
        out["configs"][name] = s; curves[name] = full["curve"]
        print(name, json.dumps({k: s[k] for k in ("trades", "wins", "losses", "breakeven", "net", "pf", "eq_dd_pct", "bal_dd_pct", "exp_r", "t_r", "halted", "skips")}, default=str))
        with open(os.path.join(a.out, f"trades_{name}.csv"), "w") as f:
            f.write("open,close,dir,lots,entry,exit,risk,pl,r,reason\n")
            for t in full["trades"]:
                f.write(f"{t['open']},{t['close']},{t['dir']},{t['lots']},{t['entry']:.3f},{t['exit']:.3f},{t['risk']:.3f},{t['pl']:.2f},{t['r']:.3f},{t['reason']}\n")
    json.dump(out, open(os.path.join(a.out, "summary.json"), "w"), indent=1, default=str)
    try:
        import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
        fig, ax = plt.subplots(2, 1, figsize=(11, 8), gridspec_kw={"height_ratios": [3, 2]})
        for n, c in curves.items():
            if n.startswith("E0"): continue
            ax[0].plot([x[0] for x in c], [x[2] for x in c], label=f"{n}: net ${out['configs'][n]['net']:+.0f}, eqDD {out['configs'][n]['eq_dd_pct']:.1f}%")
        ax[0].axhline(300, color="gray", lw=.6); ax[0].set_ylabel("equity USD"); ax[0].legend(fontsize=8)
        ax[0].set_title("XAU_300_Research_v1 · Python reference sim (Dukascopy M1, spread $0.28) · NOT MT5 real-tick")
        c = curves["E0_edge_fixed001"]
        ax[1].plot([x[0] for x in c], [x[2] - 300 for x in c], color="black", label="E0 edge, fixed 0.01 lot (P/L USD)")
        ax[1].axhline(0, color="gray", lw=.6); ax[1].legend(fontsize=8)
        plt.tight_layout(); plt.savefig(os.path.join(a.out, "equity.png"), dpi=110)
    except ImportError:
        print("matplotlib not installed: chart skipped")


if __name__ == "__main__":
    main()
