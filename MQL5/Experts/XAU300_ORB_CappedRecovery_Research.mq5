//+------------------------------------------------------------------+
//| XAU300_ORB_CappedRecovery_Research.mq5                           |
//| RESEARCH-ONLY Expert Advisor for XAUUSD (MetaTrader 5)           |
//|------------------------------------------------------------------|
//| Entry/exit/one-shot/rolling filter: IDENTICAL to                 |
//|   XAU300_ORB_Research.mq5 (costaware presets: spread gate 0).    |
//|   Rule spec: anas1412/orb-mt5 @ 0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9 |
//|   (MIT License, Copyright (c) 2026 anas1412).                    |
//| Added: capped loss-progression sizing (fractional risk)          |
//|   effectiveRisk% = min(baseRisk% * multiplier^level, RiskCap%)   |
//|   level 0..MaxLevel (max 2). Level changes ONLY when a tracked   |
//|   position is fully closed, on its net result (profit + swap +   |
//|   commission + fee of all its deals, entry fees included):       |
//|   win or breakeven -> 0; loss -> level+1; loss at MaxLevel ->    |
//|   cycle ends, back to 0. Each position id is processed once      |
//|   (persisted), partial closes wait for the full close.           |
//|   Volume floored to step, never forced to the minimum, capped    |
//|   by MaxLot (0.10). No grid, no averaging, one position.         |
//| Guards: daily hard stop 3% (flatten + no entries) - with an      |
//|   effective risk above 3% a loser is normally cut BEFORE its     |
//|   full SL; peak-equity DD stop 30% (default, buffer below the    |
//|   user's 35% backtest limit). Thresholds are triggers, not caps: |
//|   gaps and slippage can exceed them. Nothing guarantees DD<=35%. |
//| Safety: refuses REAL accounts unless AllowRealAccount=true.      |
//|  No DLL, no WebRequest, no credentials. Research only.           |
//+------------------------------------------------------------------+
#property copyright "XAU300_ORB_CappedRecovery_Research (research only); rule spec (c) 2026 anas1412, MIT"
#property version   "1.00"
#property description "Research-only Asia 15-min ORB with capped loss-progression sizing. Not a live-trading recommendation."

#include <Trade\Trade.mqh>

input group "=== Safety ==="
input bool   InpAllowRealAccount   = false;       // Allow REAL account (default false: tester/demo only)
input long   InpMagic              = 300335;      // Magic number
input string InpComment            = "XAU300ORBCR"; // Order comment
input string InpRunTag             = "";          // Run tag printed in logs (set by the runner)

input group "=== Session ==="
input int    InpServerOffsetMinutes = 0;          // Server time minus UTC, minutes (0 for UTC data such as XAUUSD_DUKA)
input int    InpSessionStartHourUTC = 0;          // Session start hour (UTC)
input int    InpSessionStartMinUTC  = 0;          // Session start minute (UTC)
input int    InpRangeMinutes        = 15;         // Range length (minutes, M1 bars)
input int    InpEntryWindowMin      = 15;         // Breaks count only for bars opened this long after the range
input int    InpMaxHoldMinutes      = 90;         // Close a position this long after its fill
input bool   InpTradeMon            = true;       // Trade Monday
input bool   InpTradeTue            = true;       // Trade Tuesday
input bool   InpTradeWed            = true;       // Trade Wednesday
input bool   InpTradeThu            = true;       // Trade Thursday
input bool   InpTradeFri            = false;      // Trade Friday

input group "=== Filters ==="
input double InpHalfFilter          = 0.5;        // Half-of-range filter (0.5 = midpoint, 0 = off)
input int    InpRollSessions        = 20;         // Rolling filter sessions
input double InpRollMinPct          = 0.18;       // Median range % of price must be >= this (0 = off)
input bool   InpRollStrict          = true;       // Not enough history -> no trade
input double InpMaxSpreadPrice      = 0.0;        // Max spread in PRICE units (USD per oz), 0 = off (real spread still paid)

input group "=== Exits ==="
input double InpSLPctOfRange        = 50.0;       // SL distance from breakout side, % of range (50 = midpoint)
input double InpRR                  = 2.0;        // Take profit (R)
input double InpStopMoveAtR         = 0.5;        // Move SL when profit reaches (R), 0 = off
input double InpStopMoveToR         = -0.5;       // ...to (R, signed: -0.5 = half the risk left)

