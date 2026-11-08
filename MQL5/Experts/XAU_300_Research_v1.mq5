//+------------------------------------------------------------------+
//| XAU_300_Research_v1.mq5                                          |
//| RESEARCH-ONLY Expert Advisor for XAUUSD (MetaTrader 5)           |
//|------------------------------------------------------------------|
//| Logic: Asia opening-range breakout (ORB) on closed bars.         |
//|  - Range = [RangeStartHour, +RangeMinutes) in SERVER time        |
//|  - Signal = closed SignalTF bar closes outside the range         |
//|  - SL = opposite side of range, TP = TP_R x risk, BE at 1R       |
//|  - Time exit, no Friday, low-volatility kill filter              |
//| Risk: broker-aware sizing via OrderCalcProfit, volume step,      |
//|  margin / stops / freeze / filling checks, server-side SL/TP,    |
//|  max 1 position, daily loss stop, persistent peak-equity DD stop.|
//|  If the minimum volume already exceeds the risk budget the       |
//|  signal is SKIPPED (never forced to the minimum lot).            |
//| Safety: refuses REAL accounts unless AllowRealAccount=true.      |
//|  No DLL, no WebRequest, no credentials, no network calls.        |
//|                                                                  |
//| Python reference rules: research/xau300/sim/xau300_sim.py         |
//| Status: no robust positive edge proven (see research/xau300).    |
//| Past results do not guarantee future results.                    |
//|                                                                  |
//| v1.01 (risk plumbing only, entry rules unchanged from v1.00):    |
//|  - DD halt and daily stop flatten with one bounded close attempt |
//|    per tick, retried every tick / after restart until flat       |
//|  - daily stop is a hard stop (flatten + no entries), day state   |
//|    (day key, start balance, daily halt, signal counters)         |
//|    persisted per account/magic/symbol and restored same day      |
//|  - entry blocked by ANY position on the symbol (any EA)          |
//|  - volume rounded in integer step units, risk re-checked         |
//|  - optional tester-only M1-sampled balance/equity CSV, run tag   |
//|  Thresholds are triggers, not guaranteed caps (gaps/slippage).   |
//+------------------------------------------------------------------+
#property copyright "XAU_300_Research_v1 (research only)"
#property version   "1.01"
#property description "Research-only Asia ORB for XAUUSD. Not a live-trading recommendation."

#include <Trade\Trade.mqh>

//--- safety
input group "=== Safety ==="
input bool            InpAllowRealAccount   = false;      // Allow REAL account (default false: tester/demo only)
input long            InpMagic              = 300301;     // Magic number
input string          InpComment            = "XAU300v1"; // Order comment
input string          InpRunTag             = "";         // Run tag printed in logs (set by the runner)

//--- session (server time)
input group "=== Session (server time) ==="
input int             InpRangeStartHour     = 0;          // Range start hour (server)
input int             InpRangeMinutes       = 60;         // Range length (minutes)
input ENUM_TIMEFRAMES InpSignalTF           = PERIOD_M5;  // Signal timeframe (closed bars only)
input int             InpEntryEndHour       = 20;         // No new entries from this hour
input int             InpExitHour           = 21;         // Close open position from this hour (until 23:00)
input bool            InpTradeFriday        = false;      // Trade on Friday
input int             InpMaxSignalsPerDir   = 1;          // Signals per direction per day

//--- exits
input group "=== Exits ==="
input double          InpSLRangePct         = 100.0;      // SL distance as % of range from breakout side (100 = opposite side)
input double          InpTP_R               = 2.0;        // Take profit (R)
input double          InpBE_TriggerR        = 1.0;        // Move SL to break-even after (R), 0 = off
input double          InpBE_LockR           = 0.0;        // Break-even lock (R)

//--- filters
input group "=== Filters ==="
input double          InpKillMedianRangePct = 1.5;        // Skip day if median D1 range% of previous days < this (0 = off)
input int             InpKillLookbackDays   = 20;         // Kill filter lookback (D1 bars, min 10 valid)
input double          InpMaxSpreadPctSL     = 10.0;       // Max spread as % of SL distance (0 = off)
input double          InpMaxSpreadPrice     = 1.00;       // Max spread in price units, e.g. 1.00 = $1.00 (0 = off)
input double          InpMinRangeATR        = 0.0;        // Min range / ATR(D1) (0 = off)
input double          InpMaxRangeATR        = 0.0;        // Max range / ATR(D1) (0 = off)
input int             InpATRPeriodD1        = 14;         // ATR(D1) period for range filter

