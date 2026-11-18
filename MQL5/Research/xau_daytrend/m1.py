# Dukascopy M1 BID/ASK candles -> pseudo ticks (4 per minute) so bt.prepare/execute run unchanged.
# Order inside a minute follows MT5's OHLC model: bullish bar O-L-H-C, bearish O-H-L-C.
import os, glob, lzma, datetime as dt, numpy as np
HERE = os.path.dirname(os.path.abspath(__file__))
REC = np.dtype([('s','>u4'),('o','>u4'),('c','>u4'),('l','>u4'),('h','>u4'),('v','>f4')])
def _day(fn):
    raw = open(fn,'rb').read()
    if not raw: return None
    d = np.frombuffer(lzma.decompress(raw), dtype=REC)
    base = dt.datetime.strptime(os.path.basename(fn)[:8], '%Y%m%d').replace(tzinfo=dt.timezone.utc).timestamp()
    return d, base
def load_m1(d0=None, d1=None):
    days = sorted({os.path.basename(f)[:8] for f in glob.glob(os.path.join(HERE,'m1raw','*_BID.bi5'))})
    if d0: days = [x for x in days if x >= d0]
    if d1: days = [x for x in days if x < d1]
    T, B, A = [], [], []
    for day in days:
        fa = os.path.join(HERE,'m1raw',f'{day}_ASK.bi5')
        if not os.path.exists(fa): continue
        rb, ra = _day(os.path.join(HERE,'m1raw',f'{day}_BID.bi5')), _day(fa)
        if rb is None or ra is None: continue
        (bd, base), (ad, _) = rb, ra
        m = (bd['v'] > 0) & (ad['v'] > 0)
        if not m.any(): continue
        bd, ad = bd[m], ad[m]
        t0 = base + bd['s'].astype(np.float64)
        f = lambda x: x.astype(np.float64) / 1000.0
        bo, bc, bl, bh = f(bd['o']), f(bd['c']), f(bd['l']), f(bd['h'])
        ao, ac, al, ah = f(ad['o']), f(ad['c']), f(ad['l']), f(ad['h'])
        bull = bc >= bo
        b2 = np.where(bull, bl, bh); b3 = np.where(bull, bh, bl)
        a2 = np.where(bull, al, ah); a3 = np.where(bull, ah, al)
        T.append(np.stack([t0, t0 + 15, t0 + 30, t0 + 59], 1).ravel())
        B.append(np.stack([bo, b2, b3, bc], 1).ravel())
        A.append(np.stack([ao, a2, a3, ac], 1).ravel())
    t, b, a = np.concatenate(T), np.concatenate(B), np.concatenate(A)
    a = np.maximum(a, b)
    return t, b, a