input group "=== Risk ==="
input double InpRiskPercent         = 1.0;        // Base risk per trade (% of equity), level 0
input double InpDailyLossPct        = 3.0;        // Daily hard stop (% of day-start balance): flatten + no entries
input double InpMaxDDPct            = 30.0;       // Persistent peak-equity DD stop (%): flatten + halt (buffer below 35%)
input bool   InpResetState          = false;      // Clear stored peak/halt/day state on init
input double InpMaxMarginUsePct     = 50.0;       // Max margin as % of free margin
input int    InpDeviationPoints     = 30;         // Max slippage (points)
input bool   InpVerbose             = true;       // Log decisions

input group "=== Capped recovery sizing ==="
input bool   InpRecoveryOn          = false;      // Raise risk after losses (capped, max 3 levels)
input double InpRecoveryMultiplier  = 1.5;        // Risk multiplier per level (1.0-3.0)
input int    InpRecoveryMaxLevel    = 2;          // Highest level (0..2); a loss at this level ends the cycle
input double InpRiskCapPercent      = 8.0;        // Hard cap on effective risk (% of equity)
input double InpMaxLot              = 0.10;       // Hard cap on volume (lots)
input double InpBETolerance         = 0.01;       // |net| <= this (account currency) counts as breakeven

input group "=== Research export (Strategy Tester only) ==="
input bool   InpEquityCsv           = false;      // Write M1-sampled balance/equity CSV (tester only)
input string InpEquityFileName      = "";         // CSV in agent MQL5/Files ("" = XAU300_ORB_Research_<RunTag>_equity.csv)

//+------------------------------------------------------------------+
CTrade   g_trade;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;
string   g_key;
double   g_peakEquity = 0.0;
bool     g_halted     = false;
// day state (persisted per account/magic/symbol)
int      g_dayKey     = -1;
double   g_dayStartBal = 0.0;
bool     g_dailyHalt  = false;
bool     g_dayDone    = true;
// session
datetime g_sessStart = 0, g_rangeEnd = 0, g_lastBar = 0;
bool     g_rangeReady = false;
double   g_hi = 0.0, g_lo = 0.0, g_lastClose = 0.0;
int      g_level = 0;                 // recovery level (persisted)
ulong    g_trackPos = 0;              // position id opened by this EA, not yet processed (persisted)
ulong    g_lastProcessed = 0;         // last position id whose result changed the level (persisted)
int c_levelUp = 0, c_resetWin = 0, c_cycleEnd = 0, c_riskAboveDaily = 0;
int      g_eqFile = INVALID_HANDLE;
datetime g_eqLastMin = 0;

int c_breaks = 0, c_opened = 0, c_half = 0, c_roll = 0, c_rollInsufficient = 0, c_noBreak = 0, c_skipPos = 0,
    c_skipSpread = 0, c_skipMinVol = 0, c_skipMargin = 0, c_skipStops = 0, c_skipCheck = 0, c_sendFail = 0,
    c_stopMoves = 0, c_holdExits = 0, c_dailyStops = 0, c_ddHalts = 0, c_closeFail = 0;

//+------------------------------------------------------------------+
void Log(const string s) { if(InpVerbose) Print("XAU300ORBCR|", InpRunTag, "|", s); }
int  DayKey(const datetime t) { MqlDateTime d; TimeToStruct(t, d); return d.year * 10000 + d.mon * 100 + d.day; }
double TickSize() { double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE); return (ts > 0.0 ? ts : _Point); }
double NormPrice(const double p) { double ts = TickSize(); return NormalizeDouble(MathRound(p / ts) * ts, _Digits); }

//--- volume: integer number of steps (works for steps like 0.25 or 0.001)
double VolumeFloor(const double v)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0) step = 0.01;
   long n = (long)MathFloor(v / step + 1e-9);
   if(n < 0) n = 0;
   return NormalizeDouble((double)n * step, 8);
  }