//--- risk
input group "=== Risk ==="
input double          InpRiskPercent        = 1.0;        // Risk per trade (% of equity)
input double          InpDailyLossPct       = 3.0;        // Daily loss stop (% of day-start balance, 0 = off)
input double          InpMaxDDPct           = 20.0;       // Persistent peak-equity DD stop (% , 0 = off)
input bool            InpResetDDState       = false;      // Reset stored peak/halt state on init
input double          InpMaxMarginUsePct    = 50.0;       // Max margin as % of free margin
input int             InpDeviationPoints    = 30;         // Max slippage (points)
input bool            InpVerbose            = true;       // Log decisions

//--- research export
input group "=== Research export (Strategy Tester only) ==="
input bool            InpEquityCsv          = false;      // Write M1-sampled balance/equity CSV (tester only)
input string          InpEquityFileName     = "";         // CSV in agent MQL5/Files ("" = XAU_300_Research_v1_<RunTag>_equity.csv)

//+------------------------------------------------------------------+
CTrade   g_trade;
string   g_key;
ENUM_ORDER_TYPE_FILLING g_filling = ORDER_FILLING_FOK;
bool     g_dailyHalt    = false;
int      g_eqFile       = INVALID_HANDLE;
datetime g_eqLastMin    = 0;
double   g_peakEquity   = 0.0;
bool     g_halted       = false;

int      g_dayKey       = -1;        // yyyymmdd of server day
double   g_dayStartBal  = 0.0;
bool     g_daySkip      = true;
bool     g_rangeReady   = false;
double   g_rangeHi      = 0.0, g_rangeLo = 0.0;
datetime g_rangeStart   = 0, g_rangeEnd = 0;
int      g_cntL = 0, g_cntS = 0;
bool     g_armL = true, g_armS = true;
datetime g_lastSignalBar = 0;
int      g_atrHandle    = INVALID_HANDLE;

// counters (printed on deinit, parsed by the runner)
int c_signals = 0, c_opened = 0, c_skipPos = 0, c_skipHalt = 0, c_skipDaily = 0, c_skipSpread = 0,
    c_skipMinVol = 0, c_skipMargin = 0, c_skipStops = 0, c_skipATR = 0, c_skipCheck = 0, c_killDays = 0,
    c_beMoves = 0, c_timeExits = 0, c_ddHalts = 0, c_sendFail = 0, c_dailyStops = 0, c_closeFail = 0;

//+------------------------------------------------------------------+
void Log(const string s) { if(InpVerbose) Print("XAU300|", InpRunTag, "|", s); }

int DayKey(const datetime t) { MqlDateTime d; TimeToStruct(t, d); return d.year * 10000 + d.mon * 100 + d.day; }

double TickSize()
  {
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0.0 ? ts : _Point);
  }

double NormPrice(const double p)
  {
   double ts = TickSize();
   return NormalizeDouble(MathRound(p / ts) * ts, _Digits);
  }

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

//--- persistent state (GlobalVariables survive terminal restarts on live/demo; per-test in tester)
string GV(const string name) { return g_key + "_" + name; }
void   GVSet(const string name, const double v) { GlobalVariableSet(GV(name), v); }
double GVGet(const string name, const double def) { return GlobalVariableCheck(GV(name)) ? GlobalVariableGet(GV(name)) : def; }

void LoadState()
  {
   g_key = StringFormat("XAU300v1_%I64d_%I64d_%s", AccountInfoInteger(ACCOUNT_LOGIN), InpMagic, _Symbol);
   if(InpResetDDState)
     {
      string names[] = {"peak", "halt", "day", "daybal", "dhalt", "cntL", "cntS", "armL", "armS"};
      for(int i = 0; i < ArraySize(names); i++) GlobalVariableDel(GV(names[i]));
     }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peakEquity = MathMax(GVGet("peak", eq), eq);
   g_halted = GVGet("halt", 0.0) > 0.5;
   GVSet("peak", g_peakEquity);
   if(g_halted) Log("STATE|DD halt flag found: trading disabled, flattening (InpResetDDState=true clears it)");
  }

void SavePeak(const double eq)
  {
   if(eq > g_peakEquity + 0.005) { g_peakEquity = eq; GVSet("peak", g_peakEquity); }
  }

