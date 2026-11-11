//+------------------------------------------------------------------+
//|  XAU_MultiSession_EA v1.00 — EA ทองคำหลายเซสชัน (XAUUSD, M5)       |
//|                                                                  |
//|  โมดูล (magic = base + n):                                        |
//|   1 Asia   00:30-06:00 UTC  BB range fade                         |
//|   2 London 07:00-10:30 UTC  Asian box breakout + sweep reversal   |
//|   3 NY     12:30-16:00 UTC  ORB + EMA pullback ตาม bias           |
//|   4 NY-PM  16:00-20:00 UTC  continuation หรือ VWAP fade ตามวัน     |
//|  เวลาด้านบนเป็นฤดูหนาว London เลื่อนตาม DST ยุโรป NY ตาม DST สหรัฐ    |
//|                                                                  |
//|  ข้อจำกัดของ v1.00 (ต่างจากเอกสารแบบ):                             |
//|   - เข้าไม้ด้วย market order เมื่อแท่ง M5 ปิด ไม่ใช้ pending          |
//|   - ยังไม่มี news filter และตารางวันหยุด                           |
//|   - ต้องใช้บัญชี hedging (netting จะรวม position ข้ามโมดูล)         |
//|  แบบเต็ม: MQL5/Docs/XAU_MultiSession_EA_Design.md                 |
//+------------------------------------------------------------------+
#property copyright "XAU MultiSession EA"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

#define MOD_ASIA   0
#define MOD_LONDON 1
#define MOD_NY     2
#define MOD_PM     3
#define MODS       4

input group "=== ทั่วไป ==="
input long          InpMagicBase       = 880000;   // Magic base (โมดูล = base+1..4)
input int           InpServerGMTWinter = 2;        // GMT offset ของเซิร์ฟเวอร์ช่วงฤดูหนาว
input ENUM_DST_MODE InpServerDST       = DST_US;   // กฎ DST ของเซิร์ฟเวอร์
input bool          InpUseAsia         = true;     // เปิดโมดูล Asia
input bool          InpUseLondon       = true;     // เปิดโมดูล London
input bool          InpUseNY           = true;     // เปิดโมดูล NY
input bool          InpUsePM           = true;     // เปิดโมดูล NY-PM

input group "=== ความเสี่ยง ==="
input double InpRiskMain      = 1.5;    // Risk ต่อไม้ London / NY (% equity)
input double InpRiskMinor     = 0.75;   // Risk ต่อไม้ Asia / NY-PM (% equity)
input double InpMaxOpenRisk   = 4.0;    // Risk รวมที่เปิดอยู่สูงสุด (%)
input double InpDailyLossPct  = 6.0;    // Daily loss (%) แล้วหยุดทั้งวัน
input double InpDDHalf        = 25.0;   // DD จาก peak (%) ลด risk เหลือครึ่ง
input double InpDDQuarter     = 40.0;   // DD จาก peak (%) ลด risk เหลือหนึ่งในสี่
input double InpDDHalt        = 45.0;   // DD จาก peak (%) หยุด EA
input bool   InpResetHalt     = false;  // true = ล้างสถานะหยุดและตั้ง peak ใหม่ตอนเริ่ม
input double InpMaxLot        = 5.0;    // Lot สูงสุดต่อไม้
input double InpSpreadPct     = 15.0;   // Spread สูงสุด (% ของระยะ SL)
input double InpSpreadPctPM   = 12.0;   // Spread สูงสุดของ NY-PM (% ของระยะ SL)

input group "=== การจัดการไม้ ==="
input double InpPartialPct    = 50.0;   // ปิดบางส่วนที่ 1R (%)
input double InpTrailATR      = 1.2;    // Trailing หลัง BE (×ATR M5)
input int    InpTimeStopAsia  = 12;     // Time-stop Asia (แท่ง M5)
input int    InpTimeStopMain  = 8;      // Time-stop London / NY (แท่ง M5)
input int    InpTimeStopPM    = 10;     // Time-stop NY-PM (แท่ง M5)

input group "=== Asia ==="
input double InpAsiaMaxBoxADR = 0.35;   // กรอบเอเชียสูงสุด (×ADR)
input double InpAsiaADXMax    = 20.0;   // ADX(M15) สูงสุด
input double InpAsiaRSILow    = 30.0;   // RSI(7) ฝั่งล่าง (ฝั่งบน = 100 - ค่านี้)
input double InpAsiaSLATR     = 1.0;    // SL เลย extreme (×ATR)
input int    InpAsiaMaxTrades = 3;      // ไม้สูงสุดต่อวัน
input int    InpAsiaMaxLosses = 2;      // แพ้ติดกันแล้วหยุด

