import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, ema, execute
START=pd.Timestamp('2025-11-03').timestamp(); SPLIT=pd.Timestamp('2026-07-01').timestamp()
tt,tb,ta=load('20251002')
m=bars(tt,tb,ta,300).reset_index(drop=True); d=bars(tt,tb,ta,86400).reset_index(drop=True)
d['e20']=ema(d.c.values,20)
dmap={int(r.ts):(r.c,r.e20) for r in d.itertuples()}
END=tt[-1]
def run(name,rs,last,ex,maxW,trend=True,reent=1,minW=3):
    rows=[]
    for day in range(int(START//86400)*86400,int(END)//86400*86400-86400,86400):
        wd=pd.Timestamp(day,unit='s').weekday()
        if wd>4: continue
        p=dmap.get(day-86400*(1 if wd else 3))
        if p is None: continue
        tr=1 if p[0]>p[1] else -1
        r=m[(m.ts>=day+rs*3600)&(m.ts<day+(rs+1)*3600)]
        if len(r)<10: continue
        hi,lo=r.h.max(),r.l.min()
        if not(minW<=hi-lo<=maxW): continue
        w=m[(m.ts>=day+(rs+1)*3600)&(m.ts<day+last*3600)]
        busy=0;n=0
        for x in w.itertuples():
            if x.ts+300<busy or n>=reent: continue
            dr=1 if x.c>hi else -1 if x.c<lo else 0
            if dr==0 or (trend and dr!=tr): continue
            i=int(np.searchsorted(tt,x.ts+300)); e=ta[i] if dr>0 else tb[i]
            sl=lo if dr>0 else hi
            s=pd.DataFrame([dict(setup=name,i=i,dir=dr,sl=sl,texit=day+ex*3600,ts=x.ts+300)])
            q=execute(tt,tb,ta,s,tps=(0.0,))
            if np.isnan(q['r0.0'].iloc[0]): continue
            rows.append(dict(setup=name,ts=x.ts+300,x=q['x0.0'].iloc[0],R=q['r0.0'].iloc[0],S=abs((ta[i]+tb[i])/2-sl),dir=dr)); busy=rows[-1]['x']; n+=1
    return pd.DataFrame(rows)
def sim(x,f=.02,cap=.055):
    eq=pk=300.;mdd=0;n=0;mon={}
    for r in x.sort_values('ts').itertuples():
        lots=np.floor(eq*f/(r.S*100)/.01+1e-9)*.01
        if lots<.01:
            if r.S/eq>cap: continue
            lots=.01
        pnl=lots*100*r.S*r.R;eq+=pnl;n+=1;pk=max(pk,eq);mdd=max(mdd,1-eq/pk)
        k=pd.Timestamp(r.ts,unit='s').strftime('%y-%m');mon[k]=mon.get(k,0)+pnl
        if mdd>=.48:break
    return eq,mdd,n,mon
def rep(x,nm):
    a,b=x[x.ts<SPLIT],x[x.ts>=SPLIT];eq,mdd,n,mon=sim(x)
    print(f"{nm}: n={len(x)} ({len(x)/12.5:.1f}/mo) win {(x.R>0).mean():.0%} avg {x.R.mean():+.3f}R sum {x.R.sum():+.1f}R | Nov-Jun {a.R.sum():+.1f}({len(a)}) Jul-Nov {b.R.sum():+.1f}({len(b)}) | $300->{eq:,.0f} DD {mdd:.0%} taken {n}")
    return mon
A=run('ASIA',0,6,12,16)
L=run('LON',7,12,16,16)
N=run('NY',13,17,20,20)
A3=run('ASIA re3',0,6,12,16,reent=3)
L3=run('LON re3',7,12,16,16,reent=3)
rep(A,'A Asia C1');rep(L,'B London 07-08');rep(N,'C NY 13-14');rep(A3,'Asia reent3');rep(L3,'London reent3')
rep(pd.concat([A,L,N]),'D A+B+C')
mon=rep(pd.concat([A3,L3,N]),'E Asia3+Lon3+NY')
print(' '.join(f'{k}:{v:+.0f}' for k,v in sorted(mon.items())))
pd.concat([A,L,N]).to_pickle('orb3_abc.pkl')
