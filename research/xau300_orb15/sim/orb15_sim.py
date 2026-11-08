#!/usr/bin/env python3
"""
XAU300_ORB_Research — Python reference simulator (Dukascopy M1 BID, UTC).
Rules = ../PREREGISTRATION.md, mirrored by MQL5/Experts/XAU300_ORB_Research.mq5.
Spec source: anas1412/orb-mt5 @ 0301b3e (MIT). Relative estimate only; not MT5.
"""
import os, sys, math, statistics, datetime as dt
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "xau300", "sim"))
from xau300_sim import load_m1, data_manifest, CONTRACT, DATA_DIR   # shared loader (independent code)


class Cfg:
    def __init__(self, **kw):
        self.deposit = 300.0; self.spread = 0.28
        self.risk_pct = 1.0; self.vol_min = 0.01; self.vol_step = 0.01; self.vol_max = 100.0
        self.fixed_lot = 0.0
        self.daily_loss_pct = 3.0; self.max_dd_pct = 20.0
        self.offset_min = 0                   # server = UTC + offset
        self.range_min = 15; self.entry_window_min = 15; self.hold_min = 90
        self.sl_pct_of_range = 50.0; self.rr = 2.0; self.move_at_r = 0.5; self.move_to_r = -0.5
        self.half_filter = 0.5
        self.roll_sessions = 20; self.roll_min_pct = 0.18; self.roll_strict = True
        self.days = (0, 1, 2, 3)              # Mon-Thu (python weekday)
        self.max_spread_price = 0.60
        # parity-only switches (upstream original behaviour); the EA has none of these
        self.today_min_pct = 0.0             # upstream InpMinRangePercent (per-day range filter)
        self.lot_round = "floor"             # "nearest" = upstream-style rounding (can over-risk)
        self.daily_mode = "flatten"          # "block" = upstream: only blocks new entries
        self.__dict__.update(kw)


def lots_for(equity, sl_dist, cfg):
    if cfg.fixed_lot > 0:
        return cfg.fixed_lot, "fixed"
    loss = sl_dist * CONTRACT
    if loss <= 0:
        return 0.0, "bad_sl"
    raw = equity * cfg.risk_pct / 100.0 / loss / cfg.vol_step
    lots = (round(raw) if cfg.lot_round == "nearest" else math.floor(raw + 1e-9)) * cfg.vol_step
    lots = round(min(lots, cfg.vol_max), 8)
    if lots < cfg.vol_min - 1e-12:
        return 0.0, "below_min_volume"
    return lots, "ok"


def session_ranges(m1, cfg):
    """date -> dict(hi, lo, last_close, n) for the range window of every calendar day present."""
    out = {}
    for ts, o, h, l, c in m1:
        st = dt.datetime(ts.year, ts.month, ts.day) + dt.timedelta(minutes=cfg.offset_min)
        if st <= ts < st + dt.timedelta(minutes=cfg.range_min):
            r = out.get(ts.date())
            if r is None:
                out[ts.date()] = dict(hi=h, lo=l, last_close=c, n=1, last_ts=ts)
            else:
                r["hi"] = max(r["hi"], h); r["lo"] = min(r["lo"], l); r["n"] += 1
                if ts >= r["last_ts"]: r["last_close"] = c; r["last_ts"] = ts
    return out


def rolling_median_pct(ranges, day, cfg):
    vals, back = [], 1
    while len(vals) < cfg.roll_sessions and back <= cfg.roll_sessions * 2 + 20:
        d = day - dt.timedelta(days=back); back += 1
        if d.weekday() >= 5: continue
        r = ranges.get(d)
        if not r or r["n"] < cfg.range_min or r["hi"] <= r["lo"]: continue
        vals.append(100.0 * (r["hi"] - r["lo"]) / r["last_close"])
    if len(vals) < cfg.roll_sessions:
        return None
    return statistics.median(vals)


