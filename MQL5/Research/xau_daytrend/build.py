# raw hourly bi5 -> per-day tick npz (UTC) ; skips days already built unless incomplete
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import os, glob, numpy as np, collections, sys
from parse import load_hour
RAW, OUT = 'raw', 'days'
os.makedirs(OUT, exist_ok=True)
byday = collections.defaultdict(list)
for f in sorted(glob.glob(RAW + '/*.bi5')):
    byday[os.path.basename(f)[:8]].append(f)
n = 0
for day, fs in sorted(byday.items()):
    out = f'{OUT}/{day}.npz'
    if os.path.exists(out) and np.load(out)['nfiles'] == len(fs): continue
    T, B, A = [], [], []
    for f in fs:
        r = load_hour(f)
        if r is None: continue
        T.append(r[0]); B.append(r[1]); A.append(r[2])
    if not T: continue
    np.savez(out, t=np.concatenate(T), b=np.concatenate(B).astype(np.float32),
             a=np.concatenate(A).astype(np.float32), nfiles=len(fs))
    n += 1
print('built', n, 'days; total', len(glob.glob(OUT + '/*.npz')))
