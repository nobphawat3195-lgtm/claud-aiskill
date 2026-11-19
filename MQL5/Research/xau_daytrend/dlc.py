import os, sys, time, datetime as dt, urllib.request, concurrent.futures as cf, random
OUT = 'm1raw'; os.makedirs(OUT, exist_ok=True)
start = dt.date(2023,11,1); end = dt.date(2026,11,14)
jobs = []
d = start
while d < end:
    if d.weekday() != 5:
        for side in ('BID', 'ASK'): jobs.append((d, side))
    d += dt.timedelta(days=1)
jobs = jobs[::-1]
def fetch(j):
    d, side = j
    fn = f"{OUT}/{d:%Y%m%d}_{side}.bi5"
    if os.path.exists(fn): return 0
    url = f"https://datafeed.dukascopy.com/datafeed/XAUUSD/{d.year}/{d.month-1:02d}/{d.day:02d}/{side}_candles_min_1.bi5"
    for a in range(8):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent':'Mozilla/5.0'}), timeout=60).read()
            open(fn+'.tmp','wb').write(data); os.replace(fn+'.tmp', fn); return 1
        except urllib.error.HTTPError as e:
            if e.code == 404: open(fn,'wb').close(); return 0
            time.sleep(2**a + random.random())
        except Exception:
            time.sleep(2**a + random.random())
    print('FAIL', url, flush=True); return -1
print('total', len(jobs), flush=True)
with cf.ThreadPoolExecutor(32) as ex:
    for i, r in enumerate(ex.map(fetch, jobs)):
        if i % 100 == 0: print('progress', i, flush=True)
print('DONE', flush=True)
