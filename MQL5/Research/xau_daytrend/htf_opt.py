import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, ema
from htf_cisd import detect
from htf_engine import engine
START=pd.Timestamp('2025-11-03').timestamp(); SPLIT=pd.Timestamp('2026-07-01').timestamp()
tt,tb,ta=load('20251002')
res=pickle.load(open('htf_res.pkl','rb'))
x=res[(300,'brC','Limit','Bal 1/3R')]
print('M5 brC-Limit outcome mix:', 'loss(<-0.5R)', (x.R<-.5).mean().round(2), 'BE(-0.5..0.5)', ((x.R>=-.5)&(x.R<.5)).mean().round(2), 'TP3', (x.R>=2).mean().round(2))
d=bars(tt,tb,ta,86400).reset_index(drop=True); d['e']=ema(d.c.values,20)
dd={int(r.ts):(1 if r.c>r.e else -1) for r in d.itertuples()}
def trend(T):
    day=int(T//86400*86400)
    for k in range(1,5):
        if day-86400*k in dd: return dd[day-86400*k]
    return 0
rows=[]
for tf,htf in ((300,3600),(900,14400)):
    m=bars(tt,tb,ta,tf).reset_index(drop=True)
    for fam,mode in (('brC','Limit'),('obOpen','Limit')):
        s=[(m.ts.values[i]+tf,dr,en,sl,mk) for i,dr,en,sl,mk in detect(m,htf,fam,mode) if m.ts.values[i]+tf>=START]
        for fn,f in (('none',lambda z:True),('D1trend',lambda z:z[1]==trend(z[0])),('00-07UTC',lambda z:(z[0]%86400)<7*3600),
                     ('trend+00-07',lambda z:z[1]==trend(z[0]) and (z[0]%86400)<7*3600)):
            for tpn,(a,b) in (('1/3R',(1,3)),('0.8/2R',(.8,2))):
                x=pd.DataFrame(engine(tt,tb,ta,[z for z in s if f(z)],tf,a,b))
                if x.empty: continue
                A,B=x[x.ts<SPLIT],x[x.ts>=SPLIT]
                rows.append(dict(cfg=f'M{tf//60} {fam} {fn} {tpn}',n=len(x),avg=x.R.mean(),sum=x.R.sum(),train=A.R.sum(),test=B.R.sum(),ntest=len(B),SL=x.S.median()))
r=pd.DataFrame(rows).sort_values('train',ascending=False)
pd.set_option('display.width',200); print(r.round(3).to_string(index=False))
r.to_pickle('htf_opt.pkl')
