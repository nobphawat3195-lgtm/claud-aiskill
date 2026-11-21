import numpy as np
def first(mask):
    k = np.flatnonzero(mask); return k[0] if len(k) else None
def manage(tt, tb, ta, pos, iEnd):
    """advance an open position over ticks [pos['i'], iEnd). returns (exit_i, exit_px) or None (still open, state updated)."""
    d = pos['dir']; a = pos['i']
    if a >= iEnd: return None
    px = tb[a:iEnd] if d > 0 else ta[a:iEnd]
    if not pos['be']:
        ks = first(d * (px - pos['sl']) <= 0); k1 = first(d * (px - pos['tp1']) >= 0)
        if ks is not None and (k1 is None or ks < k1): return a + ks, px[ks]
        if k1 is None: pos['i'] = iEnd; return None
        k3 = first(d * (px[k1:] - pos['tp3']) >= 0)
        if k3 == 0: return a + k1, px[k1]
        pos['be'] = True; pos['sl'] = pos['entry']; a = a + k1 + 1; pos['i'] = a
        if a >= iEnd: return None
        px = tb[a:iEnd] if d > 0 else ta[a:iEnd]
    ks = first(d * (px - pos['sl']) <= 0); k3 = first(d * (px - pos['tp3']) >= 0)
    ks = len(px) if ks is None else ks; k3 = len(px) if k3 is None else k3
    if ks == len(px) and k3 == len(px): pos['i'] = iEnd; return None
    k = min(ks, k3); return a + k, px[k]
def engine(tt, tb, ta, sigs, tf, tp1m, tp3m, exp_bars=60):
    """sigs: list of (close_ts, dir, en, sl, mkt) sorted. returns trades list of dict(ts, x, R, S, dir)."""
    trades = []; pos = None; pend = None
    def close(i, p):
        nonlocal pos
        trades.append(dict(ts=pos['ts'], x=tt[min(i, len(tt) - 1)], R=pos['dir'] * (p - pos['entry']) / pos['risk'], S=pos['risk'], dir=pos['dir'])); pos = None
    def step(iEnd):
        nonlocal pos, pend
        while True:
            if pos is not None:
                r = manage(tt, tb, ta, pos, iEnd)
                if r is None: return
                close(*r); continue
            if pend is None: return
            d = pend['dir']; a = pend['i']; ie = pend['ie']; b = min(iEnd, ie)
            if a < b:
                kf = first(ta[a:b] <= pend['entry']) if d > 0 else first(tb[a:b] >= pend['entry'])
                kc = first(tb[a:b] >= pend['tp1']) if d > 0 else first(ta[a:b] <= pend['tp1'])
                if kf is not None and (kc is None or kf <= kc):
                    i = a + kf; e = min(ta[i], pend['entry']) if d > 0 else max(tb[i], pend['entry'])
                    pos = dict(dir=d, entry=e, sl=pend['sl'], tp1=pend['tp1'], tp3=pend['tp3'], risk=abs(e - pend['sl']), i=i + 1, be=False, ts=tt[i]); pend = None
                    if d * (e - pos['sl']) <= 0: close(i, e)
                    continue
                if kc is not None: pend = None; return
            if ie <= iEnd: pend = None; return
            pend['i'] = b; return
    for T, d, en, sl, mkt in sigs:
        iT = int(np.searchsorted(tt, T))
        if iT >= len(tt) - 2: break
        step(iT)
        if (pos is not None and pos['dir'] == d) or (pend is not None and pend['dir'] == d): continue
        if pos is not None and pos['ts'] >= T - tf: continue                      # opposite trade opened this bar
        if pos is not None: close(iT, tb[iT] if pos['dir'] > 0 else ta[iT])       # reversal
        pend = None
        risk = d * (en - sl)
        if risk <= 0: continue
        tp1, tp3 = en + d * risk * tp1m, en + d * risk * tp3m
        if mkt:
            e = ta[iT] if d > 0 else tb[iT]
            if d * (e - sl) <= 0: continue
            pos = dict(dir=d, entry=e, sl=sl, tp1=tp1, tp3=tp3, risk=abs(e - sl), i=iT + 1, be=False, ts=tt[iT])
        else:
            pend = dict(dir=d, entry=en, sl=sl, tp1=tp1, tp3=tp3, i=iT, ie=int(np.searchsorted(tt, T + exp_bars * tf)))
    step(len(tt) - 1)
    return trades