void SaveDay()
  {
   GVSet("day", g_dayKey); GVSet("daybal", g_dayStartBal); GVSet("dhalt", g_dailyHalt ? 1.0 : 0.0);
   GVSet("cntL", g_cntL); GVSet("cntS", g_cntS); GVSet("armL", g_armL ? 1.0 : 0.0); GVSet("armS", g_armS ? 1.0 : 0.0);
  }

//--- tester-only research export: balance/equity sampled at the first tick of every minute
void EquityOpen()
  {
   if(!InpEquityCsv || !(bool)MQLInfoInteger(MQL_TESTER)) return;
   string fn = (InpEquityFileName != "") ? InpEquityFileName
               : StringFormat("XAU_300_Research_v1_%s_equity.csv", InpRunTag == "" ? "run" : InpRunTag);
   g_eqFile = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   if(g_eqFile == INVALID_HANDLE) { Print("XAU300|", InpRunTag, "|WARN|equity csv open failed ", GetLastError()); return; }
   FileWrite(g_eqFile, "server_datetime", "balance", "equity");
   Print("XAU300|", InpRunTag, "|EQUITY_CSV|", fn);
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

//--- position helpers
bool GetMyPosition(ulong &ticket)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      ticket = tk;
      return true;
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

//--- kill filter: median of previous completed D1 range%
bool KillFilterSkip()
  {
   if(InpKillMedianRangePct <= 0.0) return false;
   MqlRates d1[];
   ArraySetAsSeries(d1, true);
   int n = CopyRates(_Symbol, PERIOD_D1, 1, InpKillLookbackDays, d1);   // shift>=1: completed days only
   if(n < 10) return false;                                              // not enough history -> no kill
   double v[];
   ArrayResize(v, n);
   for(int i = 0; i < n; i++) v[i] = (d1[i].close > 0 ? 100.0 * (d1[i].high - d1[i].low) / d1[i].close : 0.0);
   ArraySort(v);
   double med = (n % 2 == 1) ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
   return med < InpKillMedianRangePct;
  }

void NewDay(const datetime now)
  {
   MqlDateTime d; TimeToStruct(now, d);
   int key = DayKey(now);
   g_rangeReady  = false;
   g_rangeStart  = StringToTime(StringFormat("%04d.%02d.%02d %02d:00", d.year, d.mon, d.day, InpRangeStartHour));
   g_rangeEnd    = g_rangeStart + InpRangeMinutes * 60;
   g_daySkip     = (d.day_of_week == 0 || d.day_of_week == 6 || (d.day_of_week == 5 && !InpTradeFriday));
   if(!g_daySkip && KillFilterSkip()) { g_daySkip = true; c_killDays++; Log("DAY|kill filter: low volatility, no trades today"); }
   g_dayKey = key;
   if((int)GVGet("day", -1) == key)            // restart on the same server day: restore, do not reset
     {
      g_dayStartBal = GVGet("daybal", AccountInfoDouble(ACCOUNT_BALANCE));
      g_dailyHalt = GVGet("dhalt", 0.0) > 0.5;
      g_cntL = (int)GVGet("cntL", 0); g_cntS = (int)GVGet("cntS", 0);
      g_armL = GVGet("armL", 1.0) > 0.5; g_armS = GVGet("armS", 1.0) > 0.5;
      Log(StringFormat("STATE|restored day %d startBal=%.2f dailyHalt=%d cntL=%d cntS=%d", key, g_dayStartBal, (int)g_dailyHalt, g_cntL, g_cntS));
      return;
     }
   g_dayStartBal = AccountInfoDouble(ACCOUNT_BALANCE);
   g_dailyHalt = false; g_cntL = 0; g_cntS = 0; g_armL = true; g_armS = true;
   SaveDay();
  }

bool BuildRange()
  {
   MqlRates m1[];
   int n = CopyRates(_Symbol, PERIOD_M1, g_rangeStart, g_rangeEnd - 1, m1);   // completed M1 bars inside the range
   if(n < InpRangeMinutes / 3) { g_daySkip = true; Log(StringFormat("DAY|range has %d M1 bars < %d, skip", n, InpRangeMinutes / 3)); return false; }
   double hi = -DBL_MAX, lo = DBL_MAX;
   for(int i = 0; i < n; i++)
     {
      if(m1[i].time < g_rangeStart || m1[i].time >= g_rangeEnd) continue;
      hi = MathMax(hi, m1[i].high); lo = MathMin(lo, m1[i].low);
     }
   if(hi <= lo) { g_daySkip = true; return false; }
   g_rangeHi = hi; g_rangeLo = lo; g_rangeReady = true;
   Log(StringFormat("RANGE|%s hi=%.3f lo=%.3f", TimeToString(g_rangeStart), hi, lo));
   return true;
  }

//--- broker-aware volume: risk money / loss of 1.0 lot from entry to SL
double LotsForRisk(const ENUM_ORDER_TYPE type, const double entry, const double sl, string &why)
  {
   double profit1 = 0.0;
   if(!OrderCalcProfit(type, _Symbol, 1.0, entry, sl, profit1)) { why = "calc_profit_failed"; return 0.0; }
   double lossPerLot = -profit1;
   if(lossPerLot <= 0.0) { why = "bad_sl"; return 0.0; }
   double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPercent / 100.0;
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP); if(step <= 0.0) step = 0.01;
   double lots = VolumeFloor(riskMoney / lossPerLot);
   if(vmax > 0.0 && lots > vmax) lots = VolumeFloor(vmax);
   while(lots >= vmin - 1e-12 && lots * lossPerLot > riskMoney * (1.0 + 1e-9)) lots = VolumeFloor(lots - step);  // re-check risk after rounding
   if(lots < vmin - 1e-12)
     {
      why = StringFormat("below_min_volume(min %.2f lot loses %.2f > budget %.2f)", vmin, vmin * lossPerLot, riskMoney);
      return 0.0;
     }
   // margin check: shrink to fit, never below the minimum
   double margin = 0.0, price = entry;
   if(!OrderCalcMargin(type, _Symbol, lots, price, margin)) { why = "calc_margin_failed"; return 0.0; }
   double allowed = AccountInfoDouble(ACCOUNT_MARGIN_FREE) * InpMaxMarginUsePct / 100.0;
   if(margin > allowed && margin > 0.0)
     {
      lots = VolumeFloor(lots * allowed / margin);
      if(lots < vmin - 1e-12) { why = "margin"; return 0.0; }
     }
   why = "ok";
   return lots;
  }

