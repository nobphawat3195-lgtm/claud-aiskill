# market_facilitation_relock_swing (gitee wg722/xauusd-backtest), author's 5y params, ported 1:1.
# H4 bars from real ticks (volume = tick count), UTC (Exness GMT+0). Latest year. Entry: first tick after the H4 close.
# Exits: SL / TP 1.45R / 8 H4 bars (legacy lifecycle). One position at a time, max 3 trades/week, 2 per direction/week.
import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import numpy as np, pandas as pd
from bt import load, bars, execute
P = dict(atr_window=14, facilitation_window=12, signal_window=4, trend_window=8, reset_max_bars=3, min_trend_drift_atr=1.0,
         extreme_facilitation_z=0.9, cooldown_facilitation_z=0.25, relock_facilitation_z=0.45, min_signal_gap=0.1,
         max_reset_depth_atr=0.95, max_entry_extension_atr=0.95, stop_buffer_atr=0.22, target_r=1.45, min_stop_points=2.0,
         max_hold_bars=8, max_trades_per_week=3, same_direction_week_cap=2)
tt, tb, ta = load('20251102')
f = bars(tt, tb, ta, 4 * 3600)
f['volume'] = (f.i1 - f.i0).astype(float)
f['end'] = f.ts + 4 * 3600
pc = f.c.shift(1)
f['atr'] = pd.concat([f.h - f.l, (f.h - pc).abs(), (f.l - pc).abs()], axis=1).max(axis=1).rolling(P['atr_window']).mean()
raw = (f.h - f.l) / f.volume.replace(0, np.nan)
mean = raw.rolling(P['facilitation_window']).mean(); std = raw.rolling(P['facilitation_window']).std(ddof=0).replace(0, np.nan)
f['fz'] = (raw - mean) / std; f['fs'] = f.fz.rolling(P['signal_window']).mean()
endt = pd.to_datetime(f.end, unit='s'); mn = endt.dt.hour * 60 + endt.dt.minute
f['time_ok'] = (mn >= 7 * 60) & (mn <= 20 * 60 + 30)
f['week'] = endt.dt.to_period('W').dt.start_time
f = f.reset_index(drop=True)
sig = []; active_until = -1; wk = {}; wkd = {}
for p in range(len(f)):
    if p <= active_until or not f.time_ok[p]: continue
    row = f.iloc[p]
    if pd.isna(row.atr) or pd.isna(row.fz) or pd.isna(row.fs) or row.atr <= 0: continue
    rs = p - P['reset_max_bars']; ts_ = rs - P['trend_window']
    if ts_ < 0: continue
    tw = f.iloc[ts_:rs]; rw = f.iloc[rs:p]
    if tw[['atr', 'fz', 'fs']].isna().any().any() or rw[['atr', 'fz', 'fs']].isna().any().any(): continue
    move = tw.c.iloc[-1] - tw.c.iloc[0]
    if abs(move) / row.atr < P['min_trend_drift_atr']: continue
    d = 1 if move > 0 else -1
    if tw.fz.max() < P['extreme_facilitation_z'] or rw.fz.iloc[-1] > P['cooldown_facilitation_z']: continue
    if d > 0:
        depth = max(0, tw.c.iloc[-1] - rw.l.min()) / row.atr; ext = max(0, row.c - rw.h.max()) / row.atr
    else:
        depth = max(0, rw.h.max() - tw.c.iloc[-1]) / row.atr; ext = max(0, rw.l.min() - row.c) / row.atr
    if depth > P['max_reset_depth_atr'] or ext > P['max_entry_extension_atr']: continue
    if abs(row.fz - row.fs) < P['min_signal_gap'] or row.fz < P['relock_facilitation_z']: continue
    if wk.get(row.week, 0) >= P['max_trades_per_week'] or wkd.get((row.week, d), 0) >= P['same_direction_week_cap']: continue
    stop = (rw.l.min() - row.atr * P['stop_buffer_atr']) if d > 0 else (rw.h.max() + row.atr * P['stop_buffer_atr'])
    if abs(row.c - stop) < P['min_stop_points']: continue
    ex = min(p + P['max_hold_bars'], len(f) - 1)
    sig.append(dict(setup='MFI', i=int(np.searchsorted(tt, row.end)), dir=d, sl=stop, texit=f.end[ex], ts=row.end))
    active_until = ex; wk[row.week] = wk.get(row.week, 0) + 1; wkd[(row.week, d)] = wkd.get((row.week, d), 0) + 1
s = pd.DataFrame(sig); s = s[s.ts >= pd.Timestamp('2025-11-10').timestamp()].reset_index(drop=True)
x = execute(tt, tb, ta, s, tps=(P['target_r'],)); x['R'] = x[f"r{P['target_r']}"]; x = x.dropna(subset=['R'])
x['S'] = (np.where(x.dir > 0, ta[x.i], tb[x.i]) - x.sl) * x.dir
split = pd.Timestamp('2026-07-01').timestamp()
tr, te = x[x.ts < split], x[x.ts >= split]
t_ = x.R.mean() / x.R.std() * np.sqrt(len(x)) if len(x) > 1 else 0
print(f'trades {len(x)} (~{len(x)/12:.1f}/month) | win {(x.R > 0).mean():.0%} | avg {x.R.mean():+.3f}R | sum {x.R.sum():+.1f}R | t {t_:.2f} | '
      f'Nov-Jun {tr.R.sum():+.1f}R ({len(tr)}) | Jul-Nov {te.R.sum():+.1f}R ({len(te)}) | SL median ${x.S.median():.1f}')
eq = pk = 300.; mdd = 0; n = 0; mon = {}
for r in x.itertuples():
    lots = np.floor(eq * .02 / (r.S * 100) / .01 + 1e-9) * .01
    if lots < .01:
        if r.S / eq > .06: continue
        lots = .01
    pnl = lots * 100 * r.S * r.R; eq += pnl; n += 1; pk = max(pk, eq); mdd = max(mdd, 1 - eq / pk)
    k = pd.Timestamp(r.ts, unit='s').strftime('%y-%m'); mon[k] = mon.get(k, 0) + pnl
    if mdd >= .48: break
print(f'$300 Standard (risk 2%, skip if 0.01 lot > 6%): -> ${eq:,.0f} ({eq-300:+,.0f}) | trades taken {n} | max DD {mdd:.0%}')
print('$/month:', ' '.join(f'{k}:{v:+.0f}' for k, v in sorted(mon.items())))