void SetFilling()
  {
   long fm = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   long ex = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_EXEMODE);
   if((fm & SYMBOL_FILLING_FOK) != 0)      g_filling = ORDER_FILLING_FOK;
   else if((fm & SYMBOL_FILLING_IOC) != 0) g_filling = ORDER_FILLING_IOC;
   else
     {
      g_filling = ORDER_FILLING_RETURN;
      if(ex != SYMBOL_TRADE_EXECUTION_EXCHANGE) Log("WARN|no FOK/IOC filling flag, using RETURN");
     }
   g_trade.SetTypeFilling(g_filling);
  }

//--- persistent state ------------------------------------------------
string GV(const string name) { return g_key + "_" + name; }
void   GVSet(const string name, const double v) { GlobalVariableSet(GV(name), v); }
double GVGet(const string name, const double def) { return GlobalVariableCheck(GV(name)) ? GlobalVariableGet(GV(name)) : def; }

void LoadState()
  {
   g_key = StringFormat("XAU300ORBCR_%I64d_%I64d_%s", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic, _Symbol);
   if(InpResetState)
     {
      string names[] = {"peak", "halt", "day", "daybal", "dhalt", "done", "level", "track", "lastpos"};
      for(int i = 0; i < ArraySize(names); i++) GlobalVariableDel(GV(names[i]));
     }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity = MathMax(GVGet("peak", eq), eq);
   g_halted = GVGet("halt", 0.0) > 0.5;
   GVSet("peak", g_peakEquity);
   g_level = (int)GVGet("level", 0.0);
   if(g_level < 0 || g_level > InpRecoveryMaxLevel || !InpRecoveryOn) g_level = 0;   // never resume above the configured ladder
   g_trackPos = (ulong)GVGet("track", 0.0);
   g_lastProcessed = (ulong)GVGet("lastpos", 0.0);
   GVSet("level", g_level);
   if(g_level > 0 || g_trackPos > 0) Log(StringFormat("STATE|restored recovery level=%d tracked position=%I64u", g_level, g_trackPos));
   if(g_halted) Log("STATE|DD halt flag found: trading disabled, flattening (InpResetState=true clears it)");
  }

void SavePeak(const double eq)
  {
   if(eq > g_peakEquity + 0.005) { g_peakEquity = eq; GVSet("peak", g_peakEquity); }
  }

void SaveDay()
  {
   GVSet("day", g_dayKey); GVSet("daybal", g_dayStartBal);
   GVSet("dhalt", g_dailyHalt ? 1.0 : 0.0); GVSet("done", g_dayDone ? 1.0 : 0.0);
  }

//--- tester-only research export: balance/equity sampled at the first tick of every minute
void EquityOpen()
  {
   if(!InpEquityCsv || !(bool)MQLInfoInteger(MQL_TESTER)) return;
   string fn = (InpEquityFileName != "") ? InpEquityFileName
               : StringFormat("XAU300_ORB_CappedRecovery_Research_%s_equity.csv", InpRunTag == "" ? "run" : InpRunTag);
   g_eqFile = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_eqFile == INVALID_HANDLE) { Print("XAU300ORBCR|", InpRunTag, "|WARN|equity csv open failed ", GetLastError()); return; }
   FileWrite(g_eqFile, "server_datetime", "balance", "equity");
   Print("XAU300ORBCR|", InpRunTag, "|EQUITY_CSV|", fn);
  }

void EquitySample(const bool force)
  {
   if(g_eqFile == INVALID_HANDLE) return;
   datetime now = TimeCurrent();
   datetime m = now - (now % 60);
   if(!force && m == g_eqLastMin) return;
   g_eqLastMin = m;
   FileWrite(g_eqFile, TimeToString(now, TIME_DATE | TIME_SECONDS),
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2), DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
  }

void EquityClose()
  {
   if(g_eqFile == INVALID_HANDLE) return;
   EquitySample(true);
   FileClose(g_eqFile);
   g_eqFile = INVALID_HANDLE;
  }

//--- positions ------------------------------------------------------
bool MyPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) { ticket = tk; return true; }
     }
   return false;
  }

bool AnyPositionOnSymbol()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && PositionGetString(POSITION_SYMBOL) == _Symbol) return true;
     }
   return false;
  }