def run(m1, cfg, t_from, t_to):
    ranges = session_ranges(m1, cfg)
    sp = cfg.spread
    bal = cfg.deposit; peak_eq = bal; halted = False; halt_time = None
    pos = None; trades = []; skips = {}; days = {}
    max_eq_dd = 0.0; peak_bal = bal; max_bal_dd = 0.0; curve = []
    day = None; day_bal = bal; dstate = None; pending = None

    def skip(k): skips[k] = skips.get(k, 0) + 1

    def close(px, ts, why):
        nonlocal bal, pos
        pl = (px - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
        bal += pl
        trades.append(dict(open=pos["t"], close=ts, dir=pos["dir"], lots=pos["lots"], entry=pos["entry"], exit=px,
                           risk=pos["risk"], pl=pl, r=(px - pos["entry"]) * pos["dir"] / pos["risk"], reason=why,
                           moved=pos["moved"], range_pct=pos["range_pct"]))
        pos = None

    for j, (ts, O, H, L, C) in enumerate(m1):
        if ts < t_from: continue
        if ts >= t_to:
            if pos: close(O if pos["dir"] > 0 else O + sp, ts, "end")
            break
        sday = (ts - dt.timedelta(minutes=cfg.offset_min)).date()          # session day in UTC terms
        if sday != day:
            day = sday; day_bal = bal
            dstate = dict(done=False, reason=None)
            if day.weekday() not in cfg.days:
                dstate.update(done=True, reason="weekday")
            else:
                r = ranges.get(ts.date())
                med = rolling_median_pct(ranges, day, cfg)
                dstate["med"] = med
                if med is None and cfg.roll_strict: dstate.update(done=True, reason="roll_insufficient")
                elif med is not None and med < cfg.roll_min_pct: dstate.update(done=True, reason="roll_filter")
            days[day] = dstate
        # 1) pending market order from previous bar close -> fill at this bar open
        if pending:
            d, mid, rp = pending; pending = None
            entry = O + sp if d > 0 else O
            sld = (entry - mid) * d
            if pos: skip("position_open")
            elif halted: skip("dd_halted")
            elif cfg.daily_loss_pct > 0 and bal <= day_bal * (1 - cfg.daily_loss_pct / 100.0): skip("daily_loss")
            elif sld <= 0: skip("bad_sl")
            elif cfg.max_spread_price > 0 and sp > cfg.max_spread_price: skip("spread")
            else:
                lots, why = lots_for(bal, sld, cfg)
                if lots <= 0: skip(why)
                else:
                    pos = dict(dir=d, entry=entry, sl=mid, tp=entry + d * sld * cfg.rr, risk=sld, lots=lots, t=ts,
                               moved=False, range_pct=rp)
        # 2) manage open position on this bar (SL first if both touched)
        if pos:
            d = pos["dir"]
            if (ts - pos["t"]).total_seconds() >= cfg.hold_min * 60:
                close(O if d > 0 else O + sp, ts, "hold")
        if pos:
            d = pos["dir"]
            if d > 0:
                hit_sl = L <= pos["sl"]; hit_tp = H >= pos["tp"]; fav = H - pos["entry"]
            else:
                hit_sl = H + sp >= pos["sl"]; hit_tp = L + sp <= pos["tp"]; fav = pos["entry"] - (L + sp)
            if hit_sl:
                px = min(O, pos["sl"]) if d > 0 else max(O + sp, pos["sl"])
                close(px, ts, "SL_moved" if pos["moved"] else "SL")
            elif hit_tp:
                close(pos["tp"], ts, "TP")
            elif cfg.move_at_r > 0 and not pos["moved"] and fav >= cfg.move_at_r * pos["risk"]:
                pos["sl"] = pos["entry"] + d * cfg.move_to_r * pos["risk"]; pos["moved"] = True
        # 3) equity / DD guard
        if pos:
            adv = (L if pos["dir"] > 0 else H + sp)
            e_low = bal + (adv - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
            e_close = bal + ((C if pos["dir"] > 0 else C + sp) - pos["entry"]) * pos["dir"] * pos["lots"] * CONTRACT
        else:
            e_low = e_close = bal
        max_eq_dd = max(max_eq_dd, (peak_eq - e_low) / peak_eq * 100.0)
        if pos and cfg.daily_mode == "flatten" and cfg.daily_loss_pct > 0 and e_low <= day_bal * (1 - cfg.daily_loss_pct / 100.0):
            thr = day_bal * (1 - cfg.daily_loss_pct / 100.0)                 # trigger price; gaps fill at open
            px = pos["entry"] + (thr - bal) / (pos["dir"] * pos["lots"] * CONTRACT)
            if pos["dir"] > 0: px = min(px, O)
            else: px = max(px, O + sp)
            close(px, ts, "daily_stop"); dstate["done"] = True
            e_low = e_close = bal
        if not halted and cfg.max_dd_pct > 0 and e_low <= peak_eq * (1 - cfg.max_dd_pct / 100.0):
            halted = True; halt_time = ts
            if pos:
                thr = peak_eq * (1 - cfg.max_dd_pct / 100.0)
                close(pos["entry"] + (thr - bal) / (pos["dir"] * pos["lots"] * CONTRACT), ts, "DD_halt")
        peak_eq = max(peak_eq, e_close, bal); peak_bal = max(peak_bal, bal)
        max_bal_dd = max(max_bal_dd, (peak_bal - bal) / peak_bal * 100.0)
        if not curve or curve[-1][0].date() != ts.date() or j % 60 == 0:
            curve.append((ts, bal, e_close))
        # 4) closed-bar break detection (this bar closes now)
        if dstate and not dstate["done"]:
            st = dt.datetime(day.year, day.month, day.day) + dt.timedelta(minutes=cfg.offset_min)
            rend = st + dt.timedelta(minutes=cfg.range_min)
            if ts >= rend + dt.timedelta(minutes=cfg.entry_window_min):
                dstate.update(done=True, reason="no_break")
            elif ts >= rend:
                r = ranges.get(st.date())
                if not r or r["hi"] <= r["lo"]:
                    dstate.update(done=True, reason="no_range")
                elif cfg.today_min_pct > 0 and 100.0 * (r["hi"] - r["lo"]) / r["last_close"] < cfg.today_min_pct:
                    dstate.update(done=True, reason="today_min_pct")
                elif C > r["hi"] or C < r["lo"]:
                    d = 1 if C > r["hi"] else -1
                    cp = (r["last_close"] - r["lo"]) / (r["hi"] - r["lo"])
                    score = cp if d > 0 else 1.0 - cp
                    dstate["done"] = True
                    if cfg.half_filter > 0 and score < cfg.half_filter:
                        dstate["reason"] = "half_filter"
                    else:
                        dstate["reason"] = "signal"
                        mid = r["hi"] - (r["hi"] - r["lo"]) * cfg.sl_pct_of_range / 100.0 if d > 0 \
                            else r["lo"] + (r["hi"] - r["lo"]) * cfg.sl_pct_of_range / 100.0
                        pending = (d, mid, 100.0 * (r["hi"] - r["lo"]) / r["last_close"])
    if pos:
        ts, O, H, L, C = m1[-1]; close(C if pos["dir"] > 0 else C + sp, ts, "end")
    return dict(trades=trades, skips=skips, days=days, bal=bal, net=bal - cfg.deposit, eq_dd=max_eq_dd,
                bal_dd=max_bal_dd, halted=halted, halt_time=halt_time, curve=curve)


def summarize(res, spread=0.28):
    tr = res["trades"]; pl = [t["pl"] for t in tr]; R = [t["r"] for t in tr]
    gp = sum(x for x in pl if x > 0); gl = -sum(x for x in pl if x < 0)
    wins = sum(1 for x in pl if x > 0.005); losses = sum(1 for x in pl if x < -0.005)
    tR = (statistics.mean(R) / statistics.stdev(R) * math.sqrt(len(R))) if len(R) > 2 and statistics.stdev(R) > 0 else 0.0
    mon = {}
    for t in tr:
        k = t["close"].strftime("%Y-%m"); m = mon.setdefault(k, [0, 0.0]); m[0] += 1; m[1] += t["pl"]
    reasons = {}
    for d, s in res["days"].items():
        reasons[s["reason"]] = reasons.get(s["reason"], 0) + 1
    best = max(pl) if pl else 0.0
    return dict(trades=len(tr), wins=wins, losses=losses, breakeven=len(tr) - wins - losses, net=res["net"],
                pf=(gp / gl if gl > 0 else None), gross_profit=gp, gross_loss=gl, eq_dd_pct=res["eq_dd"],
                bal_dd_pct=res["bal_dd"], exp_r=(statistics.mean(R) if R else 0.0), t_r=tR,
                best_trade=best, best_share_pct=(100 * best / res["net"] if res["net"] > 0 else None),
                halted=res["halted"], halt_time=str(res["halt_time"]) if res["halt_time"] else None,
                skips=res["skips"], day_outcomes=reasons,
                exits={x: sum(1 for t in tr if t["reason"] == x) for x in sorted(set(t["reason"] for t in tr))},
                monthly={k: [v[0], round(v[1], 2)] for k, v in sorted(mon.items())},
                spread_cost=sum(t["lots"] * CONTRACT * spread for t in tr))