input group "=== London ==="
input double InpLonBoxMinADR  = 0.15;   // กรอบเอเชียขั้นต่ำ (×ADR)
input double InpLonBoxMaxADR  = 0.45;   // กรอบเอเชียสูงสุด (×ADR)
input bool   InpLonBreakout   = true;   // โหมด A: breakout
input bool   InpLonSweep      = true;   // โหมด B: sweep reversal
input double InpLonBreakATR   = 0.10;   // ระยะปิดนอกกรอบขั้นต่ำ (×ATR)
input double InpLonSweepATR   = 0.15;   // ระยะ sweep ขั้นต่ำ (×ATR)
input double InpLonSLATR      = 1.5;    // SL สูงสุดของ breakout (×ATR)
input int    InpLonMaxTrades  = 3;      // ไม้สูงสุดต่อวัน

input group "=== New York ==="
input bool   InpNYORB         = true;   // Setup 1: ORB 15 นาที
input bool   InpNYPullback    = true;   // Setup 2: pullback EMA20
input double InpNYADXMin      = 20.0;   // ADX(M15) ขั้นต่ำของ pullback
input double InpNYMaxSLATR    = 2.0;    // SL สูงสุด (×ATR)
input int    InpNYMaxTrades   = 4;      // ไม้สูงสุดต่อวัน
input int    InpNYMaxLosses   = 2;      // แพ้ติดกันแล้วหยุด

input group "=== NY-PM ==="
input double InpPMTrendADR    = 1.0;    // Trend day: range ของวันขั้นต่ำ (×ADR)
input double InpPMRangeADR    = 0.7;    // Range day: range ของวันสูงสุด (×ADR)
input double InpPMTrendADX    = 25.0;   // Trend day: ADX(M15) ขั้นต่ำ
input double InpPMRangeADX    = 20.0;   // Range day: ADX(M15) สูงสุด
input int    InpPMMinCrosses  = 3;      // Range day: จำนวนครั้งที่ราคาตัด VWAP ขั้นต่ำ
input int    InpPMMaxTrades   = 2;      // ไม้สูงสุดต่อวัน
input int    InpPMMaxLosses   = 1;      // แพ้ติดกันแล้วหยุด

input group "=== Log ==="
input bool   InpWriteLog      = true;   // บันทึก CSV ทุกไม้
input string InpLogFile       = "xau_multisession_trades.csv";

//--- globals
CTrade   trade;
int      hATR, hADX, hBB, hRSI, hEMA20, hEMA50;
datetime gLastBar = 0;
long     gDayKey  = -1;
string   gPfx;
double   gScale   = 1.0;          // ตัวคูณ risk ตาม DD
bool     gHalted  = false, gDayStop = false;
double   gDayStartEq = 0;
// หน้าต่างเวลา (นาทีของวัน UTC)
int      gLonS, gLonE, gNyS, gNyE, gOrbS, gPmS, gPmE, gFlat;
long     gOffSec = 0;             // server - UTC (วินาที)
// ข้อมูลของวัน (จากแท่ง M5 ที่ปิดแล้ว)
MqlRates gR[];
int      gN = 0;
double   gATR = 0, gATRAvg = 0, gADR = 0, gADX = 0;
double   gDayHi, gDayLo, gAsiaHi, gAsiaLo, gOrbHi, gOrbLo, gPreHi, gPreLo, gP16;
bool     gHasAsia, gHasOrb, gHasPre;
double   gVWAP, gVWSD;
int      gCrosses;
// สถานะรายวัน
bool     gLonLong, gLonShort, gOrbDone, gHandoff;
int      gPmMode;                 // 0 ไม่เทรด, 1/-1 trend ขึ้น/ลง, 2 range, 9 ยังไม่จำแนก
string   gStatus = "";

//+------------------------------------------------------------------+
//| เวลาและ DST                                                       |
//+------------------------------------------------------------------+
datetime NthSunday(int year, int mon, int n)   // n>0 = อาทิตย์ที่ n, n=0 = อาทิตย์สุดท้าย
{
   MqlDateTime d;
   if(n > 0)
   {
      datetime first = StringToTime(StringFormat("%04d.%02d.01", year, mon));
      TimeToStruct(first, d);
      return first + ((7 - d.day_of_week) % 7 + 7 * (n - 1)) * 86400;
   }
   int ny = year, nm = mon + 1;
   if(nm > 12) { nm = 1; ny++; }
   datetime last = StringToTime(StringFormat("%04d.%02d.01", ny, nm)) - 86400;
   TimeToStruct(last, d);
   return last - d.day_of_week * 86400;
}
bool IsUSDST(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   return t >= NthSunday(d.year, 3, 2) && t < NthSunday(d.year, 11, 1);
}
bool IsEUDST(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   return t >= NthSunday(d.year, 3, 0) && t < NthSunday(d.year, 10, 0);
}
int ServerOffsetHours(datetime t)
{
   int off = InpServerGMTWinter;
   if(InpServerDST == DST_US && IsUSDST(t)) off++;
   if(InpServerDST == DST_EU && IsEUDST(t)) off++;
   return off;
}

