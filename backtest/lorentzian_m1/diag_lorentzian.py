import sys,datetime as dt,json,warnings;warnings.filterwarnings("ignore");sys.path.insert(0,'/home/claude/gold/src')
from lorentzian_bt import *
import matplotlib;matplotlib.use("Agg");import matplotlib.pyplot as plt
CFG={"C1":dict(),"C2":dict(use_adx=True,adx_thr=20),"C3":dict(use_ema=True,ema_p=200),"C4":dict(sl_atr=1.5,min_sl=5.0)}
a,b=dt.datetime(2025,11,1),dt.datetime(2026,9,1)
T,O,H,L,C=load_tf(dt.date(2025,10,1),dt.date(2026,11,1),1)
cache={};out={}
fig,ax=plt.subplots(figsize=(10,5))
for nm,kw in CFG.items():
    p=P(deposit=1e6,**kw);k=(p.use_adx,p.use_ema)
    if k not in cache: cache[k]=signals(T,O,H,L,C,p)
    r=backtest(T,O,H,L,C,cache[k],p,a,b);tr=r["trades"];s=stats(tr)
    mon={}
    for t in tr:
        m=t["close"].strftime("%Y-%m");mon.setdefault(m,[0,0.0]);mon[m][0]+=1;mon[m][1]+=t["pl"]
    gross=(s["net"]+s["n"]*0.28)/s["n"]
    out[nm]=dict(n=s["n"],net=round(float(s["net"]),1),pf=round(float(s["pf"]),3),t=round(float(s["t"]),2),win=round(float(s["win"]),1),
                 gross_per_trade=round(float(gross),3),net_per_trade=round(float(s["net"]/s["n"]),3),cost=round(s["n"]*0.28,1),
                 neg_months=sum(1 for v in mon.values() if v[1]<0),monthly={m:[v[0],round(v[1],1)] for m,v in sorted(mon.items())})
    print(nm,json.dumps(out[nm]))
    x=[c[0] for c in r["curve"]][::60];y=[c[1]-1e6 for c in r["curve"]][::60]
    ax.plot(x,y,label=f"{nm}: {s['n']} trades, ${s['net']:+.0f}, PF {s['pf']:.2f}")
ax.axhline(0,color="gray",lw=.6);ax.axhline(-300,color="red",lw=.8,ls="--",label="-$300 = deposit wiped")
ax.set_title("Lorentzian M1 (EA defaults) cumulative P/L, selection Nov25-Aug26, 0.01 lot, spread $0.28 (no bust stop)")
ax.set_ylabel("USD");ax.legend(fontsize=8);plt.xticks(rotation=30);plt.tight_layout();plt.savefig("/home/claude/gold/out/lorentzian_m1_selection_nobust.png",dpi=110)
json.dump(out,open("/home/claude/gold/out/lorentzian_m1_selection_nobust.json","w"),indent=1)