bool StopsOK(const ENUM_ORDER_TYPE type, const double price, const double sl, const double tp)
  {
   double lvl = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double ref = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(type == ORDER_TYPE_BUY)  return (ref - sl >= lvl && tp - ref >= lvl);
   return (sl - ref >= lvl && ref - tp >= lvl);
  }

void TryEnter(const int dir)
  {
   if(AnyPositionOnSymbol()) { c_skipPos++; Log("SKIP|a position is already open on this symbol"); return; }
   if(g_halted) { c_skipHalt++; Log("SKIP|dd_halted"); return; }
   if(g_dailyHalt) { c_skipDaily++; Log("SKIP|daily_stop"); return; }

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0) return;
   double spread = ask - bid;
   double dist  = (g_rangeHi - g_rangeLo) * InpSLRangePct / 100.0;
   ENUM_ORDER_TYPE type = (dir > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entry = (dir > 0) ? ask : bid;
   double stop  = (dir > 0) ? g_rangeHi - dist : g_rangeLo + dist;
   double sld   = (dir > 0) ? entry - stop : stop - entry;
   if(sld <= 0.0) { c_skipStops++; Log("SKIP|bad_sl"); return; }
   if(InpMaxSpreadPrice > 0.0 && spread > InpMaxSpreadPrice) { c_skipSpread++; Log(StringFormat("SKIP|spread %.3f > max %.3f", spread, InpMaxSpreadPrice)); return; }
   if(InpMaxSpreadPctSL > 0.0 && spread > sld * InpMaxSpreadPctSL / 100.0) { c_skipSpread++; Log(StringFormat("SKIP|spread %.3f > %.1f%% of SL %.3f", spread, InpMaxSpreadPctSL, sld)); return; }
   if((InpMinRangeATR > 0.0 || InpMaxRangeATR > 0.0) && g_atrHandle != INVALID_HANDLE)
     {
      double atr[];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) == 1 && atr[0] > 0.0)
        {
         double ratio = (g_rangeHi - g_rangeLo) / atr[0];
         if((InpMinRangeATR > 0.0 && ratio < InpMinRangeATR) || (InpMaxRangeATR > 0.0 && ratio > InpMaxRangeATR))
           { c_skipATR++; Log(StringFormat("SKIP|range/ATR %.2f outside filter", ratio)); return; }
        }
     }
   double sl = NormPrice(stop);
   double tp = NormPrice(entry + dir * sld * InpTP_R);
   if(!StopsOK(type, entry, sl, tp)) { c_skipStops++; Log("SKIP|stops_level"); return; }

   string why = "";
   double lots = LotsForRisk(type, entry, sl, why);
   if(lots <= 0.0)
     {
      if(StringFind(why, "below_min_volume") == 0) c_skipMinVol++; else c_skipMargin++;
      Log("SKIP|" + why);
      return;
     }
   // broker-side pre-check
   MqlTradeRequest rq; MqlTradeCheckResult ck; ZeroMemory(rq); ZeroMemory(ck);
   rq.action = TRADE_ACTION_DEAL; rq.symbol = _Symbol; rq.volume = lots; rq.type = type; rq.price = entry;
   rq.sl = sl; rq.tp = tp; rq.deviation = (ulong)InpDeviationPoints; rq.magic = InpMagic; rq.type_filling = g_filling;
   if(!OrderCheck(rq, ck)) { c_skipCheck++; Log(StringFormat("SKIP|OrderCheck %u %s", ck.retcode, ck.comment)); return; }

   bool ok = (dir > 0) ? g_trade.Buy(lots, _Symbol, 0.0, sl, tp, InpComment)
                       : g_trade.Sell(lots, _Symbol, 0.0, sl, tp, InpComment);
   if(!ok || (g_trade.ResultRetcode() != TRADE_RETCODE_DONE && g_trade.ResultRetcode() != TRADE_RETCODE_PLACED))
     { c_sendFail++; Log(StringFormat("ERR|send %u %s", g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription())); return; }
   c_opened++;
   Log(StringFormat("OPEN|%s lots=%.2f entry=%.3f sl=%.3f tp=%.3f riskR=%.3f", dir > 0 ? "BUY" : "SELL", lots, entry, sl, tp, sld));
  }

