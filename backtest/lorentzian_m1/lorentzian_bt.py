#!/usr/bin/env python3
"""
YOUNGYUU Lorentzian ML EA v1.0 -> Python backtest (M1 bars, Dukascopy BID, UTC)
Port 1:1 ของ feature/filter/kernel/signal จากไฟล์ .mq5 ของผู้ใช้ (ML core: jdehorty, MPL-2.0)
ต่างจาก .mq5 จุดเดียว (ตั้งใจ): ลูป ANN ใช้หน้าต่างเลื่อน i = t-MaxBarsBack .. t-1 (เก่า -> ใหม่)
  เพราะลูปใน .mq5 (start=mbb > sizeLoop -> เดินถอยหลัง) โตแบบ O(N^2) รันทั้งปีไม่ได้
  และ Pine เทียบกับ 2,000 แท่งแรกสุดของกราฟ ซึ่งใช้ใน backtest ไม่ได้
Execution: ตัดสินใจตอนแท่ง t ปิด -> เข้า/ออกที่ open แท่ง t+1
  BUY เข้า O+spread ออก O(bid) · SELL เข้า O(bid) ออก O+spread · lot 0.01 คงที่ ($1 ต่อ $1)
  SL (ถ้ามี) เช็กในแท่ง: BUY L<=SL, SELL H+spread>=SL · gap -> เติมที่ open
"""
import sys, math, datetime as dt
import numpy as np
from numba import njit
sys.path.insert(0, "/home/claude/gold/src")
from engine_m1 import load_m1, resample

NaN = float("nan")
def ok(x): return x == x

class Ema:
    def __init__(s, n): s.a = 2.0/(n+1.0); s.v = 0.0; s.init = False
    def upd(s, x):
        if not ok(x): s.init = False; return NaN
        if not s.init: s.v = x; s.init = True
        else: s.v = s.a*x + (1.0-s.a)*s.v
        return s.v
class Sma:
    def __init__(s, n): s.n = max(1, n); s.buf = [0.0]*s.n; s.pos = 0; s.valid = 0
    def upd(s, x):
        if not ok(x): s.valid = 0; return NaN
        s.buf[s.pos] = x; s.pos = (s.pos+1) % s.n
        if s.valid < s.n: s.valid += 1
        if s.valid < s.n: return NaN
        return sum(s.buf)/s.n
    def meandev(s, m): return sum(abs(b-m) for b in s.buf)/s.n
class Rma:
    def __init__(s, n): s.a = 1.0/max(1, n); s.v = 0.0; s.init = False; s.sma = Sma(n)
    def upd(s, x):
        sm = s.sma.upd(x)
        if not ok(x): s.init = False; return NaN
        if not s.init:
            if not ok(sm): return NaN
            s.v = sm; s.init = True; return s.v
        s.v = s.a*x + (1.0-s.a)*s.v; return s.v
class Norm:
    def __init__(s): s.mn = 10e10; s.mx = -10e10
    def upd(s, x):
        if not ok(x): return NaN
        s.mn = min(x, s.mn); s.mx = max(x, s.mx)
        return (x-s.mn)/max(s.mx-s.mn, 10e-10)
class Rsi:
    def __init__(s, n): s.has = False; s.prev = 0.0; s.up = Rma(n); s.dn = Rma(n)
    def upd(s, x):
        if not s.has: s.prev = x; s.has = True; s.up.upd(NaN); s.dn.upd(NaN); return NaN
        ch = x - s.prev; s.prev = x
        u = s.up.upd(max(ch, 0.0)); d = s.dn.upd(-min(ch, 0.0))
        if not ok(u) or not ok(d): return NaN
        if d == 0: return 100.0
        if u == 0: return 0.0
        return 100.0 - 100.0/(1.0 + u/d)
