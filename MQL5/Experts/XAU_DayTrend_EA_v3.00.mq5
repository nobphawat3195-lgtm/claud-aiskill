//+------------------------------------------------------------------+
//|  XAU_DayTrend_EA v3.00 — ทองคำ ตามเทรนด์ D1 วันละ 1 ไม้              |
//|                                                                  |
//|  Logic (ผ่านการทดสอบ 3 ปี พ.ย. 2023 – พ.ย. 2026, Dukascopy M1 bid/ask):|
//|   - 01:00 UTC: เปิด 1 ไม้ตามทิศ D1 (Close D1 เมื่อวาน เทียบ EMA50 D1) |
//|   - SL = 0.3 × ADR(14) จากราคาเข้า, ไม่มี TP                         |
//|   - ปิดที่ 20:30 UTC (19:30 UTC ช่วง DST สหรัฐ) ถ้ายังไม่โดน SL        |
//|  ผลวิจัย: +18.8R / +18.8R / +18.3R ต่อปี, เฉลี่ย +0.073R ต่อไม้        |
//|  edge เล็ก (t-stat 1.25 ทั้ง 3 ปี) — risk ที่โตเร็วสุดคือ 1–2% ต่อไม้    |
//|  เกิน 2% ค่ากลางผลตอบแทนลดลงและโอกาสชนจุดหยุด 45% สูงขึ้นมาก          |
//|                                                                  |
//|  ใช้กับบัญชี Cent เมื่อทุน $300: lot ละเอียดพอให้ risk % ตรงตามตั้ง     |
//|  แทน v1.00/v2 — โมดูลแยกเซสชันเดิมไม่ผ่านการทดสอบ 3 ปี               |
//+------------------------------------------------------------------+
#property copyright "XAU DayTrend EA"
#property version   "3.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

input group "=== เวลา ==="
input int           InpServerGMTWinter = 0;       // GMT offset ของเซิร์ฟเวอร์ช่วงฤดูหนาว (Exness = 0)
input ENUM_DST_MODE InpServerDST       = DST_NONE; // กฎ DST ของเซิร์ฟเวอร์ (Exness = DST_NONE)
input int           InpEntryMinuteUTC  = 60;      // นาทีของวัน (UTC) ที่เข้าไม้ (60 = 01:00) ช่วงที่ผ่านทดสอบ: 30–90
input int           InpExitMinuteUTC   = 1230;    // นาทีของวัน (UTC ฤดูหนาว) ที่ปิดไม้ (1230 = 20:30) เลื่อนตาม DST สหรัฐ
input int           InpEntryWindowMin  = 30;      // ถ้าพลาดเวลาเข้า (เช่น VPS รีสตาร์ท) ยังเข้าได้ภายในกี่นาที

input group "=== สัญญาณ ==="
input int    InpTrendEMA   = 50;    // EMA ของ D1 สำหรับทิศเทรนด์
input int    InpADRPeriod  = 14;    // จำนวนวันเฉลี่ย ADR
input double InpSLADR      = 0.3;   // SL เป็นเท่าของ ADR

input group "=== ความเสี่ยง ==="
input double InpRiskPct      = 1.5;   // Risk ต่อไม้ (% equity) — แนะนำ 1.0–2.0
input double InpDDHalf       = 25.0;  // DD จาก peak (%) ลด risk เหลือครึ่ง
input double InpDDQuarter    = 40.0;  // DD จาก peak (%) ลด risk เหลือหนึ่งในสี่
input double InpDDHalt       = 45.0;  // DD จาก peak (%) หยุด EA
input bool   InpResetHalt    = false; // true = ล้างสถานะหยุดและตั้ง peak ใหม่ตอนเริ่ม
input double InpMaxLot       = 50.0;  // Lot สูงสุดต่อไม้ (บัญชี Cent มีเพดานของโบรกเกอร์ด้วย)
input double InpMaxSpreadPct = 5.0;   // Spread สูงสุดตอนเข้า (% ของระยะ SL)

input group "=== ทั่วไป ==="
input long   InpMagic   = 883000;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_daytrend_trades.csv";