//--- one close attempt per position per call; true when none of ours is left
bool FlattenMine(const string why)
  {
   bool flat = true;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      bool sent = g_trade.PositionClose(tk, (ulong)InpDeviationPoints);
      uint rc = g_trade.ResultRetcode();
      if(sent && (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL) && !PositionSelectByTicket(tk))
         Log(StringFormat("CLOSE|%s ticket=%I64u", why, tk));
      else
        {
         flat = false; c_closeFail++;
         Log(StringFormat("ERR|close %s ticket=%I64u rc=%u %s (retry next tick)", why, tk, rc, g_trade.ResultRetcodeDescription()));
        }
     }
   return flat;
  }

//--- session ----------------------------------------------------------
bool DayAllowed(const int dow)
  {
   switch(dow)
     {
      case 1: return InpTradeMon;
      case 2: return InpTradeTue;
      case 3: return InpTradeWed;
      case 4: return InpTradeThu;
      case 5: return InpTradeFri;
     }
   return false;
  }

datetime ServerMidnight(const datetime t) { MqlDateTime d; TimeToStruct(t, d); d.hour = 0; d.min = 0; d.sec = 0; return StructToTime(d); }

bool RangeOf(const datetime start, const int minBars, double &hi, double &lo, double &lastClose)
  {
   MqlRates b[];
   ArraySetAsSeries(b, false);
   int n = CopyRates(_Symbol, PERIOD_M1, start, start + InpRangeMinutes * 60 - 1, b);
   if(n < minBars || n <= 0) return false;
   hi = b[0].high; lo = b[0].low;
   for(int i = 1; i < n; i++) { hi = MathMax(hi, b[i].high); lo = MathMin(lo, b[i].low); }
   lastClose = b[n - 1].close;
   return (hi > lo && lastClose > 0.0);
  }

// median of 100*range/lastClose over the previous complete weekday sessions (strictly before today); -1 = not enough
double RollingMedianPct()
  {
   double v[]; ArrayResize(v, 0);
   int maxBack = InpRollSessions * 2 + 20;
   for(int back = 1; back <= maxBack && ArraySize(v) < InpRollSessions; back++)
     {
      datetime st = g_sessStart - back * 86400;
      MqlDateTime u; TimeToStruct(st - InpServerOffsetMinutes * 60, u);      // weekday in UTC terms
      if(u.day_of_week == 0 || u.day_of_week == 6) continue;
      double hi, lo, lc;
      if(!RangeOf(st, InpRangeMinutes, hi, lo, lc)) continue;                 // incomplete session
      int k = ArraySize(v); ArrayResize(v, k + 1); v[k] = 100.0 * (hi - lo) / lc;
     }
   int n = ArraySize(v);
   if(n < InpRollSessions) return -1.0;
   ArraySort(v);
   return (n % 2 == 1) ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
  }

void NewDay(const datetime now)
  {
   int key = DayKey(now);
   g_sessStart = ServerMidnight(now) + (InpSessionStartHourUTC * 60 + InpSessionStartMinUTC + InpServerOffsetMinutes) * 60;
   g_rangeEnd  = g_sessStart + InpRangeMinutes * 60;
   g_rangeReady = false; g_lastBar = 0;
   if((int)GVGet("day", -1) == key)          // restart on the same server day: restore, do not reset
     {
      g_dayKey = key;
      g_dayStartBal = GVGet("daybal", AccountInfoDouble(ACCOUNT_BALANCE));
      g_dailyHalt = GVGet("dhalt", 0.0) > 0.5;
      g_dayDone = GVGet("done", 0.0) > 0.5;
      Log(StringFormat("STATE|restored day %d startBal=%.2f dailyHalt=%d done=%d", key, g_dayStartBal, (int)g_dailyHalt, (int)g_dayDone));
      return;
     }
   g_dayKey = key;
   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyHalt = false;
   MqlDateTime u; TimeToStruct(g_sessStart - InpServerOffsetMinutes * 60, u);
   g_dayDone = !DayAllowed(u.day_of_week);
   if(!g_dayDone && InpRollMinPct > 0.0)
     {
      double med = RollingMedianPct();
      if(med < 0.0)
        {
         if(InpRollStrict) { g_dayDone = true; c_rollInsufficient++; Log("DAY|rolling filter: fewer than RollSessions complete sessions in history, no trade (strict)"); }
        }
      else if(med < InpRollMinPct) { g_dayDone = true; c_roll++; Log(StringFormat("DAY|rolling median %.4f%% < %.4f%%, no trade", med, InpRollMinPct)); }
      else Log(StringFormat("DAY|rolling median %.4f%% ok", med));
     }
   SaveDay();
  }

