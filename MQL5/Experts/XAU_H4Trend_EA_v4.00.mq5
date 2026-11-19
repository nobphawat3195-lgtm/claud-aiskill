//+------------------------------------------------------------------+
//|  XAU_H4Trend_EA v4.00 — ทองคำ H4 pullback ตามเทรนด์ D1              |
//|  สำหรับบัญชี Standard ทุน $300 (0.01 lot ขั้นต่ำ)                    |
//|                                                                  |
//|  Logic: แท่ง H4 ปิดแล้ว Low แตะ EMA20(H4) แต่ปิดเหนือ EMA20 เป็นแท่งเขียว |
//|  และเทรนด์ D1 ขึ้น (Close วันล่าสุดที่จบ > EMA50 รายวัน, ตัดวัน 22:00 UTC)|
//|  → Buy (Sell กลับด้าน) SL $12 คงที่, TP 2R ($24), ถือได้ไม่เกิน 48 แท่ง  |
//|  ปิดทุกไม้ศุกร์ 20:00 UTC (ไม่ถือข้ามสุดสัปดาห์) ถือทีละ 1 ไม้          |
//|                                                                  |
//|  ผลวิจัย 1 ปีล่าสุด (พ.ย. 2025 – พ.ย. 2026, Dukascopy M1 bid/ask):     |
//|   152 ไม้ (~0.6/วัน), win 39%, เฉลี่ย +0.16R/ไม้                      |
//|   8 เดือนแรก +20.8R / 4 เดือนหลัง +3.4R (ช่วงหลังอ่อนลง)               |
//|   $300 Standard risk 3%: เส้นทางจริง $590 DD 41%                      |
//|   สุ่ม 2000 รอบ: ค่ากลาง $557, โอกาสขาดทุน 28%, โอกาสชนจุดหยุด 45% = 29% |
//|  คัดมาจาก 162 แบบ → มี selection bias ผลจริงมักแย่กว่า backtest         |
//|                                                                  |
//|  แท่ง H4 ของงานวิจัยเริ่มที่ 00:00 UTC — ตรงกับ Exness (GMT+0)          |
//|  ถ้าเซิร์ฟเวอร์ไม่ใช่ GMT+0 แท่ง H4 จะเลื่อน ผลอาจต่างจากงานวิจัย         |
//+------------------------------------------------------------------+
#property copyright "XAU H4Trend EA"
#property version   "4.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

input group "=== เวลา ==="
input int           InpServerGMTWinter = 0;        // GMT offset เซิร์ฟเวอร์ฤดูหนาว (Exness = 0)
input ENUM_DST_MODE InpServerDST       = DST_NONE; // กฎ DST เซิร์ฟเวอร์ (Exness = DST_NONE)

input group "=== สัญญาณ ==="
input int    InpEMAFast    = 20;     // EMA บน H4 สำหรับ pullback
input int    InpTrendEMA   = 50;     // EMA รายวันสำหรับทิศเทรนด์
input int    InpADRPeriod  = 14;     // ใช้ในตัวสร้างแท่งรายวัน (ไม่ใช้ในสัญญาณ)
input double InpSLUSD      = 12.0;   // SL เป็น $ ของราคาทอง (0.01 lot = $1 ต่อ $1)
input double InpTPR        = 2.0;    // TP เป็นเท่าของ SL
input int    InpMaxHoldBars = 48;    // ถือสูงสุดกี่แท่ง H4
input int    InpFridayCloseUTC = 20; // ปิดทุกไม้วันศุกร์ ชั่วโมงนี้ (UTC)

input group "=== ความเสี่ยง ==="
input double InpRiskPct    = 3.0;    // Risk ต่อไม้ (% equity) — ทุนน้อยจะใช้ lot ขั้นต่ำแทน
input bool   InpForceMinLot = true;  // true = ถ้าคำนวณได้ต่ำกว่า lot ขั้นต่ำ ให้ใช้ lot ขั้นต่ำ (risk จริงสูงกว่าที่ตั้ง)
input double InpDDHalf     = 25.0;   // DD จาก peak (%) ลด risk เหลือครึ่ง
input double InpDDQuarter  = 40.0;   // DD จาก peak (%) ลด risk เหลือหนึ่งในสี่
input double InpDDHalt     = 45.0;   // DD จาก peak (%) หยุด EA
input bool   InpResetHalt  = false;  // true = ล้างสถานะหยุดตอนเริ่ม
input double InpMaxLot     = 5.0;    // Lot สูงสุดต่อไม้
input double InpMaxSpreadUSD = 1.5;  // Spread สูงสุดตอนเข้า ($)

input group "=== ทั่วไป ==="
input long   InpMagic    = 884000;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_h4trend_trades.csv";

CTrade   trade;
int      hEMA;
string   gPfx;
bool     gHalted = false;
datetime gLastBar = 0;

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
   if(FileSize(f) == 0) FileWriteString(f, "time,event,dir,lots,req_price,fill_price,spread,sl,tp,risk_pct_real,net_profit\r\n");
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
   gPfx = "XH4_" + IntegerToString(InpMagic) + "_" + _Symbol + "_";
   hEMA = iMA(_Symbol, PERIOD_H4, InpEMAFast, 0, MODE_EMA, PRICE_CLOSE);
   if(hEMA == INVALID_HANDLE) { Print("สร้าง EMA H4 ไม่สำเร็จ"); return INIT_FAILED; }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(50);
   if(InpResetHalt) { GlobalVariableDel(gPfx + "halted"); GVSet("peak", AccountInfoDouble(ACCOUNT_EQUITY)); }
   gHalted = GVGet("halted", 0) > 0;
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

