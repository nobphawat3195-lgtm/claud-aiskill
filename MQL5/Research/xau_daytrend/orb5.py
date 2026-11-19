exec(open('orb3.py').read().split("A=run('ASIA'")[0])
sys.path.insert(0,'/home/user/claud-aiskill/MQL5/Research/toolkit')
from pbo import pbo, deflated_sharpe
R={rs:run(f'R{rs}',rs,rs+5,12,16) for rs in (0,1,2,3)}
def csim(x,f,cap=.055,halt=.48):
    x=x.sort_values('ts'); closed=[]; eq0=300.; pk=300.; mdd=0; out=[]
    for r in x.itertuples():
        eq=eq0+sum(p for (tx,p) in closed if tx<=r.ts)         # realized equity at entry
        lots=np.floor(eq*f/(r.S*100)/.01+1e-9)*.01
        if lots<.01:
            if r.S/eq>cap: continue
            lots=.01
        closed.append((r.x,lots*100*r.S*r.R))
    cl=sorted(closed); eq=300.;pk=300.;mdd=0
    for tx,p in cl:
        eq+=p;pk=max(pk,eq);mdd=max(mdd,1-eq/pk)
    return eq,mdd,len(cl)
for nm,keys in (('0',[0]),('0+1+2',[0,1,2]),('0-3',[0,1,2,3])):
    x=pd.concat([R[k] for k in keys])
    for f in (.02,.015,.01):
        eq,mdd,n=csim(x,f); print(f'ranges {nm} risk {f:.1%} (concurrent-aware, closed-trade DD): $300 -> {eq:,.0f} DD {mdd:.0%} n {n}')
# PBO / DSR across 8 variants: daily R series
days=pd.date_range('2025-11-03','2026-11-12',freq='D')
def daily(x): 
    s=pd.Series(0.0,index=days); 
    for r in x.itertuples(): s[pd.Timestamp(r.ts,unit='s').normalize()]+=r.R
    return s
var={'r0':R[0],'r1':R[1],'r2':R[2],'r3':R[3],'0+2':pd.concat([R[0],R[2]]),'0+1+2':pd.concat([R[0],R[1],R[2]]),'0-3':pd.concat(R.values())}
M=np.column_stack([daily(v).values for v in var.values()])
print('PBO over',list(var),':',pbo(M,16) if 'S' in pbo.__code__.co_varnames else pbo(M))
for k,v in var.items(): print(k,'DSR(n_trials=14)',deflated_sharpe(daily(v).values,14))
