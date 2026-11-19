exec(open('orb3.py').read().split("A=run('ASIA'")[0])
R={}
for rs in (0,1,2,3):
    R[rs]=run(f'R{rs}',rs,rs+5,12,16); rep(R[rs],f'range {rs:02d}-{rs+1:02d} entries to {rs+5:02d}, exit 12')
rep(pd.concat([R[0],R[1],R[2],R[3]]),'all four (overlap allowed)')
x=pd.concat([R[0],R[2]]); rep(x,'0+2'); 
x=pd.concat([R[0],R[1],R[2]]); mon=rep(x,'0+1+2'); print(' '.join(f'{k}:{v:+.0f}' for k,v in sorted(mon.items())))
