#!/usr/bin/env python3
"""
XAU_300_Research_v1 — Python reference simulator (M1 bars, Dukascopy BID, UTC = server GMT+0)

Purpose: give the MQL5 EA an independent, inspectable definition of its rules and a
relative (NOT MT5-equivalent) estimate on Dukascopy M1 data. The MT5 real-tick run on
the user's machine is the source of truth.

Rules mirrored 1:1 by MQL5/Experts/XAU_300_Research_v1.mq5:
  * Opening range: [RangeStartHour, +RangeMinutes) server time; day skipped if < RangeMinutes/3 M1 bars.
  * Signal: closed M5 bar (after range end, hour < EntryEndHour) closes above range high -> BUY,
    below range low -> SELL. Max 1 signal per direction per day (consumed even if not traded).
  * Entry at the open of the next M5 bar (market). SL = opposite side of range (SLRangePct=100),
    TP = TP_R * risk, BE: SL -> entry when price moves BE_TriggerR * risk in favour.
  * Time exit at ExitHour (until 23:00). No Friday. Kill filter: median daily range% of the
    previous 20 D1 bars < KillMedianRangePct -> no trades that day.
  * Max 1 open position. Spread filter: spread <= MaxSpreadPctSL % of SL distance.
  * Sizing: lots = floor(equity*Risk% / loss_per_lot / step)*step. lots < min volume -> SKIP
    (never forced to the minimum). force_min_cap > 0 is a parity-only switch that reproduces the
    old YY19 behaviour (force 0.01 if its loss <= cap% of balance); the EA has no such input.
  * Daily loss stop (% of day-start balance, blocks new entries) and persistent peak-equity DD
    stop (closes position and halts for the rest of the test).
Costs: fixed spread (default $0.28 round trip, applied on the ask side), no commission, no swap
(positions are flat before the daily rollover), contract size 100 oz/lot.
"""
import os, sys, lzma, math, struct, statistics, hashlib, datetime as dt

DATA_DIR = os.environ.get("XAU300_M1_DIR", "/home/claude/gold/data/raw_m1")
CONTRACT = 100.0


