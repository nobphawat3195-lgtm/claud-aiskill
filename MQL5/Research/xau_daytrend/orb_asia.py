import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, ema, execute
START=pd.Timestamp('2025-11-03').timestamp(); SPLIT=pd.Timestamp('2026-07-01').timestamp()
tt,tb,ta=load('20251002')
m=bars(tt,tb,ta,300).reset_index(drop=True); d=bars(tt,tb,ta,86400).reset_index(drop=True)
d['e20']=ema(d.c.values,20); d['e20p']=d.e20.shift(1)
dmap={int(r.ts):(r.c,r.e20,r.e20p) for r in d.itertuples()}
def sigs(cfg):
    rows=[]
    for day in range(int(START//86400)*86400, int(tt[-1])//86400*86400-86400, 86400):
        wd=pd.Timestamp(day,unit='s').weekday()
        if wd>4: continue
        pd_=dmap.get(day-86400*(1 if wd else 3))
        if pd_ is None or np.isnan(pd_[1]): continue
        trend=1 if pd_[0]>pd_[1] else -1
        r=m[(m.ts>=day)&(m.ts<day+3600)]
        if len(r)<10: continue
        hi,lo=r.h.max(),r.l.min(); W=hi-lo
        if W<3 or W>cfg['maxW']: continue
        w=m[(m.ts>=day+3600)&(m.ts<day+cfg['last']*3600)]
        for x in w.itertuples():
            dr=1 if x.c>hi else -1 if x.c<lo else 0
            if dr==0: continue
            if cfg['trend'] and dr!=trend: continue
            i=int(np.searchsorted(tt,x.ts+300))
            e=ta[i] if dr>0 else tb[i]
            sl=(lo if dr>0 else hi) if cfg['sl']=='edge' else ((hi+lo)/2)
            if cfg['sl']=='atr': sl=e-dr*cfg['k']
            rows.append(dict(setup=cfg['n'],i=i,dir=dr,sl=sl,texit=day+cfg['exit']*3600,ts=x.ts+300)); break
    return pd.DataFrame(rows)
def sim(x,tp,f=.02,cap=.055):
    eq=pk=300.;mdd=0;n=0;mon={}
    for r in x.itertuples():
        S=r.S; lots=np.floor(eq*f/(S*100)/.01+1e-9)*.01
        if lots<.01:
            if S/eq>cap: continue
            lots=.01
        pnl=lots*100*S*getattr(r,'R');eq+=pnl;n+=1;pk=max(pk,eq);mdd=max(mdd,1-eq/pk)
        k=pd.Timestamp(r.ts,unit='s').strftime('%y-%m');mon[k]=mon.get(k,0)+pnl
        if mdd>=.48:break
    return eq,mdd,n,mon
cfgs=[dict(n='C1 trend,edgeSL,hold12',trend=1,sl='edge',maxW=16,last=6,exit=12),
      dict(n='C2 trend,midSL,hold12',trend=1,sl='mid',maxW=24,last=6,exit=12),
      dict(n='C3 NO trend,edgeSL,hold12',trend=0,sl='edge',maxW=16,last=6,exit=12),
      dict(n='C4 trend,edgeSL,hold20',trend=1,sl='edge',maxW=16,last=6,exit=20)]
rng=np.random.default_rng(0)
for c in cfgs:
    s=sigs(c)
    if s.empty: print(c['n'],'no trades');continue
    for tp in (0.0,2.0):
        x=execute(tt,tb,ta,s,tps=(tp,)).dropna(subset=[f'r{tp}']).copy(); x['R']=x[f'r{tp}']
        mid=pd.Series((ta[x.i.values]+tb[x.i.values])/2,index=x.index); x['S']=np.abs(mid-x.sl)
        fl=x[['setup','i','dir','sl','texit','ts']].copy(); fl['dir']=-fl.dir; fl['sl']=2*mid.values-x.sl.values
        xf=execute(tt,tb,ta,fl,tps=(tp,)); Rf=xf[f'r{tp}'].fillna(0).values
        dr=np.where(rng.random((5000,len(x)))<.5,x.R.values,Rf).sum(1)
        a,b=x[x.ts<SPLIT],x[x.ts>=SPLIT]
        eq,mdd,n,mon=sim(x,tp)
        print(f"{c['n']} tp{tp}: n={len(x)} win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+.1f}R | Nov-Jun {a.R.sum():+.1f}({len(a)}) Jul-Nov {b.R.sum():+.1f}({len(b)}) | beats rand {(dr<x.R.sum()).mean():.0%} | SLmed {x.S.median():.1f} | $300->{eq:,.0f} DD {mdd:.0%} n{n}")