CTrade trade;
string gPfx;
bool   gHalted = false;
long   gTradedDay = -1;

//--- DST helpers
datetime NthSunday(int year, int mon, int n)
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
bool IsUSDST(datetime t) { MqlDateTime d; TimeToStruct(t, d); return t >= NthSunday(d.year, 3, 2) && t < NthSunday(d.year, 11, 1); }
bool IsEUDST(datetime t) { MqlDateTime d; TimeToStruct(t, d); return t >= NthSunday(d.year, 3, 0) && t < NthSunday(d.year, 10, 0); }
long ServerOffsetSec(datetime t)
{
   int off = InpServerGMTWinter;
   if(InpServerDST == DST_US && IsUSDST(t)) off++;
   if(InpServerDST == DST_EU && IsEUDST(t)) off++;
   return (long)off * 3600;
}

double GVGet(string k, double def) { return GlobalVariableCheck(gPfx + k) ? GlobalVariableGet(gPfx + k) : def; }
void   GVSet(string k, double v)   { GlobalVariableSet(gPfx + k, v); }

void LogLine(string s)
{
   if(!InpWriteLog) return;
   int f = FileOpen(InpLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) return;
   if(FileSize(f) == 0) FileWriteString(f, "time,event,dir,lots,req_price,fill_price,spread,sl,adr,risk_pct,net_profit\r\n");
   FileSeek(f, 0, SEEK_END);
   FileWriteString(f, s + "\r\n");
   FileClose(f);
}

ulong OpenTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) return t;
   }
   return 0;
}

//--- วันเทรดตัดที่ 22:00 UTC (ปิดตลาดนิวยอร์ก) สร้างจาก H1 เอง ไม่ขึ้นกับเวลาเซิร์ฟเวอร์ (ตรงกับงานวิจัย)
//    คืนทิศเทรนด์ (close วันล่าสุดที่จบแล้ว เทียบ EMA) และ ADR ของวันที่จบแล้ว
bool CalcDaily(long curKey, int &dir, double &adr)
{
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_H1, 0, 24 * 400, r);
   if(n < 24 * (InpTrendEMA + InpADRPeriod)) return false;
   double cl[], hi[], lo[]; int nd = 0; long key = -1;
   ArrayResize(cl, 0); ArrayResize(hi, 0); ArrayResize(lo, 0);
   for(int i = 0; i < n; i++)
   {
      long utc = (long)r[i].time - ServerOffsetSec(r[i].time);
      long k = (utc + 2 * 3600) / 86400;
      if(k >= curKey) break;                       // วันปัจจุบันยังไม่จบ
      if(k != key)
      {
         key = k; nd++;
         ArrayResize(cl, nd); ArrayResize(hi, nd); ArrayResize(lo, nd);
         hi[nd - 1] = r[i].high; lo[nd - 1] = r[i].low;
      }
      hi[nd - 1] = MathMax(hi[nd - 1], r[i].high);
      lo[nd - 1] = MathMin(lo[nd - 1], r[i].low);
      cl[nd - 1] = r[i].close;
   }
   if(nd < InpTrendEMA + InpADRPeriod) return false;
   double a = 2.0 / (InpTrendEMA + 1.0), ema = cl[0];
   for(int i = 1; i < nd; i++) ema = a * cl[i] + (1 - a) * ema;
   dir = cl[nd - 1] > ema ? 1 : (cl[nd - 1] < ema ? -1 : 0);
   adr = 0;
   for(int i = nd - InpADRPeriod; i < nd; i++) adr += hi[i] - lo[i];
   adr /= InpADRPeriod;
   return true;
}