void EndDay(const string why) { g_dayDone = true; SaveDay(); Log("DAY|" + why); }

//--- capped recovery ---------------------------------------------------
double EffectiveRiskPct()
  {
   double r = InpRiskPercent;
   if(InpRecoveryOn) r = InpRiskPercent * MathPow(InpRecoveryMultiplier, g_level);
   return MathMin(r, InpRiskCapPercent);
  }

void UpdateLevel(const double net)
  {
   int before = g_level;
   if(!InpRecoveryOn) g_level = 0;
   else if(net > -InpBETolerance) { if(g_level > 0) c_resetWin++; g_level = 0; }            // win or breakeven
   else if(g_level < InpRecoveryMaxLevel) { g_level++; c_levelUp++; }                        // loss: next level
   else { g_level = 0; c_cycleEnd++; }                                                     // loss at the top: cycle ends
   GVSet("level", g_level);
   Log(StringFormat("LEVEL|position net %.2f: level %d -> %d (next risk %.2f%%)", net, before, g_level, EffectiveRiskPct()));
  }

void TrackOpenPosition()
  {
   ulong tk;
   if(g_trackPos == 0 && MyPosition(tk) && PositionSelectByTicket(tk))
     {
      g_trackPos = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      GVSet("track", (double)g_trackPos);
     }
  }

// Called every tick. Changes the level once per fully closed tracked position.
void ProcessClosedPosition()
  {
   if(g_trackPos == 0) { TrackOpenPosition(); return; }
   for(int i = PositionsTotal() - 1; i >= 0; i--)                // still open (incl. after a partial close)?
     {
      ulong tk = PositionGetTicket(i);
      if(tk != 0 && (ulong)PositionGetInteger(POSITION_IDENTIFIER) == g_trackPos) return;
     }
   if(g_trackPos == g_lastProcessed) { g_trackPos = 0; GVSet("track", 0.0); return; }   // already counted
   if(!HistorySelectByPosition((long)g_trackPos)) return;           // history not ready: retry next tick
   double net = 0.0, vin = 0.0, vout = 0.0;
   int n = HistoryDealsTotal();
   for(int i = 0; i < n; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID) != g_trackPos) continue;
      long   e = HistoryDealGetInteger(d, DEAL_ENTRY);
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      if(e == DEAL_ENTRY_IN) vin += v;
      else if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY || e == DEAL_ENTRY_INOUT) vout += v;
      net += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP)
           + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
     }
   if(vin <= 0.0 || vout < vin - 1e-8) return;                       // not fully closed in history yet: retry
   UpdateLevel(net);
   g_lastProcessed = g_trackPos; GVSet("lastpos", (double)g_lastProcessed);
   g_trackPos = 0; GVSet("track", 0.0);
  }

//--- entry -------------------------------------------------------------
bool StopsOK(const int dir, const double sl, const double tp)
  {
   double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(dir > 0) return (bid - sl >= lvl && tp - bid >= lvl);
   return (sl - ask >= lvl && ask - tp >= lvl);
  }

