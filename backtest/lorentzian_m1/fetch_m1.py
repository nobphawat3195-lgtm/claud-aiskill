#!/usr/bin/env python3
"""XAUUSD M1 BID จาก Dukascopy รายวัน — cache + resume  (python3 fetch_m1.py W N)"""
import os, sys, time, urllib.request, urllib.error, datetime as dt
RAW="/home/claude/gold/data/raw_m1"; os.makedirs(RAW,exist_ok=True)
BASE="https://datafeed.dukascopy.com/datafeed/XAUUSD"
def fetch(url,tries=6):
    d=4.0
    for _ in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url,headers={"User-Agent":"research-client/1.0"}),timeout=60) as r: return r.read()
        except urllib.error.HTTPError as e:
            if e.code==404: return b""
            time.sleep(d); d*=1.7
        except Exception: time.sleep(d); d*=1.7
    return None
def days(a,b):
    d=a
    while d<=b:
        if d.weekday()!=5: yield d
        d+=dt.timedelta(days=1)
spans=[(dt.date(2025,10,1),dt.date(2025,12,31)),(dt.date(2026,1,1),dt.date(2026,10,31))]
W,N=int(sys.argv[1]),int(sys.argv[2])
for a,b in spans:
    for n,d in enumerate(days(a,b)):
        if n%N!=W: continue
        p=f"{RAW}/{d:%Y%m%d}.bi5"
        if os.path.exists(p): continue
        raw=fetch(f"{BASE}/{d.year}/{d.month-1:02d}/{d.day:02d}/BID_candles_min_1.bi5")
        if raw is None:
            open("/home/claude/gold/data/m1_progress.txt","a").write(f"FAIL {d}\n"); time.sleep(10); continue
        open(p,"wb").write(raw)
        time.sleep(0.3)
    open("/home/claude/gold/data/m1_progress.txt","a").write(f"SPAN_DONE {a} W{W}\n")