int OnInit()
{
   gPfx = "XDT_" + IntegerToString(InpMagic) + "_" + _Symbol + "_";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(50);
   if(InpResetHalt) { GlobalVariableDel(gPfx + "halted"); GVSet("peak", AccountInfoDouble(ACCOUNT_EQUITY)); }
   gHalted = GVGet("halted", 0) > 0;
   gTradedDay = (long)GVGet("day", -1);
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

void OnTick()
{
   datetime now = TimeCurrent();
   long off = ServerOffsetSec(now);
   datetime utc = (datetime)((long)now - off);
   long day = (long)utc / 86400;
   int  mn  = (int)(((long)utc % 86400) / 60);
   MqlDateTime du; TimeToStruct(utc, du);
   int exitMn = InpExitMinuteUTC - (IsUSDST(utc) ? 60 : 0);

   //--- DD guard
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet("peak", eq);
   if(eq > peak || !GlobalVariableCheck(gPfx + "peak")) { peak = MathMax(eq, peak); GVSet("peak", peak); }
   double dd = peak > 0 ? (peak - eq) / peak * 100.0 : 0;
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GVSet("halted", 1);
      ulong tk = OpenTicket(); if(tk > 0) trade.PositionClose(tk);
      Print("XAU DayTrend: DD ถึงเพดาน หยุด EA — ตั้ง InpResetHalt=true เพื่อเริ่มใหม่");
   }

   //--- time exit
   ulong tk = OpenTicket();
   if(tk > 0 && mn >= exitMn) trade.PositionClose(tk);

   string status = "รอเวลาเข้า";
   if(gHalted) status = "หยุดเพราะ DD ถึงเพดาน";
   else if(tk == 0 && gTradedDay != day && du.day_of_week >= 1 && du.day_of_week <= 5 &&
           mn >= InpEntryMinuteUTC && mn < InpEntryMinuteUTC + InpEntryWindowMin && mn < exitMn)
   {
      int dir = 0; double adr = 0;
      if(CalcDaily(((long)utc + 2 * 3600) / 86400, dir, adr))
      {
         if(dir != 0)
         {
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double entry = dir > 0 ? ask : bid;
            double slDist = InpSLADR * adr;
            double sl = NormalizeDouble(entry - dir * slDist, _Digits);
            double spread = ask - bid;
            double fr = InpRiskPct * (dd >= InpDDQuarter ? 0.25 : (dd >= InpDDHalf ? 0.5 : 1.0));
            double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
            double lots = (tv > 0 && ts > 0) ? eq * fr / 100.0 / (slDist / ts * tv) : 0;
            lots = MathFloor(lots / step) * step;
            lots = MathMin(lots, MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
            if(spread > slDist * InpMaxSpreadPct / 100.0) status = "ข้ามวันนี้: spread กว้างเกิน";
            else if(lots < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN)) status = "ข้ามวันนี้: lot ต่ำกว่าขั้นต่ำ (ใช้บัญชี Cent)";
            else
            {
               lots = NormalizeDouble(lots, 2);
               bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "XDT") : trade.Sell(lots, _Symbol, 0, sl, 0, "XDT");
               if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
               {
                  gTradedDay = day; GVSet("day", (double)day);
                  status = "เปิดไม้แล้ว";
                  LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%s,%.2f,",
                          TimeToString(now, TIME_DATE | TIME_SECONDS), dir, lots, DoubleToString(entry, _Digits),
                          DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
                          DoubleToString(sl, _Digits), DoubleToString(adr, 2), fr));
               }
               else status = "order ล้มเหลว " + IntegerToString((int)trade.ResultRetcode());
            }
            if(status != "เปิดไม้แล้ว" && StringFind(status, "order") < 0) { gTradedDay = day; GVSet("day", (double)day); }
         }
      }
   }
   else if(tk > 0) status = "ถือไม้อยู่ ปิดเวลา " + StringFormat("%02d:%02d UTC", exitMn / 60, exitMn % 60);
   else if(gTradedDay == day) status = "วันนี้เทรดแล้ว";

   Comment(StringFormat("XAU DayTrend v3.00\nUTC %s\nDD %.1f%% | Risk %.2f%%\n%s",
           TimeToString(utc, TIME_DATE | TIME_MINUTES), dd,
           InpRiskPct * (dd >= InpDDQuarter ? 0.25 : (dd >= InpDDHalf ? 0.5 : 1.0)), status));
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpWriteLog || trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic || HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol) return;
   if(HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   LogLine(StringFormat("%s,CLOSE,,%.2f,,%s,,,,,%.2f", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
           HistoryDealGetDouble(trans.deal, DEAL_VOLUME), DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits), net));
}
//+------------------------------------------------------------------+