class Adx:
    def __init__(s, l): s.len = max(1, l); s.trS = s.pS = s.nS = 0.0; s.has = False; s.rma = Rma(s.len); s.ph = s.pl = s.pc = 0.0
    def upd(s, h, l, c):
        h1, l1, c1 = (s.ph, s.pl, s.pc) if s.has else (0.0, 0.0, 0.0)
        tr = max(max(h-l, abs(h-c1)), abs(l-c1))
        dmp = max(h-h1, 0.0) if (h-h1) > (l1-l) else 0.0
        dmn = max(l1-l, 0.0) if (l1-l) > (h-h1) else 0.0
        s.trS = s.trS - s.trS/s.len + tr; s.pS = s.pS - s.pS/s.len + dmp; s.nS = s.nS - s.nS/s.len + dmn
        s.ph, s.pl, s.pc, s.has = h, l, c, True
        dx = NaN
        if s.trS != 0:
            dip = s.pS/s.trS*100.0; din = s.nS/s.trS*100.0
            if dip + din != 0: dx = abs(dip-din)/(dip+din)*100.0
        return s.rma.upd(dx)
RSI, WT, CCI, ADX = 0, 1, 2, 3
class Feat:
    def __init__(s, t, a, b):
        s.t = t; s.nrm = Norm(); s.rsi = Rsi(a); s.e1 = Ema(a if t == WT else b); s.e2 = Ema(a); s.e3 = Ema(b)
        s.s4 = Sma(4); s.cci = Sma(a); s.adx = Adx(a)
    def upd(s, h, l, c):
        if s.t == RSI:
            e = s.e1.upd(s.rsi.upd(c)); return e/100.0 if ok(e) else NaN
        if s.t == WT:
            src = (h+l+c)/3.0; m1 = s.e1.upd(src)
            m2 = s.e2.upd(abs(src-m1) if ok(m1) else NaN)
            ci = (src-m1)/(0.015*m2) if (ok(m1) and ok(m2) and m2 != 0) else NaN
            w1 = s.e3.upd(ci); w2 = s.s4.upd(w1)
            return s.nrm.upd(w1-w2 if (ok(w1) and ok(w2)) else NaN)
        if s.t == CCI:
            m = s.cci.upd(c); cc = NaN
            if ok(m):
                dv = s.cci.meandev(m)
                if dv != 0: cc = (c-m)/(0.015*dv)
            return s.nrm.upd(s.e1.upd(cc))
        if s.t == ADX:
            ad = s.adx.upd(h, l, c); return ad/100.0 if ok(ad) else NaN
        return NaN

@njit(cache=True)
def ann(F, Y, mbb, k, fc, t0):
    n = F.shape[0]; pred = np.zeros(n)
    dist = np.empty(k+2); prd = np.empty(k+2); cnt = 0; p = 0.0
    for t in range(n):
        if t >= t0:
            lastD = -1.0
            for i in range(max(0, t-mbb), t):
                d = 0.0; bad = False
                for f in range(fc):
                    a = F[t, f]; b = F[i, f]
                    if a != a or b != b: bad = True; break
                    d += math.log(1.0 + abs(a-b))
                if bad: continue
                if d >= lastD and i % 4 != 0:
                    lastD = d; dist[cnt] = d; prd[cnt] = Y[i]; cnt += 1
                    if cnt > k:
                        lastD = dist[int(round(k*3.0/4.0))]
                        for j in range(cnt-1): dist[j] = dist[j+1]; prd[j] = prd[j+1]
                        cnt -= 1
            p = 0.0
            for j in range(cnt): p += prd[j]
        pred[t] = p
    return pred