double LotsForRisk(const ENUM_ORDER_TYPE type, const double entry, const double sl, string &why)
  {
   double p1 = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, p1)) { why = "calc_profit_failed"; return 0.0; }
   double lossPerLot = -p1;
   if(lossPerLot <= 0.0) { why = "bad_sl"; return 0.0; }
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * EffectiveRiskPct() / 100.0;
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(step <= 0.0) step = 0.01;
   double lots = VolumeFloor(riskMoney / lossPerLot);
   if(vmax > 0.0 && lots > vmax) lots = VolumeFloor(vmax);
   if(InpMaxLot > 0.0 && lots > InpMaxLot) lots = VolumeFloor(InpMaxLot);            // explicit lot cap
   while(lots >= vmin - 1e-12 && lots * lossPerLot > riskMoney * (1.0 + 1e-9)) lots = VolumeFloor(lots - step);  // re-check risk after rounding
   if(lots < vmin - 1e-12)
     { why = StringFormat("below_min_volume(min %.2f lot loses %.2f > budget %.2f)", vmin, vmin * lossPerLot, riskMoney); return 0.0; }
   double margin = 0.0;
   if(!OrderCalcMargin(type, _Symbol, lots, entry, margin)) { why = "calc_margin_failed"; return 0.0; }
   double allowed = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * InpMaxMarginUsePct / 100.0;
   if(margin > allowed && margin > 0.0)
     {
      lots = VolumeFloor(lots * allowed / margin);
      if(lots < vmin - 1e-12) { why = "margin"; return 0.0; }
     }
   why = "ok";
   return lots;
  }

void TryEnter(const int dir)
  {
   if(AnyPositionOnSymbol()) { c_skipPos++; Log("SKIP|a position is already open on this symbol"); return; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   if(InpMaxSpreadPrice > 0.0 && ask - bid > InpMaxSpreadPrice) { c_skipSpread++; Log(StringFormat("SKIP|spread %.3f > %.3f", ask - bid, InpMaxSpreadPrice)); return; }
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double rng = g_hi - g_lo;
   double stop = (dir > 0) ? g_hi - rng * InpSLPctOfRange / 100.0 : g_lo + rng * InpSLPctOfRange / 100.0;
   double entry = (dir > 0) ? ask : bid;
   double sl = NormPrice(stop);
   double sld = (entry - sl) * dir;
   if(sld <= 0.0) { c_skipStops++; Log("SKIP|price already beyond the stop"); return; }
   double tp = NormPrice(entry + dir * sld * InpRR);
   if(!StopsOK(dir, sl, tp)) { c_skipStops++; Log("SKIP|stops_level"); return; }
   string why = "";
   double lots = LotsForRisk(type, entry, sl, why);
   if(lots <= 0.0) { if(StringFind(why, "below_min_volume") == 0) c_skipMinVol++; else c_skipMargin++; Log("SKIP|" + why); return; }
   MqlTradeRequest rq; MqlTradeCheckResult ck; ZeroMemory(rq); ZeroMemory(ck);
   rq.action = TRADE_ACTION_DEAL; rq.symbol = _Symbol; rq.volume = lots; rq.type = type; rq.price = entry;
   rq.sl = sl; rq.tp = tp; rq.deviation = (ulong)InpDeviationPoints; rq.magic = InpMagic; rq.type_filling = g_filling;
   if(!OrderCheck(rq, ck)) { c_skipCheck++; Log(StringFormat("SKIP|OrderCheck %u %s", ck.retcode, ck.comment)); return; }
   bool ok = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment) : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);
   uint rc = g_trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_PLACED && rc != TRADE_RETCODE_DONE_PARTIAL))
     { c_sendFail++; Log(StringFormat("ERR|send rc=%u %s", rc, g_trade.ResultRetcodeDescription())); return; }
   c_opened++;
   TrackOpenPosition();
   if(EffectiveRiskPct() > InpDailyLossPct && InpDailyLossPct > 0.0)
     { c_riskAboveDaily++; Log(StringFormat("NOTE|risk %.2f%% > daily stop %.1f%%: a loser is normally cut by the daily stop before its full SL", EffectiveRiskPct(), InpDailyLossPct)); }
   double fill = g_trade.ResultPrice();
   Log(StringFormat("OPEN|level=%d risk=%.2f%% %s lots=%.2f fill=%.3f sl=%.3f tp=%.3f R=%.3f range=[%.3f,%.3f]", g_level, EffectiveRiskPct(), dir > 0 ? "BUY" : "SELL", lots, fill, sl, tp, sld, g_lo, g_hi));
   // anchor TP to the real fill so that R = |fill - SL| (R is later recovered from the TP)
   ulong tk;
   if(fill > 0.0 && MyPosition(tk))
     {
      double r = (fill - sl) * dir;
      double ntp = NormPrice(fill + dir * r * InpRR);
      if(r > 0.0 && MathAbs(ntp - tp) >= TickSize() && g_trade.PositionModify(tk, sl, ntp)) Log(StringFormat("TP|anchored to fill %.3f", ntp));
     }
  }