//+------------------------------------------------------------------+
//| ตัวช่วย                                                           |
//+------------------------------------------------------------------+
double Val(int handle, int buffer, int shift)
{
   double b[1];
   if(CopyBuffer(handle, buffer, shift, 1, b) != 1) return EMPTY_VALUE;
   return b[0];
}
long   ModMagic(int mod)      { return InpMagicBase + 1 + mod; }
bool   IsOurMagic(long m)     { return m >= InpMagicBase + 1 && m <= InpMagicBase + MODS; }
double Spread()               { return SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID); }
double GVGet(string k, double def) { return GlobalVariableCheck(gPfx + k) ? GlobalVariableGet(gPfx + k) : def; }
void   GVSet(string k, double v)   { GlobalVariableSet(gPfx + k, v); }

void LogLine(string s)
{
   if(!InpWriteLog) return;
   int f = FileOpen(InpLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) return;
   if(FileSize(f) == 0)
      FileWriteString(f, "time,event,module,dir,lots,req_price,fill_price,spread,sl,tp,net_profit,tag\r\n");
   FileSeek(f, 0, SEEK_END);
   FileWriteString(f, s + "\r\n");
   FileClose(f);
}

bool HasOpen(int mod)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == ModMagic(mod)) return true;
   }
   return false;
}

//--- risk ที่เปิดอยู่รวม (% equity) นับเฉพาะไม้ที่ SL ยังอยู่ฝั่งขาดทุน
double OpenRiskPct()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(ts <= 0 || eq <= 0) return 0;
   double sum = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !IsOurMagic(PositionGetInteger(POSITION_MAGIC))) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      if(sl <= 0) continue;
      double dist = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? op - sl : sl - op;
      if(dist > 0) sum += dist / ts * tv * PositionGetDouble(POSITION_VOLUME);
   }
   return 100.0 * sum / eq;
}

//--- นับไม้ของวันนี้และจำนวนแพ้ติดกันล่าสุดของโมดูล (รวมผลต่อ position)
void CountToday(int mod, int &trades, int &consecLoss)
{
   trades = 0; consecLoss = 0;
   datetime from = (datetime)(gDayKey * 86400 + gOffSec);
   if(!HistorySelect(from, TimeCurrent() + 60)) return;
   ulong ids[]; double net[];
   int n = 0, total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol || HistoryDealGetInteger(d, DEAL_MAGIC) != ModMagic(mod)) continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      int idx = -1;
      for(int k = 0; k < n; k++) if(ids[k] == pid) { idx = k; break; }
      if(idx < 0)
      {
         ArrayResize(ids, n + 1); ArrayResize(net, n + 1);
         ids[n] = pid; net[n] = 0; idx = n; n++;
      }
      if(HistoryDealGetInteger(d, DEAL_ENTRY) == DEAL_ENTRY_IN) trades++;
      net[idx] += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) + HistoryDealGetDouble(d, DEAL_COMMISSION);
   }
   for(int k = n - 1; k >= 0; k--)
   {
      if(PositionSelectByTicket(ids[k])) continue;      // ยังเปิดอยู่
      if(net[k] < 0) consecLoss++; else break;
   }
}

void ClosePositions(int mod, bool onlyInitialSL)      // mod = -1 คือทุกโมดูล
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !IsOurMagic(mg)) continue;
      if(mod >= 0 && mg != ModMagic(mod)) continue;
      if(onlyInitialSL)
      {
         double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
         bool initial = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? (sl < op) : (sl > op);
         if(!initial) continue;
      }
      trade.SetExpertMagicNumber(mg);
      trade.PositionClose(t);
   }
}

