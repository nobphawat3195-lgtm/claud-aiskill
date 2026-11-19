import os, sys, time, datetime as dt, urllib.request, concurrent.futures as cf, random
OUT = sys.argv[1] if len(sys.argv) > 1 else "raw"
start = dt.datetime(2025,11,1); end = dt.datetime(2026,11,14)
os.makedirs(OUT, exist_ok=True)
def hours():
    t = start
    while t < end:
        wd = t.weekday()
        # skip Sat, Sun before 21:00 and Fri after 22:00 (market closed)
        if not (wd == 5 or (wd == 6 and t.hour < 21) or (wd == 4 and t.hour >= 22)):
            yield t
        t += dt.timedelta(hours=1)
def fetch(t):
    fn = os.path.join(OUT, t.strftime('%Y%m%d%H') + '.bi5')
    if os.path.exists(fn): return 0
    url = f"https://datafeed.dukascopy.com/datafeed/XAUUSD/{t.year}/{t.month-1:02d}/{t.day:02d}/{t.hour:02d}h_ticks.bi5"
    for a in range(8):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            d = urllib.request.urlopen(req, timeout=30).read()
            open(fn + '.tmp', 'wb').write(d); os.replace(fn + '.tmp', fn)
            return 1
        except urllib.error.HTTPError as e:
            if e.code == 404: open(fn, 'wb').close(); return 0
            time.sleep(2 ** a + random.random())
        except Exception:
            time.sleep(2 ** a + random.random())
    print('FAIL', url, flush=True); return -1
hs = list(hours())[::-1]; print('total', len(hs), flush=True)
done = 0
with cf.ThreadPoolExecutor(int(os.environ.get("NT","24"))) as ex:
    for i, r in enumerate(ex.map(fetch, hs)):
        if i % 200 == 0: print('progress', i, len(hs), flush=True)
print('DONE', flush=True)
