# Port of "HTF Sweep CISD Setups [WillyAlgoTrader] v1.7.1" (Pine) core logic for backtesting.
# Detection on bid bars from Dukascopy ticks (UTC); execution on real ticks (limit fill at ask/bid, exits at bid/ask).
# Defaults as in the indicator: live sweeps of previous HTF H/L + any untaken HTF H/L (lookback 10), pivot 3,
# wait 36 bars, context age 120, displacement 0.5 ATR, min FVG 0.1 ATR, risk 0.25-3 ATR, stop = swept extreme,
# limit entry, skip stale entries, cancel after 60 bars or TP1-before-fill, BE after TP1, close at TP3,
# reversal on opposite signal, same-bar long & short skipped. Not ported: kill zones, PD/SMT/liquidity targets (all off by default).
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
P = dict(PIV=3, MAXWAIT=36, PRE=30, FVGLIFE=120, MAXAGE=120, LOOK=10, DISP=0.5, MINFVG=0.1, MINR=0.25, MAXR=3.0, EXP=60, REQPIV=True)
KEYS = ('trigBar createdBar level levelBar anchor ext extBar rOpen rHigh rLow rMinC rStart rPH rPL rPC rPBar kOpen kHigh kLow '
        'kMinC kStart kPH kPL kPC kPBar obBar xL xC fvgTop fvgBot fvgBar ifTop ifBot ixL ixC ifBar ifXBar brBar brXBar brTop brBot brC bxL bxC').split()
class Ctx:
    def __init__(s, d):
        s.dir = d; s.active = False; s.pvP = []; s.pvB = []; s.pvL = []; s.pvC = []; s.begin(None, None, None, None)
        s.active = False
    def begin(s, lvl, lvlBar, anch, bi):
        for k in KEYS: setattr(s, k, None)
        s.active = True; s.trigBar = bi; s.createdBar = bi; s.level = lvl; s.levelBar = lvlBar; s.anchor = anch
        s.inRun = False; s.obX = s.fvg = s.ifvg = s.brk = False; s.oTop = []; s.oBot = []; s.oBar = []
    def addPivot(s, p, b, lw, cl):
        s.pvP.append(p); s.pvB.append(b); s.pvL.append(lw); s.pvC.append(cl)
        if len(s.pvP) > 40: s.pvP.pop(0); s.pvB.pop(0); s.pvL.pop(0); s.pvC.pop(0)
    def advance(s, bi, o, h, l, c, h1, l1, c1, h2, l2, cnt, a):
        disp = c - o >= P['DISP'] * a; newExt = False
        if cnt and (s.ext is None or l < s.ext): s.ext = l; s.extBar = bi; newExt = True
        if c < o:
            if not s.inRun:
                s.inRun = True; s.rOpen, s.rHigh, s.rLow, s.rMinC, s.rStart = o, h, l, c, bi
                s.rPH, s.rPL, s.rPC, s.rPBar = h1, l1, c1, bi - 1
            else: s.rHigh = max(s.rHigh, h); s.rLow = min(s.rLow, l); s.rMinC = min(s.rMinC, c)
        else: s.inRun = False
        if newExt:
            s.kOpen, s.kHigh, s.kLow, s.kMinC, s.kStart = s.rOpen, s.rHigh, s.rLow, s.rMinC, s.rStart
            s.kPH, s.kPL, s.kPC, s.kPBar = s.rPH, s.rPL, s.rPC, s.rPBar
            s.obX = s.fvg = s.ifvg = s.brk = False
        elif s.inRun and s.rStart == s.kStart: s.kMinC = s.rMinC; s.kLow = s.rLow
        if l2 is not None and h < l2 and l2 - h >= P['MINFVG'] * a: s.oTop.append(l2); s.oBot.append(h); s.oBar.append(bi - 1)
        inWin = cnt and s.extBar is not None and bi >= s.extBar
        for j in range(len(s.oTop) - 1, -1, -1):
            tp = s.oTop[j]; ob = s.oBar[j]; rm = False
            if c > tp and inWin and disp:
                s.ifvg = True; s.ifXBar = bi; s.ifTop = tp; s.ifBot = s.oBot[j]; s.ixL = l; s.ixC = c; s.ifBar = ob - 1; rm = True
            elif c > tp and not inWin: rm = True
            elif bi - ob > P['FVGLIFE']: rm = True
            if rm: del s.oTop[j]; del s.oBot[j]; del s.oBar[j]
        if inWin:
            if s.obX and s.kLow is not None and c < s.kLow: s.obX = False
            if s.ifvg and c < s.ifBot: s.ifvg = False
            if s.brk and s.brBot is not None and c < s.brBot: s.brk = False
            if not s.obX and s.kOpen is not None and c > s.kOpen and disp: s.obX = True; s.obBar = bi; s.xL = l; s.xC = c
            if bi - 2 >= s.extBar and h2 is not None and l > h2 and l - h2 >= P['MINFVG'] * a:
                s.fvg = True; s.fvgTop = l; s.fvgBot = h2; s.fvgBar = bi - 1
            elif s.fvg and c < s.fvgBot: s.fvg = False
            if not s.brk:
                lv = zb = zc = zx = None
                if P['REQPIV']:
                    for j in range(len(s.pvP) - 1, -1, -1):
                        pb = s.pvB[j]
                        if pb < s.extBar and pb + P['PIV'] <= bi: lv, zb, zc, zx = s.pvP[j], s.pvL[j], s.pvC[j], pb; break
                else: lv, zb, zc, zx = s.kPH, s.kPL, s.kPC, s.kPBar
                if lv is not None and c > lv and disp:
                    s.brk = True; s.brXBar = bi; s.brBar = zx; s.brTop = lv; s.brBot = zb; s.brC = zc; s.bxL = l; s.bxC = c