//+------------------------------------------------------------------+
//| เปิดไม้: ตรวจ spread, RR, lot, เพดาน risk รวม                      |
//+------------------------------------------------------------------+
bool OpenTrade(int mod, int dir, double sl, double tp, double minRR, string tag)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = dir > 0 ? ask : bid;
   double slDist = dir > 0 ? entry - sl : sl - entry;
   double spread = ask - bid;
   double stopLv = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(slDist <= 0 || slDist < stopLv) return false;

   double maxPct = (mod == MOD_PM) ? InpSpreadPctPM : InpSpreadPct;
   if(spread > slDist * maxPct / 100.0) { gStatus = "ข้าม: spread กว้างเกิน (" + tag + ")"; return false; }

   if(tp > 0)
   {
      double tpDist = dir > 0 ? tp - entry : entry - tp;
      if(tpDist < slDist * minRR || tpDist < stopLv) { gStatus = "ข้าม: RR ต่ำ (" + tag + ")"; return false; }
   }

   double riskPct = ((mod == MOD_LONDON || mod == MOD_NY) ? InpRiskMain : InpRiskMinor) * gScale;
   if(OpenRiskPct() + riskPct > InpMaxOpenRisk) { gStatus = "ข้าม: risk รวมเต็ม (" + tag + ")"; return false; }

   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tv <= 0 || ts <= 0) return false;
   double lots = AccountInfoDouble(ACCOUNT_EQUITY) * riskPct / 100.0 / (slDist / ts * tv);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lots = MathFloor(lots / step) * step;
   lots = MathMin(lots, MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
   if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) { gStatus = "ข้าม: lot ต่ำกว่าขั้นต่ำ (" + tag + ")"; return false; }
   lots = NormalizeDouble(lots, 2);

   sl = NormalizeDouble(sl, _Digits);
   tp = tp > 0 ? NormalizeDouble(tp, _Digits) : 0;
   trade.SetExpertMagicNumber(ModMagic(mod));
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, tag) : trade.Sell(lots, _Symbol, 0, sl, tp, tag);
   if(!ok || (trade.ResultRetcode() != TRADE_RETCODE_DONE && trade.ResultRetcode() != TRADE_RETCODE_PLACED))
   {
      gStatus = "order ล้มเหลว " + IntegerToString((int)trade.ResultRetcode()) + " (" + tag + ")";
      return false;
   }
   gStatus = "เปิด " + tag;
   LogLine(StringFormat("%s,OPEN,%d,%d,%.2f,%s,%s,%s,%s,%s,,%s",
           TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), mod + 1, dir, lots,
           DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits),
           DoubleToString(spread, _Digits), DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), tag));
   return true;
}

