# Run three gitee strategies' own signal code on real-tick M1 bars (platform time = GMT+2, +3 in US DST),
# then execute on real ticks: entry at next M1 open, exit at SL / TP / exit_signal (next M1 open). Latest year.
import sys, os, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, us_dst
from gbpkg.asia_range_expansion_continuation import AsiaRangeExpansionContinuationStrategy as S1
from gbpkg.inside_day_breakout import InsideDayNr7BreakoutStrategy as S2
from gbpkg.range_expansion_failure_reversal_swing import RangeExpansionFailureReversalSwingStrategy as S3
R = '/tmp/claude-0/-home-user-claud-aiskill/e7241df1-756a-5746-b13a-2aa88e582b93/scratchpad/gitee_xau/src/repo/research/'
def params(fn):
    p = json.load(open(R + fn, encoding='utf-8-sig'))
    return {k: v for k, v in p.items() if not isinstance(v, (list, dict)) and k not in ('strategy', 'strategy_type', 'timeframe', 'direct_close_rule', 'source_task', 'source_memo_date', 'design_status')}
tt, tb, ta = load('20251102')
m = bars(tt, tb, ta, 60)
off = np.array([3 if us_dst(pd.Timestamp(x, unit='s').date()) else 2 for x in m.ts.values]) * 3600
idx = pd.DatetimeIndex(pd.to_datetime(m.ts.values + off, unit='s'))
df = pd.DataFrame({'open': m.o.values, 'high': m.h.values, 'low': m.l.values, 'close': m.c.values,
                   'volume': (m.i1 - m.i0).values.astype(float)}, index=idx)
utc_open = m.ts.values
def run(name, strat):
    sg = strat.generate_signals(df)
    sig = sg['signal'].to_numpy(); ex = sg['exit_signal'].to_numpy() if 'exit_signal' in sg else np.zeros(len(sg), bool)
    sp = sg['stop_price'].to_numpy() if 'stop_price' in sg else None; tp = sg['take_profit_price'].to_numpy() if 'take_profit_price' in sg else None
    sl_d = sg['stop_loss'].to_numpy() if 'stop_loss' in sg else None; tp_d = sg['take_profit'].to_numpy() if 'take_profit' in sg else None
    trades = []; k = 0; n = len(sg)
    while k < n - 1:
        d = int(sig[k])
        if d == 0: k += 1; continue
        e_bar = k + 1; i0 = int(np.searchsorted(tt, utc_open[e_bar]))
        e = ta[i0] if d > 0 else tb[i0]
        stop = sp[k] if sp is not None and not np.isnan(sp[k]) else (e - d * sl_d[k] if sl_d is not None and not np.isnan(sl_d[k]) else np.nan)
        targ = tp[k] if tp is not None and not np.isnan(tp[k]) else (e + d * tp_d[k] if tp_d is not None and not np.isnan(tp_d[k]) else np.nan)
        risk = (e - stop) * d if not np.isnan(stop) else np.nan
        # exit bar: first exit_signal after entry, else end
        later = np.flatnonzero(ex[e_bar:]); xb = e_bar + later[0] + 1 if len(later) else n - 1
        xb = min(xb, n - 1); i1 = int(np.searchsorted(tt, utc_open[xb]))
        px = tb[i0 + 1:i1 + 1] if d > 0 else ta[i0 + 1:i1 + 1]
        if not len(px) or not (risk > 0): k = xb; continue
        adv = (px - e) * d
        hs = np.flatnonzero(adv <= -risk); ht = np.flatnonzero(adv >= (targ - e) * d) if not np.isnan(targ) else []
        j = min(hs[0] if len(hs) else 10**9, ht[0] if len(ht) else 10**9, len(adv) - 1)
        trades.append(dict(ts=tt[i0], R=adv[j] / risk, S=risk))
        k = int(np.searchsorted(utc_open, tt[i0 + 1 + j], side='right'))
    x = pd.DataFrame(trades)
    if x.empty: print(f'{name}: no trades'); return
    x = x[x.ts >= pd.Timestamp('2025-11-10').timestamp()]
    split = pd.Timestamp('2026-07-01').timestamp(); a, b_ = x[x.ts < split], x[x.ts >= split]
    t_ = x.R.mean() / x.R.std() * np.sqrt(len(x)) if len(x) > 1 else 0
    eq = pk = 300.; mdd = 0; nt = 0
    for r in x.itertuples():
        lots = np.floor(eq * .02 / (r.S * 100) / .01 + 1e-9) * .01
        if lots < .01:
            if r.S / eq > .06: continue
            lots = .01
        eq += lots * 100 * r.S * r.R; nt += 1; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
        if mdd >= .48: break
    print(f'{name}: trades {len(x)} | win {(x.R > 0).mean():.0%} | avg {x.R.mean():+.3f}R | sum {x.R.sum():+.1f}R | t {t_:.2f} | '
          f'Nov-Jun {a.R.sum():+.1f}R ({len(a)}) | Jul-Nov {b_.R.sum():+.1f}R ({len(b_)}) | SL med ${x.S.median():.1f} | '
          f'$300 Std -> ${eq:,.0f} ({eq-300:+,.0f}), {nt} taken, DD {mdd:.0%}')
run('asia_range_expansion_continuation', S1(**params('asia_range_expansion_continuation_params_draft_2026-05-08.json')))
run('inside_day_breakout', S2(**params('inside_day_breakout_5y_params.json')))
run('range_expansion_failure_reversal', S3(**params('range_expansion_failure_reversal_swing_params_draft_2026-05-12.json')))