//--- management --------------------------------------------------------
void ManagePosition(const datetime now)
  {
   ulong tk;
   if(!MyPosition(tk) || !PositionSelectByTicket(tk)) return;
   int    dir  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), tp = PositionGetDouble(POSITION_TP);
   datetime opened = (datetime)PositionGetInteger(POSITION_TIME);
   if(InpMaxHoldMinutes > 0 && now - opened >= InpMaxHoldMinutes * 60)
     {
      if(FlattenMine("max_hold")) c_holdExits++;
      return;
     }
   if(InpStopMoveAtR <= 0.0 || InpRR <= 0.0 || tp <= 0.0 || sl <= 0.0) return;
   double r = MathAbs(tp - open) / InpRR;                     // original risk, recovered from the target
   if(r <= 0.0) return;
   double px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((px - open) * dir < InpStopMoveAtR * r) return;
   double nsl = NormPrice(open + dir * InpStopMoveToR * r);
   if((nsl - sl) * dir <= 0.0) return;                        // tighten only (also: already moved)
   double lvl = (double)MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point;
   if((px - nsl) * dir < lvl) return;
   if(g_trade.PositionModify(tk, nsl, tp) && g_trade.ResultRetcode() == TRADE_RETCODE_DONE)
     { c_stopMoves++; Log(StringFormat("STOP|moved to %.3f (%.2fR)", nsl, InpStopMoveToR)); }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   bool tester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(!tester && mode == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealAccount)
     { Print("XAU300ORBCR|REFUSED|real account and AllowRealAccount=false. This EA is research-only."); return INIT_FAILED; }
   if(InpRiskPercent <= 0.0 || InpRiskCapPercent <= 0.0 || InpRiskCapPercent > 8.0 || InpRiskPercent > InpRiskCapPercent)
     { Print("XAU300ORBCR|BAD_INPUT|need 0 < RiskPercent <= RiskCapPercent <= 8"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRecoveryMaxLevel < 0 || InpRecoveryMaxLevel > 2 || InpRecoveryMultiplier < 1.0 || InpRecoveryMultiplier > 3.0 || InpMaxLot <= 0.0 || InpBETolerance < 0.0)
     { Print("XAU300ORBCR|BAD_INPUT|recovery: MaxLevel 0..2, multiplier 1..3, MaxLot > 0"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRangeMinutes < 1 || InpRangeMinutes > 240 || InpEntryWindowMin < 1 || InpRR <= 0.0 || InpSLPctOfRange <= 0.0)
     { Print("XAU300ORBCR|BAD_INPUT|session/exits"); return INIT_PARAMETERS_INCORRECT; }
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints((ulong)InpDeviationPoints);
   g_trade.SetMarginMode();
   SetFilling();
   LoadState();
   EquityOpen();
   PrintFormat("XAU300ORBCR|%s|INIT|symbol=%s digits=%d tick=%.5f contract=%.2f vmin=%.3f vstep=%.3f lev=%I64d tester=%d risk=%.2f%% recovery=%d mult=%.2f maxlevel=%d cap=%.2f%% maxlot=%.2f daily=%.1f%% dd=%.1f%% offset=%d",
               InpRunTag, _Symbol, _Digits, TickSize(), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               AccountInfoInteger(ACCOUNT_LEVERAGE), (int)tester, InpRiskPercent, (int)InpRecoveryOn, InpRecoveryMultiplier, InpRecoveryMaxLevel, InpRiskCapPercent, InpMaxLot, InpDailyLossPct, InpMaxDDPct, InpServerOffsetMinutes);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EquityClose();
   PrintFormat("XAU300ORBCR|%s|SUMMARY|breaks=%d opened=%d half_filter=%d roll_filter=%d roll_insufficient=%d no_break=%d skip_position=%d skip_spread=%d skip_min_volume=%d skip_margin=%d skip_stops=%d skip_check=%d send_fail=%d stop_moves=%d hold_exits=%d daily_stops=%d dd_halts=%d close_fail=%d level_up=%d reset_win=%d cycle_end=%d risk_above_daily=%d level=%d peak=%.2f halted=%d",
               InpRunTag, c_breaks, c_opened, c_half, c_roll, c_rollInsufficient, c_noBreak, c_skipPos, c_skipSpread, c_skipMinVol,
               c_skipMargin, c_skipStops, c_skipCheck, c_sendFail, c_stopMoves, c_holdExits, c_dailyStops, c_ddHalts, c_closeFail,
               c_levelUp, c_resetWin, c_cycleEnd, c_riskAboveDaily, g_level, g_peakEquity, (int)g_halted);
  }

void OnTick()
  {
   EquitySample(false);                        // research export: before any early return
   ProcessClosedPosition();                    // recovery level: once per fully closed position
   datetime now = TimeCurrent();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // 1) persistent peak-equity DD stop: once set, flatten on every tick until flat (also after restart)
   if(!g_halted && InpMaxDDPct > 0.0 && g_peakEquity > 0.0 && eq <= g_peakEquity * (1.0 - InpMaxDDPct / 100.0))
     {
      g_halted = true; c_ddHalts++; GVSet("halt", 1.0);
      Log(StringFormat("HALT|equity %.2f <= peak %.2f - %.1f%% (trigger, not a guaranteed cap)", eq, g_peakEquity, InpMaxDDPct));
     }
   if(g_halted) { FlattenMine("dd_halt"); return; }
   SavePeak(eq);

   // 2) server day (state restored on restart)
   if(DayKey(now) != g_dayKey) NewDay(now);

   // 3) daily hard stop: flatten (retry every tick) and no entries until the next day
   if(!g_dailyHalt && InpDailyLossPct > 0.0 && eq <= g_dayStartBal * (1.0 - InpDailyLossPct / 100.0))
     {
      g_dailyHalt = true; g_dayDone = true; c_dailyStops++; SaveDay();
      Log(StringFormat("DAILY|equity %.2f <= day start %.2f - %.1f%% (trigger, not a guaranteed cap)", eq, g_dayStartBal, InpDailyLossPct));
     }
   if(g_dailyHalt) { FlattenMine("daily_stop"); return; }

   // 4) manage our position (max hold, stop move)
   ManagePosition(now);

   // 5) closed M1 bars after the range: the first break decides the day
   if(g_dayDone || now < g_rangeEnd) return;
   datetime cur = iTime(_Symbol, PERIOD_M1, 0);
   if(cur == 0 || cur == g_lastBar) return;
   g_lastBar = cur;
   if(!g_rangeReady)
     {
      if(!RangeOf(g_sessStart, 1, g_hi, g_lo, g_lastClose)) { EndDay("no M1 bars / flat range in the window"); return; }
      g_rangeReady = true;
      Log(StringFormat("RANGE|%s hi=%.3f lo=%.3f lastClose=%.3f (%.4f%%)", TimeToString(g_sessStart), g_hi, g_lo, g_lastClose, 100.0 * (g_hi - g_lo) / g_lastClose));
     }
   MqlRates b[];
   ArraySetAsSeries(b, true);
   if(CopyRates(_Symbol, PERIOD_M1, 1, 1, b) != 1) return;          // bar 1 = last CLOSED bar (no lookahead)
   if(b[0].time < g_rangeEnd) return;
   if(b[0].time >= g_rangeEnd + InpEntryWindowMin * 60) { c_noBreak++; EndDay("no break inside the entry window"); return; }
   int dir = 0;
   if(b[0].close > g_hi) dir = 1; else if(b[0].close < g_lo) dir = -1;
   if(dir == 0) return;
   c_breaks++;
   EndDay(StringFormat("break %s close=%.3f", dir > 0 ? "UP" : "DOWN", b[0].close));   // one shot per day
   if(InpHalfFilter > 0.0)
     {
      double cp = (g_lastClose - g_lo) / (g_hi - g_lo);
      double score = (dir > 0) ? cp : 1.0 - cp;
      if(score < InpHalfFilter) { c_half++; Log(StringFormat("SKIP|half filter: range closed at %.2f of the box", cp)); return; }
     }
   TryEnter(dir);
  }

double OnTester() { return TesterStatistics(STAT_PROFIT); }
//+------------------------------------------------------------------+