//+------------------------------------------------------------------+
//| จัดการไม้: partial + BE ที่ 1R, trailing, time-stop                 |
//+------------------------------------------------------------------+
void ManagePositions()
{
   if(gATR <= 0) return;
   double stopLv = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      long mg = PositionGetInteger(POSITION_MAGIC);
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || !IsOurMagic(mg)) continue;
      int    mod = (int)(mg - InpMagicBase - 1);
      int    dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double op  = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      double tp  = PositionGetDouble(POSITION_TP);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double cur = dir > 0 ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double profit = (cur - op) * dir;
      if(sl <= 0) continue;
      bool initial = dir > 0 ? (sl < op) : (sl > op);
      trade.SetExpertMagicNumber(mg);

      if(initial)
      {
         double R = (op - sl) * dir;
         if(profit >= R)
         {
            double part = MathFloor(vol * InpPartialPct / 100.0 / step) * step;
            if(part >= minLot && vol - part >= minLot) trade.PositionClosePartial(t, NormalizeDouble(part, 2));
            double be = NormalizeDouble(op + dir * Spread(), _Digits);
            if((cur - be) * dir > stopLv) trade.PositionModify(t, be, tp);
         }
         else
         {
            int limit = (mod == MOD_ASIA) ? InpTimeStopAsia : (mod == MOD_PM ? InpTimeStopPM : InpTimeStopMain);
            int bars  = (int)((TimeCurrent() - (datetime)PositionGetInteger(POSITION_TIME)) / 300);
            if(limit > 0 && bars >= limit && profit < 0.5 * R) trade.PositionClose(t);
         }
      }
      else
      {
         double ns = NormalizeDouble(cur - dir * InpTrailATR * gATR, _Digits);
         if((ns - sl) * dir > 10 * _Point && (cur - ns) * dir > stopLv) trade.PositionModify(t, ns, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| โหลดแท่ง M5 ของวัน (UTC) และคำนวณบริบท                             |
//+------------------------------------------------------------------+
bool LoadDay()
{
   datetime from = (datetime)(gDayKey * 86400 + gOffSec);
   int got = CopyRates(_Symbol, PERIOD_M5, from, TimeCurrent(), gR);
   if(got <= 0) return false;
   gN = got;
   if(gR[gN - 1].time == iTime(_Symbol, PERIOD_M5, 0)) gN--;     // ตัดแท่งที่ยังไม่ปิด
   if(gN < 3) return false;

   double a[];
   if(CopyBuffer(hATR, 0, 1, 20, a) != 20) return false;
   gATR = a[19]; gATRAvg = 0;
   for(int i = 0; i < 20; i++) gATRAvg += a[i];
   gATRAvg /= 20.0;
   gADX = Val(hADX, 0, 1);
   if(gATR <= 0 || gADX == EMPTY_VALUE) return false;

   MqlRates d[];
   if(CopyRates(_Symbol, PERIOD_D1, 1, 14, d) != 14) return false;
   gADR = 0;
   for(int i = 0; i < 14; i++) gADR += d[i].high - d[i].low;
   gADR /= 14.0;
   if(gADR <= 0) return false;

   gHasAsia = false; gHasOrb = false; gHasPre = false; gCrosses = 0;
   gDayHi = gR[0].high; gDayLo = gR[0].low;
   double cumPV = 0, cumV = 0, vw = 0; int prevS = 0;
   for(int i = 0; i < gN; i++)
   {
      int mn = (int)((((long)gR[i].time - gOffSec) % 86400) / 60);
      double h = gR[i].high, l = gR[i].low, c = gR[i].close;
      gDayHi = MathMax(gDayHi, h); gDayLo = MathMin(gDayLo, l);
      if(mn < 360)
      {
         if(!gHasAsia) { gAsiaHi = h; gAsiaLo = l; gHasAsia = true; }
         else { gAsiaHi = MathMax(gAsiaHi, h); gAsiaLo = MathMin(gAsiaLo, l); }
      }
      if(mn >= gOrbS && mn < gOrbS + 15)
      {
         if(!gHasOrb) { gOrbHi = h; gOrbLo = l; gHasOrb = true; }
         else { gOrbHi = MathMax(gOrbHi, h); gOrbLo = MathMin(gOrbLo, l); }
      }
      if(mn < gPmS)
      {
         if(!gHasPre) { gPreHi = h; gPreLo = l; gHasPre = true; }
         else { gPreHi = MathMax(gPreHi, h); gPreLo = MathMin(gPreLo, l); }
         gP16 = c;
      }
      double v = (double)MathMax(gR[i].tick_volume, 1);
      cumPV += (h + l + c) / 3.0 * v; cumV += v; vw = cumPV / cumV;
      if(mn >= gNyS && mn < gPmS)
      {
         int s = c > vw ? 1 : -1;
         if(prevS != 0 && s != prevS) gCrosses++;
         prevS = s;
      }
   }
   gVWAP = vw;
   double var = 0;
   for(int i = 0; i < gN; i++)
   {
      double v = (double)MathMax(gR[i].tick_volume, 1);
      double tpv = (gR[i].high + gR[i].low + gR[i].close) / 3.0;
      var += v * (tpv - gVWAP) * (tpv - gVWAP);
   }
   gVWSD = MathSqrt(var / cumV);
   return true;
}

//+------------------------------------------------------------------+
//| โมดูล                                                             |
//+------------------------------------------------------------------+
void ModuleAsia()
{
   if(!gHasAsia || HasOpen(MOD_ASIA)) return;
   if((gAsiaHi - gAsiaLo) > InpAsiaMaxBoxADR * gADR || gADX >= InpAsiaADXMax) return;
   int tr, cl; CountToday(MOD_ASIA, tr, cl);
   if(tr >= InpAsiaMaxTrades || cl >= InpAsiaMaxLosses) return;

   double up = Val(hBB, 1, 1), lo = Val(hBB, 2, 1), mid = Val(hBB, 0, 1);
   double r1 = Val(hRSI, 0, 1), r2 = Val(hRSI, 0, 2);
   if(up == EMPTY_VALUE || lo == EMPTY_VALUE || r1 == EMPTY_VALUE || r2 == EMPTY_VALUE) return;
   MqlRates b = gR[gN - 1];
   if(b.low < lo && b.close > lo && MathMin(r1, r2) < InpAsiaRSILow)
      OpenTrade(MOD_ASIA, 1, b.low - InpAsiaSLATR * gATR, mid, 0.8, "ASIA_FADE");
   else if(b.high > up && b.close < up && MathMax(r1, r2) > 100.0 - InpAsiaRSILow)
      OpenTrade(MOD_ASIA, -1, b.high + InpAsiaSLATR * gATR, mid, 0.8, "ASIA_FADE");
}

void ModuleLondon()
{
   if(!gHasAsia || HasOpen(MOD_LONDON)) return;
   double box = gAsiaHi - gAsiaLo;
   if(box < InpLonBoxMinADR * gADR || box > InpLonBoxMaxADR * gADR) return;
   int tr, cl; CountToday(MOD_LONDON, tr, cl);
   if(tr >= InpLonMaxTrades) return;

   MqlRates b = gR[gN - 1], p = gR[gN - 2];
   double mid = (gAsiaHi + gAsiaLo) / 2.0;
   double swHi = MathMax(b.high, MathMax(p.high, gR[gN - 3].high));
   double swLo = MathMin(b.low,  MathMin(p.low,  gR[gN - 3].low));

   //--- โหมด B: sweep reversal (ตรวจก่อน เพราะเป็นสัญญาณกลับด้านของ breakout ที่ล้มเหลว)
   if(InpLonSweep)
   {
      if(!gLonShort && swHi > gAsiaHi + InpLonSweepATR * gATR && b.close < gAsiaHi)
      { if(OpenTrade(MOD_LONDON, -1, swHi + 0.2 * gATR, gAsiaLo, 1.0, "LON_SWEEP")) gLonShort = true; return; }
      if(!gLonLong && swLo < gAsiaLo - InpLonSweepATR * gATR && b.close > gAsiaLo)
      { if(OpenTrade(MOD_LONDON, 1, swLo - 0.2 * gATR, gAsiaHi, 1.0, "LON_SWEEP")) gLonLong = true; return; }
   }
   //--- โหมด A: breakout
   if(InpLonBreakout && gATR > gATRAvg)
   {
      double buf = InpLonBreakATR * gATR;
      if(!gLonLong && b.close > gAsiaHi + buf && p.close <= gAsiaHi + buf)
      { if(OpenTrade(MOD_LONDON, 1, MathMax(mid, b.close - InpLonSLATR * gATR), 0, 0, "LON_BREAK")) gLonLong = true; return; }
      if(!gLonShort && b.close < gAsiaLo - buf && p.close >= gAsiaLo - buf)
      { if(OpenTrade(MOD_LONDON, -1, MathMin(mid, b.close + InpLonSLATR * gATR), 0, 0, "LON_BREAK")) gLonShort = true; return; }
   }
}

void ModuleNY(int mn)
{
   if(HasOpen(MOD_NY)) return;
   int tr, cl; CountToday(MOD_NY, tr, cl);
   if(tr >= InpNYMaxTrades || cl >= InpNYMaxLosses) return;
   double e50 = Val(hEMA50, 0, 1), e20 = Val(hEMA20, 0, 1);
   if(e50 == EMPTY_VALUE || e20 == EMPTY_VALUE) return;
   MqlRates b = gR[gN - 1], p = gR[gN - 2];
   int bias = 0;
   if(b.close > e50 && b.close > gVWAP) bias = 1;
   if(b.close < e50 && b.close < gVWAP) bias = -1;
   if(bias == 0) return;

   //--- Setup 1: ORB
   if(InpNYORB && !gOrbDone && gHasOrb && mn >= gOrbS + 15)
   {
      if(bias > 0 && b.close > gOrbHi && p.close <= gOrbHi)
      { if(OpenTrade(MOD_NY, 1, MathMax(gOrbLo, b.close - InpNYMaxSLATR * gATR), 0, 0, "NY_ORB")) gOrbDone = true; return; }
      if(bias < 0 && b.close < gOrbLo && p.close >= gOrbLo)
      { if(OpenTrade(MOD_NY, -1, MathMin(gOrbHi, b.close + InpNYMaxSLATR * gATR), 0, 0, "NY_ORB")) gOrbDone = true; return; }
   }
   //--- Setup 2: pullback ถึง EMA20 แล้วปิดกลับตามทาง
   if(InpNYPullback && gADX >= InpNYADXMin)
   {
      if(bias > 0 && b.low <= e20 && b.close > e20 && b.close > b.open)
      {
         double sl = MathMin(b.low, p.low) - 0.3 * gATR;
         if(b.close - sl <= InpNYMaxSLATR * gATR) OpenTrade(MOD_NY, 1, sl, 0, 0, "NY_PULLBACK");
      }
      else if(bias < 0 && b.high >= e20 && b.close < e20 && b.close < b.open)
      {
         double sl = MathMax(b.high, p.high) + 0.3 * gATR;
         if(sl - b.close <= InpNYMaxSLATR * gATR) OpenTrade(MOD_NY, -1, sl, 0, 0, "NY_PULLBACK");
      }
   }
}

void ModulePM()
{
   //--- จำแนกประเภทวันครั้งเดียวเมื่อเข้าเซสชัน
   if(gPmMode == 9)
   {
      gPmMode = 0;
      if(gHasPre && gPreHi > gPreLo)
      {
         double rng = (gPreHi - gPreLo) / gADR;
         double pos = (gP16 - gPreLo) / (gPreHi - gPreLo);
         if(rng >= InpPMTrendADR && gADX >= InpPMTrendADX)
         {
            if(pos >= 0.75) gPmMode = 1;
            if(pos <= 0.25) gPmMode = -1;
         }
         else if(rng < InpPMRangeADR && gADX < InpPMRangeADX && gCrosses >= InpPMMinCrosses) gPmMode = 2;
      }
   }
   if(gPmMode == 0 || HasOpen(MOD_PM)) return;
   if(gDayStartEq > 0 && (gDayStartEq - AccountInfoDouble(ACCOUNT_EQUITY)) / gDayStartEq * 100.0 > InpDailyLossPct / 2.0) return;
   int tr, cl; CountToday(MOD_PM, tr, cl);
   if(tr >= InpPMMaxTrades || cl >= InpPMMaxLosses) return;

   MqlRates b = gR[gN - 1], p = gR[gN - 2];
   if(gPmMode == 1 || gPmMode == -1)          // โหมด A: continuation
   {
      double e20 = Val(hEMA20, 0, 1);
      if(e20 == EMPTY_VALUE) return;
      if(gPmMode == 1 && b.low <= e20 && b.close > e20 && b.close > b.open)
         OpenTrade(MOD_PM, 1, MathMin(MathMin(b.low, p.low) - 0.2 * gATR, b.close - 1.2 * gATR), gDayHi, 1.0, "PM_CONT");
      else if(gPmMode == -1 && b.high >= e20 && b.close < e20 && b.close < b.open)
         OpenTrade(MOD_PM, -1, MathMax(MathMax(b.high, p.high) + 0.2 * gATR, b.close + 1.2 * gATR), gDayLo, 1.0, "PM_CONT");
   }
   else                                        // โหมด B: VWAP fade
   {
      double r1 = Val(hRSI, 0, 1), r2 = Val(hRSI, 0, 2);
      if(r1 == EMPTY_VALUE || r2 == EMPTY_VALUE || gVWSD <= 0) return;
      double up = gVWAP + 2.0 * gVWSD, lo = gVWAP - 2.0 * gVWSD;
      if(b.low < lo && b.close > lo && MathMin(r1, r2) < 30.0)
         OpenTrade(MOD_PM, 1, b.low - gATR, gVWAP, 0.8, "PM_FADE");
      else if(b.high > up && b.close < up && MathMax(r1, r2) > 70.0)
         OpenTrade(MOD_PM, -1, b.high + gATR, gVWAP, 0.8, "PM_FADE");
   }
}

//+------------------------------------------------------------------+
//| Guard ระดับบัญชี: DD และ daily loss                                |
//+------------------------------------------------------------------+
void UpdateGuards()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet("peak", eq);
   if(eq > peak || !GlobalVariableCheck(gPfx + "peak")) { peak = MathMax(eq, peak); GVSet("peak", peak); }
   double dd = peak > 0 ? (peak - eq) / peak * 100.0 : 0;
   gScale = dd >= InpDDQuarter ? 0.25 : (dd >= InpDDHalf ? 0.5 : 1.0);
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GVSet("halted", 1);
      ClosePositions(-1, false);
      Print("XAU_MultiSession: DD ถึงเพดาน หยุด EA — ตั้ง InpResetHalt=true เพื่อเริ่มใหม่");
   }
   if(gDayStartEq > 0 && !gDayStop && (gDayStartEq - eq) / gDayStartEq * 100.0 >= InpDailyLossPct)
   {
      gDayStop = true;
      ClosePositions(-1, false);
      Print("XAU_MultiSession: ถึง daily loss หยุดจนถึงวันถัดไป");
   }
}

