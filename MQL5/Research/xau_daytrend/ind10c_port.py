import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from sentinel_bt_run import run
c = pickle.load(open('ind10c.pkl', 'rb')); o2 = pickle.load(open('ssl_opt2.pkl', 'rb'))
E = {'sM15': o2[(900, 320, 20, 1.5)], 'sH1': o2[(3600, 60, None, 1.5)], 'Aroon': c[(3600, 'Aroon')], 'Coral': c[(3600, 'Coral')]}
for nm, ks in (('Aroon H1', ['Aroon']), ('Coral H1', ['Coral']), ('Aroon+Coral H1', ['Aroon', 'Coral']),
               ('SENTINEL std (SSL M15+H1)', ['sM15', 'sH1']), ('SENTINEL std + Coral', ['sM15', 'sH1', 'Coral']), ('SENTINEL std + Aroon + Coral', ['sM15', 'sH1', 'Aroon', 'Coral'])):
    n = sum(len(E[k]) for k in ks); out = []
    for f in (.005, .0075, .01):
        eq, mdd, nn, sk, mon, cv, st, by = run({k: E[k] for k in ks}, f)
        out.append(f'{f:.2%}: ${eq:,.0f} DD {mdd:.0%} lose {sum(v<0 for v in mon.values())}' + (' HALT' if st else ''))
    print(f'{nm:30s} ~{n/12.4:.0f}/mo | ' + ' | '.join(out))