# ----------------------------------------------------------------------------- data
def load_m1(start, end, data_dir=DATA_DIR):
    """Dukascopy daily BID_candles_min_1.bi5 files named YYYYMMDD.bi5 -> list of (ts, o, h, l, c)."""
    bars, d = [], start
    while d < end:
        p = os.path.join(data_dir, f"{d:%Y%m%d}.bi5")
        if os.path.exists(p):
            raw = open(p, "rb").read()
            data = lzma.decompress(raw) if raw else b""
            base = dt.datetime(d.year, d.month, d.day)
            for i in range(len(data) // 24):
                sec, o, c, lo, hi, _v = struct.unpack(">IIIIIf", data[i*24:(i+1)*24])
                if o > 0:
                    bars.append((base + dt.timedelta(seconds=sec), o/1000.0, hi/1000.0, lo/1000.0, c/1000.0))
        d += dt.timedelta(days=1)
    bars.sort(key=lambda b: b[0])
    return bars


def data_manifest(start, end, data_dir=DATA_DIR):
    """Coverage + sha256 per daily file, so other machines can confirm they use the same data."""
    rows, d = [], start
    while d < end:
        p = os.path.join(data_dir, f"{d:%Y%m%d}.bi5")
        if os.path.exists(p):
            b = open(p, "rb").read()
            n = len(lzma.decompress(b)) // 24 if b else 0
            rows.append((f"{d:%Y-%m-%d}", n, hashlib.sha256(b).hexdigest()[:16]))
        elif d.weekday() != 5:
            rows.append((f"{d:%Y-%m-%d}", -1, "MISSING"))
        d += dt.timedelta(days=1)
    return rows


def daily_range_pct(m1):
    days = {}
    for ts, o, h, l, c in m1:
        k = ts.date()
        if k in days:
            v = days[k]; v[0] = max(v[0], h); v[1] = min(v[1], l); v[2] = c
        else:
            days[k] = [h, l, c]
    return {k: 100.0*(v[0]-v[1])/v[2] for k, v in days.items()}


# ----------------------------------------------------------------------------- config
class Cfg:
    def __init__(self, **kw):
        self.deposit = 300.0
        self.spread = 0.28
        self.risk_pct = 1.0
        self.vol_min = 0.01; self.vol_step = 0.01; self.vol_max = 100.0
        self.force_min_cap = 0.0            # parity only (old YY19): force min lot if loss <= cap% balance
        self.daily_loss_pct = 3.0
        self.max_dd_pct = 20.0
        self.range_start = 0; self.range_min = 60
        self.entry_end = 20; self.exit_hour = 21
        self.sl_range_pct = 100.0; self.tp_r = 2.0; self.be_trig = 1.0; self.be_lock = 0.0
        self.kill_pct = 1.5; self.kill_days = 20
        self.trade_friday = False
        self.max_spread_pct_sl = 10.0
        self.max_per_dir = 1
        self.fixed_lot = 0.0                # >0: edge study, fixed lot, no sizing skips
        self.__dict__.update(kw)


def lots_for(equity, sl_dist, cfg):
    """Risk-based volume. Returns (lots, reason)."""
    if cfg.fixed_lot > 0:
        return cfg.fixed_lot, "fixed"
    loss_per_lot = sl_dist * CONTRACT
    if loss_per_lot <= 0:
        return 0.0, "bad_sl"
    raw = equity * cfg.risk_pct / 100.0 / loss_per_lot
    lots = math.floor(raw / cfg.vol_step + 1e-9) * cfg.vol_step
    lots = round(min(lots, cfg.vol_max), 8)
    if lots < cfg.vol_min - 1e-12:
        if cfg.force_min_cap > 0 and cfg.vol_min * loss_per_lot <= equity * cfg.force_min_cap / 100.0:
            return cfg.vol_min, "forced_min"
        return 0.0, "below_min_volume"
    return lots, "ok"


# ----------------------------------------------------------------------------- engine
def run(m1, d1pct, cfg, t_from=None, t_to=None):
    T = [b[0] for b in m1]; O = [b[1] for b in m1]; H = [b[2] for b in m1]; L = [b[3] for b in m1]; C = [b[4] for b in m1]
    # M5 closes keyed by bar open time
    m5 = {}
    for ts, o, h, l, c in m1:
        k = ts.replace(minute=(ts.minute//5)*5, second=0)
        m5[k] = c
    sp = cfg.spread
    bal = cfg.deposit; peak_eq = bal; halted = False; halt_time = None
    pos = None; trades = []; signals = []; skips = {}
    day = None; day_bal = bal; st = None; last5 = None
    max_eq_dd = 0.0; max_bal_dd = 0.0; peak_bal = bal; curve = []

    def skip(reason):
        skips[reason] = skips.get(reason, 0) + 1

    def close(px, ts, reason):
        nonlocal bal, pos
        pl = (px - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
        bal += pl
        trades.append(dict(open=pos["t"], close=ts, dir=pos["dir"], lots=pos["lots"], entry=pos["entry"], exit=px,
                           risk=pos["risk"], pl=pl, r=(px - pos["entry"]) * pos["dir"] / pos["risk"], reason=reason,
                           moved=pos["moved"]))
        pos = None

    for j in range(len(T)):
        ts = T[j]
        if t_from and ts < t_from:
            continue
        if t_to and ts >= t_to:
            if pos: close(O[j] if pos["dir"] > 0 else O[j] + sp, ts, "end")
            break
        hour = ts.hour
        if day != ts.date():
            day = ts.date(); day_bal = bal
            st = {"skip": ts.weekday() >= 5 or (ts.weekday() == 4 and not cfg.trade_friday),
                  "ready": False, "armL": True, "armS": True, "cL": 0, "cS": 0, "hi": None, "lo": None}
            if not st["skip"] and cfg.kill_pct > 0:
                prev = [d1pct.get(day - dt.timedelta(days=k)) for k in range(1, 40)]
                prev = [p for p in prev if p is not None][:cfg.kill_days]
                if len(prev) >= 10 and statistics.median(prev) < cfg.kill_pct:
                    st["skip"] = True; st["killed"] = True
        # equity at bar open -> risk manager
        eq_open = bal + ((O[j] - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT if pos else 0.0)
        blocked = halted or (cfg.daily_loss_pct > 0 and eq_open <= day_bal * (1 - cfg.daily_loss_pct/100.0))
        # time exit
        if pos and cfg.exit_hour <= hour < 23:
            close(O[j] if pos["dir"] > 0 else O[j] + sp, ts, "time")
        # signal on closed M5 bar
        if not st["skip"] and hour < cfg.exit_hour:
            rs = dt.datetime(day.year, day.month, day.day, cfg.range_start)
            re_ = rs + dt.timedelta(minutes=cfg.range_min)
            if re_ <= ts and hour < cfg.entry_end:
                if not st["ready"]:
                    sel = [(H[k], L[k]) for k in range(max(0, j - cfg.range_min - 5), j) if rs <= T[k] < re_]
                    if len(sel) < cfg.range_min // 3:
                        st["skip"] = True
                    else:
                        st["hi"] = max(s[0] for s in sel); st["lo"] = min(s[1] for s in sel); st["ready"] = True
                if st["ready"]:
                    bt = ts.replace(minute=(ts.minute//5)*5, second=0) - dt.timedelta(minutes=5)
                    if bt in m5 and bt != last5 and bt >= re_:
                        last5 = bt; cl = m5[bt]
                        if st["lo"] <= cl <= st["hi"]: st["armL"] = st["armS"] = True
                        d = 0
                        if cl > st["hi"] and st["armL"] and st["cL"] < cfg.max_per_dir: d = 1
                        elif cl < st["lo"] and st["armS"] and st["cS"] < cfg.max_per_dir: d = -1
                        if d:
                            if d > 0: st["cL"] += 1; st["armL"] = False
                            else: st["cS"] += 1; st["armS"] = False
                            signals.append((ts, d))
                            dist = (st["hi"] - st["lo"]) * cfg.sl_range_pct / 100.0
                            stop = st["hi"] - dist if d > 0 else st["lo"] + dist
                            entry = O[j] + sp if d > 0 else O[j]
                            sld = entry - stop if d > 0 else stop - entry
                            if pos: skip("position_open")
                            elif halted: skip("dd_halted")
                            elif blocked: skip("daily_loss")
                            elif sld <= 0: skip("bad_sl")
                            elif cfg.max_spread_pct_sl > 0 and sp > sld * cfg.max_spread_pct_sl / 100.0: skip("spread")
                            else:
                                lots, why = lots_for(bal, sld, cfg)
                                if lots <= 0: skip(why)
                                else:
                                    if why == "forced_min": skip("forced_min(info)")
                                    pos = dict(dir=d, entry=entry, sl=entry - d*sld, tp=entry + d*sld*cfg.tp_r,
                                               risk=sld, lots=lots, t=ts, moved=False)
        # intrabar management (SL first if both touched)
        if pos:
            d = pos["dir"]
            if d > 0:
                hit_sl = L[j] <= pos["sl"]; hit_tp = H[j] >= pos["tp"]; fav = H[j] - pos["entry"]
            else:
                hit_sl = H[j] + sp >= pos["sl"]; hit_tp = L[j] + sp <= pos["tp"]; fav = pos["entry"] - (L[j] + sp)
            if hit_sl:
                px = min(O[j], pos["sl"]) if d > 0 else max(O[j] + sp, pos["sl"])
                close(px, ts, "BE" if pos["moved"] else "SL")
            elif hit_tp:
                close(pos["tp"], ts, "TP")
            elif cfg.be_trig > 0 and not pos["moved"] and fav >= cfg.be_trig * pos["risk"]:
                pos["sl"] = pos["entry"] + d * cfg.be_lock * pos["risk"]; pos["moved"] = True
        # equity extremes, persistent peak-equity DD stop
        if pos:
            adv_px = L[j] if pos["dir"] > 0 else H[j] + sp
            e_low = bal + (adv_px - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
            e_close = bal + ((C[j] if pos["dir"] > 0 else C[j] + sp) - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
        else:
            e_low = e_close = bal
        if peak_eq > 0:
            max_eq_dd = max(max_eq_dd, (peak_eq - e_low) / peak_eq * 100.0)
        if not halted and cfg.max_dd_pct > 0 and e_low <= peak_eq * (1 - cfg.max_dd_pct/100.0):
            halted = True; halt_time = ts
            if pos:
                thr = peak_eq * (1 - cfg.max_dd_pct/100.0)
                px = pos["entry"] + (thr - bal) / (pos["dir"] * pos["lots"] * CONTRACT)
                close(px, ts, "DD_halt")
        peak_eq = max(peak_eq, e_close, bal)
        peak_bal = max(peak_bal, bal)
        max_bal_dd = max(max_bal_dd, (peak_bal - bal) / peak_bal * 100.0)
        if not curve or curve[-1][0].date() != ts.date() or j % 60 == 0:
            curve.append((ts, bal, e_close))
    if pos:
        close(C[-1] if pos["dir"] > 0 else C[-1] + sp, T[-1], "end")
    return dict(trades=trades, signals=signals, skips=skips, bal=bal, net=bal - cfg.deposit,
                eq_dd=max_eq_dd, bal_dd=max_bal_dd, halted=halted, halt_time=halt_time, curve=curve)


def summarize(res, spread=0.28):
    tr = res["trades"]; pl = [t["pl"] for t in tr]; R = [t["r"] for t in tr]
    gp = sum(x for x in pl if x > 0); gl = -sum(x for x in pl if x < 0)
    eps = 1e-9
    wins = sum(1 for x in pl if x > eps); losses = sum(1 for x in pl if x < -eps)
    tR = (statistics.mean(R) / statistics.stdev(R) * math.sqrt(len(R))) if len(R) > 2 and statistics.stdev(R) > 0 else 0.0
    mon = {}
    for t in tr:
        k = t["close"].strftime("%Y-%m"); m = mon.setdefault(k, [0, 0.0]); m[0] += 1; m[1] += t["pl"]
    best = max(pl) if pl else 0.0
    return dict(trades=len(tr), wins=wins, losses=losses, breakeven=len(tr) - wins - losses,
                net=res["net"], pf=(gp/gl if gl > 0 else None), gross_profit=gp, gross_loss=gl,
                eq_dd_pct=res["eq_dd"], bal_dd_pct=res["bal_dd"], exp_r=(statistics.mean(R) if R else 0.0), t_r=tR,
                best_trade=best, best_share_pct=(100*best/res["net"] if res["net"] > 0 else None),
                halted=res["halted"], halt_time=str(res["halt_time"]) if res["halt_time"] else None,
                signals=len(res["signals"]), skips=res["skips"],
                exits={x: sum(1 for t in tr if t["reason"] == x) for x in sorted(set(t["reason"] for t in tr))},
                monthly={k: [v[0], round(v[1], 2)] for k, v in sorted(mon.items())},
                spread_cost=sum(t["lots"] * CONTRACT * spread for t in tr))