void ManageBreakEven()
  {
   if(InpBE_TriggerR <= 0.0) return;
   ulong tk;
   if(!GetMyPosition(tk) || !PositionSelectByTicket(tk)) return;
   long   ptype = PositionGetInteger(POSITION_TYPE);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double tp    = PositionGetDouble(POSITION_TP);
   if(sl <= 0.0) return;
   int dir = (ptype == POSITION_TYPE_BUY) ? 1 : -1;
   double risk = (open - sl) * dir;            // > 0 only before the BE move
   if(risk <= 0.0) return;
   double px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if((px - open) * dir < InpBE_TriggerR * risk) return;
   double nsl = NormPrice(open + dir * InpBE_LockR * risk);
   double lvl = (double)MathMax(SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL), SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL)) * _Point;
   if((px - nsl) * dir < lvl) return;          // too close to market: retry on a later tick
   if(g_trade.PositionModify(tk, nsl, tp)) { c_beMoves++; Log(StringFormat("BE|sl -> %.3f", nsl)); }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   bool tester = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   long mode = AccountInfoInteger(ACCOUNT_TRADE_MODE);
   if(!tester && mode == ACCOUNT_TRADE_MODE_REAL && !InpAllowRealAccount)
     {
      Print("XAU300|REFUSED|real account and AllowRealAccount=false. This EA is research-only.");
      return INIT_FAILED;
     }
   if(InpRiskPercent <= 0.0 || InpRiskPercent > 10.0) { Print("XAU300|BAD_INPUT|RiskPercent must be in (0,10]"); return INIT_PARAMETERS_INCORRECT; }
   if(InpRangeMinutes < 5 || InpRangeStartHour < 0 || InpRangeStartHour > 23 || InpEntryEndHour > InpExitHour)
     { Print("XAU300|BAD_INPUT|session"); return INIT_PARAMETERS_INCORRECT; }
   if(InpTP_R <= 0.0 || InpSLRangePct <= 0.0) { Print("XAU300|BAD_INPUT|exits"); return INIT_PARAMETERS_INCORRECT; }
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpDeviationPoints);
   g_trade.SetMarginMode();
   SetFilling();
   if(InpMinRangeATR > 0.0 || InpMaxRangeATR > 0.0)
      g_atrHandle = iATR(_Symbol, PERIOD_D1, InpATRPeriodD1);
   LoadState();
   EquityOpen();
   PrintFormat("XAU300|%s|INIT|symbol=%s digits=%d tick=%.5f contract=%.2f vmin=%.2f vstep=%.2f lev=%I64d mode=%I64d tester=%d risk=%.2f%% dl=%.1f%% dd=%.1f%%",
               InpRunTag, _Symbol, _Digits, TickSize(), SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE),
               SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP),
               AccountInfoInteger(ACCOUNT_LEVERAGE), mode, (int)tester, InpRiskPercent, InpDailyLossPct, InpMaxDDPct);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   EquityClose();
   PrintFormat("XAU300|%s|SUMMARY|signals=%d opened=%d skip_position=%d skip_halted=%d skip_daily=%d skip_spread=%d skip_min_volume=%d skip_margin=%d skip_stops=%d skip_atr=%d skip_check=%d kill_days=%d be_moves=%d time_exits=%d dd_halts=%d send_fail=%d daily_stops=%d close_fail=%d peak=%.2f halted=%d",
               InpRunTag, c_signals, c_opened, c_skipPos, c_skipHalt, c_skipDaily, c_skipSpread, c_skipMinVol, c_skipMargin,
               c_skipStops, c_skipATR, c_skipCheck, c_killDays, c_beMoves, c_timeExits, c_ddHalts, c_sendFail,
               c_dailyStops, c_closeFail, g_peakEquity, (int)g_halted);
  }

