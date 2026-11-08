"""Reference (test oracle) for the capped loss-progression sizing in
MQL5/Experts/XAU300_ORB_CappedRecovery_Research.mq5. Mirrors EffectiveRiskPct, UpdateLevel,
ProcessClosedPosition and LotsForRisk; it is NOT a backtest."""
import math


def effective_risk(base, mult, level, cap, on=True):
    r = base * (mult ** level) if on else base
    return min(r, cap)


def next_level(level, net, on=True, max_level=2, be_tol=0.01):
    """Returns (new_level, event). Win or breakeven -> 0; loss -> +1; loss at max_level -> cycle ends at 0."""
    if not on:
        return 0, "off"
    if net > -be_tol:
        return 0, ("reset_win" if level > 0 else "win_at_0")
    if level < max_level:
        return level + 1, "level_up"
    return 0, "cycle_end"


def position_net(deals, pos_id):
    """deals: dicts with position_id, entry ('in'|'out'|'out_by'|'inout'), volume, profit, swap, commission, fee.
    Returns (net, vol_in, vol_out, fully_closed). Entry-deal fees/commission are included."""
    net = vin = vout = 0.0
    for d in deals:
        if d["position_id"] != pos_id:
            continue
        if d["entry"] == "in":
            vin += d["volume"]
        elif d["entry"] in ("out", "out_by", "inout"):
            vout += d["volume"]
        net += d.get("profit", 0.0) + d.get("swap", 0.0) + d.get("commission", 0.0) + d.get("fee", 0.0)
    return net, vin, vout, (vin > 0 and vout >= vin - 1e-8)


class RecoveryState:
    """Persisted fields: level, track, last_processed (GlobalVariables in the EA)."""

    def __init__(self, on=True, max_level=2, be_tol=0.01, level=0, track=0, last_processed=0):
        self.on, self.max_level, self.be_tol = on, max_level, be_tol
        self.level = 0 if (level < 0 or level > max_level or not on) else level
        self.track, self.last_processed = track, last_processed
        self.events = []

    def process(self, open_position_ids, history):
        """One tick of ProcessClosedPosition."""
        if self.track == 0:
            if open_position_ids:
                self.track = open_position_ids[0]
            return
        if self.track in open_position_ids:          # still open, also after a partial close
            return
        if self.track == self.last_processed:          # already counted (restart / duplicate)
            self.track = 0
            return
        net, vin, vout, closed = position_net(history, self.track)
        if not closed:                                  # history incomplete: retry next tick
            return
        self.level, ev = next_level(self.level, net, self.on, self.max_level, self.be_tol)
        self.events.append((self.track, round(net, 6), ev, self.level))
        self.last_processed, self.track = self.track, 0


def lots_for_risk(equity, risk_pct, loss_per_lot, vmin=0.01, vstep=0.01, vmax=100.0, max_lot=0.10):
    """Floor to integer steps, cap by vmax and max_lot, re-check risk, never force the minimum."""
    if loss_per_lot <= 0:
        return 0.0
    money = equity * risk_pct / 100.0
    fl = lambda v: round(math.floor(v / vstep + 1e-9) * vstep, 8)
    lots = fl(money / loss_per_lot)
    if vmax > 0 and lots > vmax: lots = fl(vmax)
    if max_lot > 0 and lots > max_lot: lots = fl(max_lot)
    while lots >= vmin - 1e-12 and lots * loss_per_lot > money * (1 + 1e-9):
        lots = fl(lots - vstep)
    return lots if lots >= vmin - 1e-12 else 0.0