class P:  # parameters (= .mq5 inputs)
    def __init__(s, **kw):
        s.tf = 1; s.neighbors = 8; s.mbb = 2000; s.fc = 5
        s.feats = [(RSI, 14, 1), (WT, 10, 11), (CCI, 20, 1), (ADX, 20, 2), (RSI, 9, 1)]
        s.use_vol = True; s.use_regime = True; s.regime_thr = -0.1; s.use_adx = False; s.adx_thr = 20
        s.use_ema = False; s.ema_p = 200; s.use_sma = False; s.sma_p = 200
        s.use_kernel = True; s.kernel_smooth = False; s.h = 8; s.r = 8.0; s.x = 25; s.lag = 2
        s.hold = 4; s.exit_on_flip = True; s.reverse = True
        s.sl_atr = 0.0; s.min_sl = 5.0       # SL = max(sl_atr*ATR14, min_sl) ถ้า sl_atr>0
        s.spread = 0.28; s.lot = 0.01; s.deposit = 300.0
        s.__dict__.update(kw)

def signals(T, O, H, L, C, p):
    n = len(C); fc = max(2, min(5, p.fc))
    feats = [Feat(*f) for f in p.feats]
    F = np.full((n, 5), NaN); Y = np.zeros(n)
    atr1, atr10, atr14 = Rma(1), Rma(10), Rma(14); A14 = np.full(n, NaN)
    regE, emaT, smaT, adxF = Ema(200), Ema(p.ema_p), Sma(p.sma_p), Adx(14)
    rV1 = rV2 = rPrevSrc = rPrevK = 0.0; rHas = rKValid = False
    filt = np.zeros(n, bool); eUp = np.ones(n, bool); eDn = np.ones(n, bool)
    for t in range(n):
        o, h, l, c = O[t], H[t], L[t], C[t]
        for k in range(5): F[t, k] = feats[k].upd(h, l, c)
        Y[t] = (-1 if C[t-4] < c else 1 if C[t-4] > c else 0) if t >= 4 else 0
        tr = h-l if t == 0 else max(h-l, abs(h-C[t-1]), abs(l-C[t-1]))
        a1 = atr1.upd(tr); a10 = atr10.upd(tr); A14[t] = atr14.upd(tr)
        fVol = (not p.use_vol) or (ok(a1) and ok(a10) and a1 > a10)
        src4 = (o+h+l+c)/4.0
        v1 = 0.2*(src4-rPrevSrc) + 0.8*rV1 if rHas else NaN
        v2 = 0.1*(h-l) + 0.8*rV2; kl = NaN
        if ok(v1) and v2 != 0:
            om = abs(v1/v2); al = (-om**2 + math.sqrt(om**4 + 16.0*om**2))/8.0
            kl = al*src4 + (1.0-al)*(rPrevK if rKValid else 0.0)
        slope = abs(kl-rPrevK) if (ok(kl) and rKValid) else NaN
        em = regE.upd(slope)
        fReg = (not p.use_regime) or (ok(slope) and ok(em) and em != 0 and (slope-em)/em >= p.regime_thr)
        rV1 = v1 if ok(v1) else 0.0; rV2 = v2; rPrevSrc = src4; rHas = True
        if ok(kl): rPrevK = kl; rKValid = True
        else: rKValid = False
        ad = adxF.upd(h, l, c)
        fAdx = (not p.use_adx) or (ok(ad) and ad > p.adx_thr)
        filt[t] = fVol and fReg and fAdx
        e = emaT.upd(c); sm = smaT.upd(c)
        eUp[t] = ((not p.use_ema) or (ok(e) and c > e)) and ((not p.use_sma) or (ok(sm) and c > sm))
        eDn[t] = ((not p.use_ema) or (ok(e) and c < e)) and ((not p.use_sma) or (ok(sm) and c < sm))
    pred = ann(F, Y, p.mbb, max(1, p.neighbors), fc, p.mbb)
    # kernel (rational quadratic / gaussian) ผ่าน convolution
    ii = np.arange(p.x + 2)
    wq = (1.0 + ii**2/(p.h**2*2.0*p.r))**(-p.r)
    hh = max(1, p.h - p.lag); wg = np.exp(-ii**2/(2.0*hh*hh))
    Cn = np.asarray(C)
    def kern(w):
        out = np.full(n, NaN)
        for t in range(p.x+1, n): out[t] = np.dot(Cn[t-len(w)+1:t+1][::-1], w)/w.sum()
        return out
    y1 = kern(wq); y2 = kern(wg) if p.kernel_smooth else None
    sig = np.zeros(n, int); s = 0; held = 0
    startL = np.zeros(n, bool); startS = np.zeros(n, bool); endL = np.zeros(n, bool); endS = np.zeros(n, bool)
    for t in range(n):
        if pred[t] > 0 and filt[t]: s = 1
        elif pred[t] < 0 and filt[t]: s = -1
        sig[t] = s
        changed = t > 0 and sig[t] != sig[t-1]
        held = 0 if changed else held + 1
        isBuy = s == 1 and eUp[t]; isSell = s == -1 and eDn[t]
        lastBuy = t >= 4 and sig[t-4] == 1 and eUp[t-4]; lastSell = t >= 4 and sig[t-4] == -1 and eDn[t-4]
        newBuy = isBuy and changed; newSell = isSell and changed
        if p.use_kernel:
            if p.kernel_smooth:
                bull = ok(y2[t]) and ok(y1[t]) and y2[t] >= y1[t]; bear = ok(y2[t]) and ok(y1[t]) and y2[t] <= y1[t]
            else:
                o3 = t >= 1 and ok(y1[t]) and ok(y1[t-1])
                bull = o3 and y1[t-1] < y1[t]; bear = o3 and y1[t-1] > y1[t]
        else: bull = bear = True
        startL[t] = newBuy and bull and eUp[t]; startS[t] = newSell and bear and eDn[t]
        h4 = held == 4; hl = 0 < held < 4
        endL[t] = ((h4 and lastBuy) or (hl and newSell and lastBuy)) and t >= 4 and startL[t-4]
        endS[t] = ((h4 and lastSell) or (hl and newBuy and lastSell)) and t >= 4 and startS[t-4]
    return dict(sig=sig, startL=startL, startS=startS, endL=endL, endS=endS, A14=A14, pred=pred)