void OnTick()
  {
   EquitySample(false);                        // research export: before any early return
   datetime now = TimeCurrent();
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);

   // 1) persistent peak-equity DD stop: once set, flatten on every tick until flat (also after restart)
   if(!g_halted && InpMaxDDPct > 0.0 && g_peakEquity > 0.0 && eq <= g_peakEquity * (1.0 - InpMaxDDPct / 100.0))
     {
      g_halted = true; c_ddHalts++;
      GVSet("halt", 1.0);
      Log(StringFormat("HALT|equity %.2f <= peak %.2f - %.1f%% (trigger, not a guaranteed cap)", eq, g_peakEquity, InpMaxDDPct));
     }
   if(g_halted) { FlattenMine("dd_halt"); return; }
   SavePeak(eq);

   // 2) day roll (server date), state restored on restart
   if(DayKey(now) != g_dayKey) NewDay(now);

   // 2b) daily hard stop: flatten (retry every tick) and no entries until the next day
   if(!g_dailyHalt && InpDailyLossPct > 0.0 && eq <= g_dayStartBal * (1.0 - InpDailyLossPct / 100.0))
     {
      g_dailyHalt = true; c_dailyStops++; SaveDay();
      Log(StringFormat("DAILY|equity %.2f <= day start %.2f - %.1f%% (trigger, not a guaranteed cap)", eq, g_dayStartBal, InpDailyLossPct));
     }
   if(g_dailyHalt) { FlattenMine("daily_stop"); return; }

   MqlDateTime t; TimeToStruct(now, t);
   // 3) time exit (one bounded attempt per tick)
   ulong tk;
   if(t.hour >= InpExitHour && t.hour < 23 && GetMyPosition(tk)) { if(FlattenMine("time_exit")) c_timeExits++; }

   // 4) break-even management (server-side SL modify)
   ManageBreakEven();

   // 5) closed-bar signal
   if(g_halted || g_daySkip || t.hour >= InpExitHour) return;
   if(now < g_rangeEnd || t.hour >= InpEntryEndHour) return;
   if(!g_rangeReady && !BuildRange()) return;

   datetime cur = iTime(_Symbol, InpSignalTF, 0);
   if(cur == 0 || cur == g_lastSignalBar) return;
   datetime closedOpen = iTime(_Symbol, InpSignalTF, 1);
   if(closedOpen < g_rangeEnd) { g_lastSignalBar = cur; return; }   // closed bar must start after the range
   g_lastSignalBar = cur;
   double cl = iClose(_Symbol, InpSignalTF, 1);                      // closed bar only: no lookahead
   if(cl <= 0.0) return;

   if(cl >= g_rangeLo && cl <= g_rangeHi && (!g_armL || !g_armS)) { g_armL = true; g_armS = true; SaveDay(); }
   int dir = 0;
   if(cl > g_rangeHi && g_armL && g_cntL < InpMaxSignalsPerDir) dir = 1;
   else if(cl < g_rangeLo && g_armS && g_cntS < InpMaxSignalsPerDir) dir = -1;
   if(dir == 0) return;
   if(dir > 0) { g_cntL++; g_armL = false; } else { g_cntS++; g_armS = false; }
   SaveDay();
   c_signals++;
   Log(StringFormat("SIGNAL|%s close=%.3f range=[%.3f,%.3f]", dir > 0 ? "BUY" : "SELL", cl, g_rangeLo, g_rangeHi));
   TryEnter(dir);
  }

double OnTester()
  {
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+