//+------------------------------------------------------------------+
int OnInit()
{
   gPfx = "XMS_" + IntegerToString(InpMagicBase) + "_" + _Symbol + "_";
   hATR   = iATR(_Symbol, PERIOD_M5, 14);
   hADX   = iADX(_Symbol, PERIOD_M15, 14);
   hBB    = iBands(_Symbol, PERIOD_M5, 20, 0, 2.0, PRICE_CLOSE);
   hRSI   = iRSI(_Symbol, PERIOD_M5, 7, PRICE_CLOSE);
   hEMA20 = iMA(_Symbol, PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE);
   hEMA50 = iMA(_Symbol, PERIOD_M15, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(hATR == INVALID_HANDLE || hADX == INVALID_HANDLE || hBB == INVALID_HANDLE ||
      hRSI == INVALID_HANDLE || hEMA20 == INVALID_HANDLE || hEMA50 == INVALID_HANDLE)
   { Print("สร้าง indicator ไม่สำเร็จ"); return INIT_FAILED; }

   if((ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("คำเตือน: บัญชีไม่ใช่ hedging — position ข้ามโมดูลจะรวมกันและการจัดการไม้จะผิด");

   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(30);
   if(InpResetHalt)
   {
      GlobalVariableDel(gPfx + "halted");
      GVSet("peak", AccountInfoDouble(ACCOUNT_EQUITY));
   }
   gHalted = GVGet("halted", 0) > 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//+------------------------------------------------------------------+
void OnTick()
{
   datetime now = TimeCurrent();
   gOffSec = (long)ServerOffsetHours(now) * 3600;
   datetime utc = (datetime)((long)now - gOffSec);
   long day = (long)utc / 86400;
   int  mn  = (int)(((long)utc % 86400) / 60);
   int  eu  = IsEUDST(utc) ? 60 : 0, us = IsUSDST(utc) ? 60 : 0;
   gLonS = 420 - eu;  gLonE = gLonS + 210;
   gNyS  = 750 - us;  gNyE  = 960 - us;  gOrbS = 810 - us;
   gPmS  = 960 - us;  gPmE  = gPmS + 240;
   MqlDateTime du; TimeToStruct(utc, du);
   gFlat = (du.day_of_week == 5) ? gPmE : gPmE + 30;

   //--- วันใหม่ (UTC)
   if(day != gDayKey)
   {
      gDayKey = day;
      gLonLong = false; gLonShort = false; gOrbDone = false; gHandoff = false; gPmMode = 9; gDayStop = false;
      if((long)GVGet("day", -1) != day) { GVSet("day", (double)day); GVSet("dayeq", AccountInfoDouble(ACCOUNT_EQUITY)); }
      gDayStartEq = GVGet("dayeq", AccountInfoDouble(ACCOUNT_EQUITY));
   }

   UpdateGuards();
   if(gHalted) { Comment("XAU MultiSession: หยุดเพราะ DD ถึงเพดาน"); return; }

   //--- ปิดตามเวลา
   if(mn >= 390) ClosePositions(MOD_ASIA, false);
   if(mn >= gPmS && !gHandoff) { ClosePositions(MOD_LONDON, true); ClosePositions(MOD_NY, true); gHandoff = true; }
   if(mn >= gFlat) ClosePositions(-1, false);

   ManagePositions();

   //--- สัญญาณใหม่เฉพาะเมื่อแท่ง M5 ปิด
   datetime bar = iTime(_Symbol, PERIOD_M5, 0);
   if(bar == gLastBar) return;
   gLastBar = bar;
   if(gDayStop || mn >= gFlat || du.day_of_week == 0 || du.day_of_week == 6) return;
   if(!LoadDay()) return;

   string sess = "OFF";
   if(mn >= 30 && mn < 360)            { sess = "ASIA";   if(InpUseAsia)   ModuleAsia(); }
   else if(mn >= gLonS && mn < gLonE)  { sess = "LONDON"; if(InpUseLondon) ModuleLondon(); }
   else if(mn >= gNyS && mn < gNyE)    { sess = "NY";     if(InpUseNY)     ModuleNY(mn); }
   else if(mn >= gPmS && mn < gPmE)    { sess = "NY-PM";  if(InpUsePM)     ModulePM(); }

   double eq = AccountInfoDouble(ACCOUNT_EQUITY), peak = GVGet("peak", eq);
   Comment(StringFormat("XAU MultiSession v1.00\nUTC %s | เซสชัน: %s\nATR(M5) %.2f | ADR %.2f | ADX(M15) %.1f\n"
                        "กรอบเอเชีย %.2f (%.0f%% ADR) | VWAP %.2f\nDD %.1f%% | ตัวคูณ risk %.2f | risk ที่เปิด %.2f%%\n%s",
                        TimeToString(utc, TIME_DATE | TIME_MINUTES), sess, gATR, gADR, gADX,
                        gHasAsia ? gAsiaHi - gAsiaLo : 0.0, gHasAsia ? 100.0 * (gAsiaHi - gAsiaLo) / gADR : 0.0, gVWAP,
                        peak > 0 ? (peak - eq) / peak * 100.0 : 0.0, gScale, OpenRiskPct(), gStatus));
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpWriteLog || trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   long mg = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(!IsOurMagic(mg) || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   LogLine(StringFormat("%s,CLOSE,%d,,%.2f,,%s,,,,%.2f,",
           TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), (int)(mg - InpMagicBase),
           HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
           DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits), net));
}
//+------------------------------------------------------------------+