def backtest(T, O, H, L, C, S, p, t_from, t_to):
    """จำลองการเทรดเฉพาะช่วง [t_from, t_to) (เวลา bar open) · สัญญาณคำนวณจากข้อมูลทั้งหมดก่อนหน้า (warm-up)"""
    sp = p.spread; mult = p.lot*100.0
    bal = p.deposit; peak = bal; maxdd = 0.0; trades = []; pos = None; pend = None; curve = []; busted = None
    n = len(C)
    for j in range(n):
        if T[j] < t_from: continue
        if T[j] >= t_to:
            if pos:
                px = O[j] if pos["d"] > 0 else O[j] + sp
                pl = (px - pos["e"])*pos["d"]*mult; bal += pl
                trades.append(dict(open=pos["t"], close=T[j], dir=pos["d"], pl=pl, reason="end", risk=pos["risk"]))
            pos = None; break
        # 1) คำสั่งที่ค้างจากแท่งก่อน -> เติมที่ open[j]
        if pend:
            if pend.get("close") and pos:
                px = O[j] if pos["d"] > 0 else O[j] + sp
                pl = (px - pos["e"])*pos["d"]*mult; bal += pl
                trades.append(dict(open=pos["t"], close=T[j], dir=pos["d"], pl=pl, reason=pend["close"], risk=pos["risk"])); pos = None
            if pend.get("open") and pos is None:
                d, sd = pend["open"]; e = O[j] + sp if d > 0 else O[j]
                pos = dict(d=d, e=e, sl=(e - d*sd) if sd > 0 else None, t=T[j], sig=pend["sig"], risk=sd if sd > 0 else None)
            pend = None
        # 2) SL ในแท่ง
        if pos and pos["sl"] is not None:
            d = pos["d"]
            if d > 0 and L[j] <= pos["sl"]:
                px = min(O[j], pos["sl"]); pl = (px - pos["e"])*mult; bal += pl
                trades.append(dict(open=pos["t"], close=T[j], dir=d, pl=pl, reason="SL", risk=pos["risk"])); pos = None
            elif d < 0 and H[j] + sp >= pos["sl"]:
                px = max(O[j] + sp, pos["sl"]); pl = (pos["e"] - px)*mult; bal += pl
                trades.append(dict(open=pos["t"], close=T[j], dir=d, pl=pl, reason="SL", risk=pos["risk"])); pos = None
        # DD (equity ต่ำสุดในแท่ง เทียบ peak ของ balance)
        if pos:
            adv = ((L[j] - pos["e"]) if pos["d"] > 0 else (pos["e"] - (H[j] + sp)))*mult
            eq_low = bal + adv
        else: eq_low = bal
        peak = max(peak, bal); maxdd = max(maxdd, (peak - eq_low)/peak*100.0 if peak > 0 else 0)
        curve.append((T[j], bal))
        if eq_low <= 0:   # พอร์ตแตก: ปิดที่ราคาปิดแท่งนี้แล้วหยุด
            if pos:
                px = C[j] if pos["d"] > 0 else C[j] + sp
                pl = (px - pos["e"])*pos["d"]*mult; bal += pl
                trades.append(dict(open=pos["t"], close=T[j], dir=pos["d"], pl=pl, reason="bust", risk=pos["risk"])); pos = None
            busted = T[j]; break
        # 3) แท่ง j ปิด -> ตัดสินใจ (เหมือน OnNewBar)
        if j + 1 >= n: continue
        cl = None
        if pos:
            d = pos["d"]; hb = j - pos["sig"]
            if (d > 0 and S["endL"][j]) or (d < 0 and S["endS"][j]): cl = "end4"
            elif hb >= p.hold: cl = "hold"
            elif p.exit_on_flip and S["sig"][j] != d: cl = "flip"
            if p.reverse and ((d > 0 and S["startS"][j]) or (d < 0 and S["startL"][j])): cl = cl or "reverse"
        flat_after = pos is None or cl is not None
        op = None
        if flat_after:
            if S["startL"][j]: op = 1
            elif S["startS"][j]: op = -1
        if cl or op:
            sd = 0.0
            if op and p.sl_atr > 0:
                a = S["A14"][j]; sd = max(p.sl_atr*(a if a == a else 0.0), p.min_sl)
            pend = dict(close=cl, open=(op, sd) if op else None, sig=j)
    return dict(trades=trades, bal=bal, net=bal - p.deposit, dd=maxdd, curve=curve, busted=busted)

def stats(tr, dep=300.0):
    pl = np.array([t["pl"] for t in tr]) if tr else np.zeros(0)
    gp = pl[pl > 0].sum(); gl = -pl[pl <= 0].sum()
    t_ = pl.mean()/pl.std(ddof=1)*math.sqrt(len(pl)) if len(pl) > 2 and pl.std(ddof=1) > 0 else 0.0
    return dict(n=len(pl), net=pl.sum(), pf=gp/gl if gl > 0 else float("inf"), win=(pl > 0).mean()*100 if len(pl) else 0,
                t=t_, best=pl.max() if len(pl) else 0, worst=pl.min() if len(pl) else 0,
                best_share=(pl.max()/pl.sum()*100 if len(pl) and pl.sum() > 0 else float("nan")))

def load_tf(a, b, tf):
    m1 = load_m1(a, b)
    if tf == 1: bars = m1
    else:
        d, order = resample(m1, tf); bars = [(k, *d[k]) for k in order]
    T = [x[0] for x in bars]; O = np.array([x[1] for x in bars]); H = np.array([x[2] for x in bars])
    L = np.array([x[3] for x in bars]); C = np.array([x[4] for x in bars])
    return T, O, H, L, C
