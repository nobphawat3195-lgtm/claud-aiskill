import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pickle, numpy as np, pandas as pd
from sentinel_bt_run import run
g = pickle.load(open('ssl_grid.pkl', 'rb')); o2 = pickle.load(open('ssl_opt2.pkl', 'rb')); o3 = pickle.load(open('ssl_opt3.pkl', 'rb'))
ST = {
 '0 ก่อนออฟติไมซ์ (ค่าเดิม HMA60 ทุก TF, ไม่กรอง D1)': {'H1': g[(3600, 60, False)], 'M15': g[(900, 60, False)], 'M5': g[(300, 60, False)]},
 '1 HMA ยาว 60 ชม. + D1 (M15 240, M5 720)':           {'H1': g[(3600, 60, False)], 'M15': g[(900, 240, True)], 'M5': g[(300, 720, True)]},
 '2 ออฟติไมซ์แล้ว (M15 320, M5 960) = SENTINEL':       {'H1': o2[(3600, 60, None, 1.5)], 'M15': o2[(900, 320, 20, 1.5)], 'M5': o3[(300, 960, 20, 1.5)]},
}
for nm, E in ST.items():
    print(nm)
    for k in ('H1', 'M15', 'M5'): print(f'   {k}: {len(E[k])} ไม้  เฉลี่ย {E[k].R.mean():+.3f}R')
    for mn, ks in (('มาตรฐาน M15+H1', ['M15', 'H1']), ('ไม้เยอะ M5+M15+H1', ['M5', 'M15', 'H1'])):
        out = []
        for f in (.005, .0075, .01):
            eq, mdd, n, sk, mon, cv, st, by = run({k: E[k] for k in ks}, f)
            out.append(f'{f:.2%}: ${eq:,.0f} DD{mdd:.0%}{" หยุด" if st else ""}')
        print(f'   {mn}: ' + ' | '.join(out))