def rma_atr(H, L, C, n=14):
    pc = np.r_[C[0], C[:-1]]; tr = np.maximum(H - L, np.maximum(abs(H - pc), abs(L - pc)))
    return pd.Series(tr).ewm(alpha=1 / n, adjust=False).mean().values

def detect(m, htf, fam, mode):
    """m: bars DataFrame (ts,o,h,l,c). fam in brC/obOpen/fvgCE; mode Limit/Market. Returns signals (bar idx, dir, en, sl, mkt)."""
    O, H, L, C, TS = m.o.values, m.h.values, m.l.values, m.c.values, m.ts.values
    A = rma_atr(H, L, C); hk = TS // htf; N = len(m); PV = P['PIV']
    bull, bear = Ctx(1), Ctx(-1); htfs = []; cur = None; first = False; liqH = []; liqL = []; cnt = 0
    bPrev = sPrev = False; out = []
    def bar(t, i):                                                    # transformed values of bar i
        if t.dir == 1: return O[i], H[i], L[i], C[i]
        return -O[i], -L[i], -H[i], -C[i]
    def run(t, replay, i):
        n = max(0, min(max(i - t.anchor, 0) + P['PRE'], 450, i - 2)) if replay else 0
        for k in range(n, -1, -1):
            bi = i - k; o, h, l, c = bar(t, bi); _, h1, l1, c1 = bar(t, bi - 1); _, h2, l2, _ = bar(t, bi - 2)
            t.advance(bi, o, h, l, c, h1, l1, c1, h2, l2, bi >= t.anchor, A[bi])
    def build(t, i):
        d = t.dir; cT = C[i] if d == 1 else -C[i]
        if t.extBar is None: return None
        if fam == 'brC': e, cb = (t.brC, t.brXBar) if t.brk else (None, None)
        elif fam == 'obOpen': e, cb = (t.kOpen, t.obBar) if t.obX else (None, None)
        else: e, cb = ((t.fvgTop + t.fvgBot) / 2, t.fvgBar + 1) if t.fvg else (None, None)
        if e is None: return None
        s = t.ext
        if mode == 'Limit' and cb is not None:
            for k in range(1, min(i - cb - 1, 400) + 1):
                lw = L[i - k] if d == 1 else -H[i - k]
                if lw <= e: return 'stale'
        if not (e > s and cT > s): return None
        mkt = mode == 'Market' or cT <= e; en = cT if mkt else e; risk = en - s; ra = risk / A[i] if A[i] > 0 else 0
        if not (risk > 0 and cT > s) or ra < P['MINR'] or ra > P['MAXR']: return None
        return (d * en, d * s, mkt, d)
    for i in range(N):
        if i >= 2 * PV:
            j = i - PV
            if H[j] > H[j - PV:j].max() and H[j] > H[j + 1:i + 1].max(): bull.addPivot(H[j], j, L[j], C[j])
            if L[j] < L[j - PV:j].min() and L[j] < L[j + 1:i + 1].min(): bear.addPivot(-L[j], j, -H[j], -C[j])
        trig = {1: None, -1: None}                                      # [lvl, lvlBar, anchor]
        def put(d, lvl, lb, anch):
            t = trig[d]
            if t is None: trig[d] = [lvl, lb, anch]; return
            if (lvl < t[0]) if d == 1 else (lvl > t[0]): t[0] = lvl; t[1] = lb
            t[2] = min(t[2], anch)
        if i == 0 or hk[i] != hk[i - 1]:
            if cur is not None and first:
                htfs.append(cur); cnt += 1; liqH.append([cur[1], cur[5], cnt]); liqL.append([cur[2], cur[6], cnt])
                if len(htfs) > 300: htfs.pop(0)
            if cur is not None: first = True
            cur = [O[i], H[i], L[i], C[i], i, i, i]; bPrev = sPrev = False
        else:
            if H[i] > cur[1]: cur[1] = H[i]; cur[5] = i
            if L[i] < cur[2]: cur[2] = L[i]; cur[6] = i
            cur[3] = C[i]
        if htfs:
            p = htfs[-1]
            if not bPrev and L[i] < p[2]: put(1, p[2], p[6], i); bPrev = True
            if not sPrev and H[i] > p[1]: put(-1, p[1], p[5], i); sPrev = True
        for arr, isH in ((liqL, False), (liqH, True)):
            sw = None
            for j in range(len(arr) - 1, -1, -1):
                q = arr[j]
                if cnt - q[2] >= P['LOOK']: del arr[j]
                elif (H[i] > q[0]) if isH else (L[i] < q[0]):
                    if sw is None or ((q[0] > sw[0]) if isH else (q[0] < sw[0])): sw = (q[0], q[1])
                    del arr[j]
            if sw: put(-1 if isH else 1, sw[0], sw[1], i)
        for t in (bull, bear):
            tg = trig[t.dir]; started = False
            if tg is not None:
                lvT = t.dir * tg[0]
                if not t.active: t.begin(lvT, tg[1], tg[2], i); started = True
                else:
                    t.trigBar = i
                    if lvT < t.level: t.level = lvT; t.levelBar = tg[1]
            if t.active: run(t, started, i)
            if t.active and (i - t.trigBar > P['MAXWAIT'] or i - t.createdBar > P['MAXAGE']): t.active = False
        if i < 50: continue
        plans = []
        for t in (bull, bear):
            if not t.active: continue
            r = build(t, i)
            if r is None: continue
            t.active = False                                            # a formed setup closes the context
            if r != 'stale': plans.append(r)
            else: t.active = True                                       # stale: indicator keeps looking (setup not formed)
        if len(plans) == 2: continue                                    # same-bar long & short: skip both
        for en, sl, mkt, d in plans: out.append((i, d, en, sl, mkt))
    return out
