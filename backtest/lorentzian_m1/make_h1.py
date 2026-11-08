#!/usr/bin/env python3
"""สร้าง data/XAUUSD_H1.csv จาก M1 Dukascopy (UTC) — ใช้กับ ORB kill filter"""
import sys, csv, datetime as dt
sys.path.insert(0,"/home/claude/gold/src")
from engine_m1 import load_m1, resample
m1=load_m1(dt.date(2025,9,1),dt.date(2026,11,1))
h1,order=resample(m1,60)
with open("/home/claude/gold/data/XAUUSD_H1.csv","w",newline="") as f:
    w=csv.writer(f); w.writerow(["time","open","high","low","close"])
    for k in order: o,h,l,c=h1[k]; w.writerow([k.strftime("%Y-%m-%d %H:%M:%S"),o,h,l,c])
print(len(order),"H1 bars")
