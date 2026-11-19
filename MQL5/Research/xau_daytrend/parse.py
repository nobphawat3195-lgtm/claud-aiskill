import lzma, numpy as np, os, datetime as dt
REC = np.dtype([('ms','>u4'),('ask','>u4'),('bid','>u4'),('av','>f4'),('bv','>f4')])
def load_hour(fn):
    raw = open(fn,'rb').read()
    if not raw: return None
    d = np.frombuffer(lzma.decompress(raw), dtype=REC)
    base = dt.datetime.strptime(os.path.basename(fn)[:10], '%Y%m%d%H').replace(tzinfo=dt.timezone.utc).timestamp()
    t = base + d['ms'].astype(np.float64) / 1000.0
    return t, d['bid'].astype(np.float64) / 1000.0, d['ask'].astype(np.float64) / 1000.0
if __name__ == '__main__':
    import sys
    r = load_hour(sys.argv[1]); t, b, a = r
    print(len(t), dt.datetime.utcfromtimestamp(t[0]), b[:3], a[:3], 'spread med', np.median(a-b))
