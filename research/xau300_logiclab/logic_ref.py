"""Causal reference (test oracle) for the entry logic of MQL5/Experts/XAU300_ORB_LogicLab_v2.mq5.
Processes CLOSED M1 bars one at a time, exactly as the EA sees them at the first tick of the next bar.
It decides only whether/when TryEnter is called; sizing, exits and guards are the baseline EA's. Not a backtest."""
import datetime as dt


def close_location_ok(bar, direction, min_loc=0.75):
    _t, _o, h, l, c = bar
    rng = h - l
    if rng <= 0:
        return False
    loc = (c - l) / rng if direction > 0 else (h - c) / rng
    return loc >= min_loc


def run_day(bars, hi, lo, last_close, range_end, mode=0, window_min=15, min_loc=0.75, half=0.5, restart_before=None):
    """bars: closed M1 bars (time, open, high, low, close) in time order.
    restart_before: index of the bar at which the EA restarts (pending retest lost, persisted dayDone kept).
    Returns dict(result, dir, signal_bar, entry_bar) where entry_bar is the closed bar after which TryEnter runs."""
    win_end = range_end + dt.timedelta(minutes=window_min)
    done, pend, pend_t, armed = False, 0, None, None
    for i, bar in enumerate(bars):
        t, _o, h, l, c = bar
        if restart_before is not None and i == restart_before:
            pend = 0                                        # pending state is not persisted
        if done and pend == 0:
            return dict(result="restart_cancelled" if armed else "done", dir=0, signal_bar=armed, entry_bar=None)
        if pend:
            if t <= pend_t:
                continue                                    # must be a LATER closed bar
            if t >= win_end:
                return dict(result="retest_expired", dir=0, signal_bar=armed, entry_bar=None)
            if (pend > 0 and c <= hi) or (pend < 0 and c >= lo):
                return dict(result="retest_invalidated", dir=0, signal_bar=armed, entry_bar=None)
            if (pend > 0 and l <= hi) or (pend < 0 and h >= lo):
                return dict(result="enter", dir=pend, signal_bar=armed, entry_bar=t)
            continue
        if t < range_end:
            continue
        if t >= win_end:
            return dict(result="no_break", dir=0, signal_bar=None, entry_bar=None)
        d = 1 if c > hi else (-1 if c < lo else 0)
        if d == 0:
            continue
        done = True                                         # one shot consumed by the first break
        if half > 0:
            cp = (last_close - lo) / (hi - lo)
            if (cp if d > 0 else 1.0 - cp) < half:
                return dict(result="half_filter", dir=0, signal_bar=t, entry_bar=None)
        if mode == 1 and not close_location_ok(bar, d, min_loc):
            return dict(result="close_location", dir=0, signal_bar=t, entry_bar=None)
        if mode == 2:
            pend, pend_t, armed = d, t, t
            continue
        return dict(result="enter", dir=d, signal_bar=t, entry_bar=t)
    return dict(result="pending_at_end" if pend else "no_break", dir=0, signal_bar=armed, entry_bar=None)
