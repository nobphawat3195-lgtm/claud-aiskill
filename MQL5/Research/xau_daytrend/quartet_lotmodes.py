# XAU QUARTET v1.10 lot modes on Cent USD 300 (30,000 USC), 2 years M1 bid/ask, DD halt 70%.
# Cent: 0.01 lot = 1 USC per $1 move = USD 0.01 per $1 move  ->  cent lots == USD per $1 move. Min 0.01, step 0.01.
# Sizing on closed balance at entry (open P/L not marked; %Equity ~ %Balance here).
import sys, os, pickle; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
E = pickle.load(open('port2y.pkl', 'rb')); KS = ['KST H1', 'Coral H1', 'Gann H1', 'SSL H4']
X = pd.concat([E[k].assign(eng=k) for k in KS]).sort_values('ts').reset_index(drop=True); X['xe'] = X['x0.0']
def sim(mode, p, halt=.70, compound=True, base=300.0):
    closed = []; rows = []; stop = None
    for r in X.itertuples():
        if stop is not None and r.ts >= stop: break
        bal = base + sum(q for t, q in closed if t <= r.ts); cap = bal if compound else base
        if mode == 'pct':     raw = cap * p / r.S
        elif mode == 'money': raw = p / r.S
        elif mode == 'step':  raw = np.floor(cap / p[0]) * p[1]
        else:                 raw = p
        lots = np.floor(raw / .01 + 1e-9) * .01
        if lots < .01:
            if .01 * r.S / bal > .055: continue
            lots = .01
        pnl = lots * r.S * r.R; closed.append((r.xe, pnl))
        rows.append(dict(eng=r.eng, open=pd.Timestamp(r.ts, unit='s'), close=pd.Timestamp(r.xe, unit='s'), dir='BUY' if r.dir > 0 else 'SELL',
                         lots=lots, sl_usd=r.S, R=r.R, pnl=pnl, bal_at_entry=bal, risk_pct=lots * r.S / bal * 100))
        eq = pk = base
        for t, q in sorted(closed):
            eq += q; pk = max(pk, eq)
            if 1 - eq / pk >= halt: stop = t; break
    t = pd.DataFrame(rows); t = t[t.close <= (pd.Timestamp(stop, unit='s') if stop else t.close.max())]
    c = t.sort_values('close'); eq = base + c.pnl.cumsum(); dd = (1 - eq / np.maximum.accumulate(np.r_[base, eq.values])[1:]).max()
    return t, base + t.pnl.sum(), dd, stop
MODES = [('%Equity / %Balance 1.5% ทบต้น', 'pct', .015, True), ('%Equity 1.5% ไม่ทบต้น (ฐาน $300)', 'pct', .015, False),
         ('เงินคงที่ $4.50/ไม้ (=1.5% ของ 300)', 'money', 4.5, True), ('ตามทุน 0.01 ต่อ 3,000 USC (ค่าเริ่มต้น)', 'step', (30, .01), True),
         ('ตามทุน 0.01 ต่อ 1,500 USC', 'step', (15, .01), True), ('ล็อตคงที่ 0.01', 'fixed', .01, True), ('ล็อตคงที่ 0.20', 'fixed', .20, True)]
res = {}
for nm, m, p, cp in MODES:
    t, end, dd, st = sim(m, p, compound=cp); res[nm] = t
    print(f'{nm:40s} | ${end:>9,.0f}  DD {dd:4.0%}  ไม้ {len(t):4d}  เสี่ยงจริงเฉลี่ย {t.risk_pct.mean():4.2f}% (สูงสุด {t.risk_pct.max():4.1f}%)' + (f'  หยุด {pd.Timestamp(st, unit="s"):%Y-%m-%d}' if st else ''))
pickle.dump(res, open('quartet_lotmodes.pkl', 'wb'))