void OnTick()
{
   datetime now = TimeCurrent();
   datetime utc = (datetime)((long)now - ServerOffsetSec(now));
   MqlDateTime du; TimeToStruct(utc, du);

   //--- DD guard
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet("peak", eq);
   if(eq > peak || !GlobalVariableCheck(gPfx + "peak")) { peak = MathMax(eq, peak); GVSet("peak", peak); }
   double dd = peak > 0 ? (peak - eq) / peak * 100.0 : 0;
   ulong tk = OpenTicket();
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GVSet("halted", 1);
      if(tk > 0) trade.PositionClose(tk);
      Print("XAU H4Trend: DD ถึงเพดาน หยุด EA — ตั้ง InpResetHalt=true เพื่อเริ่มใหม่");
   }

   //--- time exits: Friday close, max hold
   bool friday = (du.day_of_week == 5 && du.hour >= InpFridayCloseUTC) || du.day_of_week == 6 || du.day_of_week == 0;
   if(tk > 0 && PositionSelectByTicket(tk))
   {
      long held = (long)now - (long)PositionGetInteger(POSITION_TIME);
      if(friday || held >= (long)InpMaxHoldBars * 4 * 3600) trade.PositionClose(tk);
   }

   string status = gHalted ? "หยุดเพราะ DD ถึงเพดาน" : (OpenTicket() > 0 ? "ถือไม้อยู่" : "รอสัญญาณ H4");

   //--- new H4 bar → evaluate the bar that just closed
   datetime bar = iTime(_Symbol, PERIOD_H4, 0);
   if(bar != gLastBar && !gHalted)
   {
      gLastBar = bar;
      // research skipped signals from bars closing Friday 19:00 UTC or later
      bool lateFriday = du.day_of_week == 5 && du.hour >= InpFridayCloseUTC - 1;
      if(OpenTicket() == 0 && !friday && !lateFriday)
      {
         double ema[1];
         double o = iOpen(_Symbol, PERIOD_H4, 1), c = iClose(_Symbol, PERIOD_H4, 1), l = iLow(_Symbol, PERIOD_H4, 1), h = iHigh(_Symbol, PERIOD_H4, 1);
         int dirD1 = 0; double adr = 0;
         if(CopyBuffer(hEMA, 0, 1, 1, ema) == 1 && CalcDaily(((long)utc + 2 * 3600) / 86400, dirD1, adr))
         {
            int dir = 0;
            if(dirD1 > 0 && l <= ema[0] && c > ema[0] && c > o) dir = 1;
            if(dirD1 < 0 && h >= ema[0] && c < ema[0] && c < o) dir = -1;
            if(dir != 0)
            {
               double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
               double entry = dir > 0 ? ask : bid, spread = ask - bid;
               double sl = NormalizeDouble(entry - dir * InpSLUSD, _Digits);
               double tp = NormalizeDouble(entry + dir * InpSLUSD * InpTPR, _Digits);
               double fr = InpRiskPct * (dd >= InpDDQuarter ? 0.25 : (dd >= InpDDHalf ? 0.5 : 1.0));
               double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
               double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
               double lossPerLot = (tv > 0 && ts > 0) ? InpSLUSD / ts * tv : 0;
               double lots = lossPerLot > 0 ? MathFloor(eq * fr / 100.0 / lossPerLot / step) * step : 0;
               if(lots < vmin && InpForceMinLot) lots = vmin;
               lots = MathMin(lots, MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
               if(spread > InpMaxSpreadUSD) status = "ข้ามสัญญาณ: spread กว้างเกิน";
               else if(lots < vmin) status = "ข้ามสัญญาณ: lot ต่ำกว่าขั้นต่ำ";
               else
               {
                  lots = NormalizeDouble(lots, 2);
                  bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, tp, "XH4") : trade.Sell(lots, _Symbol, 0, sl, tp, "XH4");
                  if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
                  {
                     status = "เปิดไม้แล้ว";
                     LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%s,%.2f,", TimeToString(now, TIME_DATE | TIME_SECONDS), dir, lots,
                             DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
                             DoubleToString(sl, _Digits), DoubleToString(tp, _Digits), lots * lossPerLot / eq * 100.0));
                  }
                  else status = "order ล้มเหลว " + IntegerToString((int)trade.ResultRetcode());
               }
            }
         }
      }
   }

   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minRisk = (tv > 0 && ts > 0 && eq > 0) ? vmin * InpSLUSD / ts * tv / eq * 100.0 : 0;
   Comment(StringFormat("XAU H4Trend v4.00\nUTC %s\nDD %.1f%% | Risk ตั้ง %.1f%% | risk ขั้นต่ำจริงที่ lot %.2f = %.1f%%\n%s",
           TimeToString(utc, TIME_DATE | TIME_MINUTES), dd, InpRiskPct, vmin, minRisk, status));
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
