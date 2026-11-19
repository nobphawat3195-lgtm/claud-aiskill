//+------------------------------------------------------------------+
//|  XAU_ORB_EA v6.00 — Asia Opening-Range Breakout + D1 trend         |
//|  สำหรับบัญชี Standard ทุน $300, server GMT+0 (Exness), ถือไม้ถึง 12:00 UTC |
//|                                                                  |
//|  Logic:                                                          |
//|   1) กรอบ = High/Low ของ 00:00-01:00 UTC (แท่ง M5 bid), กว้าง 3-16 USD   |
//|   2) 01:05-06:00 UTC: แท่ง M5 แรกที่ปิดนอกกรอบ = สัญญาณ (1 ไม้/วัน)        |
//|   3) เข้าเฉพาะทิศเดียวกับเทรนด์ D1: ปิดเมื่อวาน > EMA20(D1) ซื้อ, ต่ำกว่า ขาย |
//|   4) SL = ขอบตรงข้ามของกรอบ ไม่มี TP ปิดที่ 12:00 UTC (InpExitHourUTC)    |
//|  Backtest real tick Dukascopy พ.ย.25-พ.ย.26 (config C1 pre-registered):    |
//|   71 ไม้ ชนะ 48% เฉลี่ย +0.67R รวม +47.6R (พ.ย.-มิ.ย. +39.3R, ก.ค.-พ.ย. +8.3R)|
//|   ชนะ random-direction 99% | $300 Standard risk 2% -> ~$968, DD 13%       |
//|   ออก 20:00 UTC (C4): +53.0R, $1,031 แต่ DD 30% | ไม่กรองเทรนด์ (C3): +45.1R |
//|  ข้อควรระวัง: ~6 ไม้/เดือน (ไม่ใช่ตัวที่ออกไม้บ่อย) ทดสอบปีเดียว ปรับค่าครั้งเดียว|
//|  ต้อง demo 4-8 สัปดาห์ก่อนใช้เงินจริง                                      |
//+------------------------------------------------------------------+
#property copyright "XAU ORB EA"
#property version   "6.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

input group "=== เวลา ==="
input int           InpServerGMTWinter = 0;        // GMT offset เซิร์ฟเวอร์ฤดูหนาว (Exness = 0)
input ENUM_DST_MODE InpServerDST       = DST_NONE; // กฎ DST เซิร์ฟเวอร์ (Exness = DST_NONE)
input int           InpLastSignalHour  = 6;        // รับสัญญาณถึงกี่โมง UTC
input int           InpExitHourUTC     = 12;       // ปิดไม้กี่โมง UTC (12 = C1, 20 = C4)

input group "=== สัญญาณ ==="
input double InpMinRange  = 3.0;   // กรอบ 00-01 UTC แคบสุด (USD)
input double InpMaxRange  = 16.0;  // กรอบกว้างสุด (USD) = SL สูงสุด
input bool   InpUseTrend  = true;  // กรองทิศตามเทรนด์ D1 (close เมื่อวาน เทียบ EMA)
input int    InpTrendEMA  = 20;    // period EMA ของ D1

input group "=== ความเสี่ยง ==="
input double InpRiskPct     = 2.0;   // Risk ต่อไม้ (% equity)
input double InpMinLotCap   = 5.5;   // ถ้าต้องใช้ lot ขั้นต่ำ: เข้าเฉพาะเมื่อ risk จริง ≤ ค่านี้ (%) ไม่งั้นข้าม
input double InpDDHalf      = 30.0;  // DD จาก peak (%) ลด risk เหลือครึ่ง
input double InpDDHalt      = 45.0;  // DD จาก peak (%) หยุด EA
input bool   InpResetHalt   = false; // true = ล้างสถานะหยุดตอนเริ่ม
input double InpMaxLot      = 5.0;
input double InpMaxSpreadUSD = 1.5;  // Spread สูงสุดตอนเข้า ($)

input group "=== ทั่วไป ==="
input long   InpMagic    = 886000;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_orb_trades.csv";

CTrade trade;
string gPfx;
bool   gHalted = false;
long   gTradedDay = -1;
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
   if(FileSize(f) == 0) FileWriteString(f, "time,event,dir,lots,req_price,fill_price,spread,sl,range,risk_pct_real,net_profit\r\n");
   FileSeek(f, 0, SEEK_END);
   FileWriteString(f, s + "\r\n");
   FileClose(f);
}

ulong OpenTicketM(long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) return t;
   }
   return 0;
}

//--- วันเทรดตัดที่ 22:00 UTC (ปิดตลาดนิวยอร์ก) สร้างจาก H1 เอง ไม่ขึ้นกับเวลาเซิร์ฟเวอร์ (ตรงกับงานวิจัย)
//    คืนทิศเทรนด์ (close วันล่าสุดที่จบแล้ว เทียบ EMA) และ ADR ของวันที่จบแล้ว

ulong OpenTicket() { return OpenTicketM(InpMagic); }
int OnInit()
{
   gPfx = "XORB_" + IntegerToString(InpMagic) + "_" + _Symbol + "_";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(50);
   if(InpResetHalt) { GlobalVariableDel(gPfx + "halted"); GVSet("peak", AccountInfoDouble(ACCOUNT_EQUITY)); }
   gHalted = GVGet("halted", 0) > 0;
   gTradedDay = (long)GVGet("day", -1);
   if(InpServerGMTWinter != 0 || InpServerDST != DST_NONE)
      Print("คำเตือน: งานวิจัยใช้วัน UTC; ตั้ง InpServerGMTWinter/DST ให้ตรงเซิร์ฟเวอร์");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

//--- ประเมินสัญญาณที่แท่ง M5 ที่ปิดล่าสุด (shift 1)
string TryEntry(datetime utc, long day, double eq, double fr)
{
   MqlDateTime du; TimeToStruct(utc, du);
   if(gHalted || OpenTicket() != 0 || gTradedDay == day || du.day_of_week < 1 || du.day_of_week > 5) return "";
   long srvOff = ServerOffsetSec(TimeCurrent());
   datetime barSrv = iTime(_Symbol, PERIOD_M5, 1);
   long barUtc = (long)barSrv - srvOff;                              // เวลาเปิดแท่งที่ปิดแล้ว (UTC)
   long sod = barUtc % 86400;
   if(barUtc / 86400 != day || sod < 3600 || sod >= (long)InpLastSignalHour * 3600) return "";
   //--- กรอบ 00:00-01:00 UTC (12 แท่ง M5)
   double hi = -1e9, lo = 1e9;
   datetime t0 = (datetime)(day * 86400 + srvOff);
   MqlRates r[];
   if(CopyRates(_Symbol, PERIOD_M5, t0, t0 + 3600 - 1, r) < 10) return "";
   for(int i = 0; i < ArraySize(r); i++) { hi = MathMax(hi, r[i].high); lo = MathMin(lo, r[i].low); }
   double W = hi - lo;
   if(W < InpMinRange || W > InpMaxRange) return "";
   double c1 = iClose(_Symbol, PERIOD_M5, 1);
   int dir = c1 > hi ? 1 : (c1 < lo ? -1 : 0);
   if(dir == 0) return "";
   if(InpUseTrend)
   {
      int h = iMA(_Symbol, PERIOD_D1, InpTrendEMA, 0, MODE_EMA, PRICE_CLOSE);
      double e[]; if(h == INVALID_HANDLE || CopyBuffer(h, 0, 1, 1, e) != 1) { IndicatorRelease(h); return "รอข้อมูล D1"; }
      IndicatorRelease(h);
      int tr = iClose(_Symbol, PERIOD_D1, 1) > e[0] ? 1 : -1;
      if(tr != dir) return "ข้าม: ผิดทิศเทรนด์ D1 (รอสัญญาณทิศตรงเทรนด์ต่อ)";
   }
   gTradedDay = day; GVSet("day", (double)day);                  // ไม้แรกที่ผ่านตัวกรองเท่านั้น (1 ไม้/วัน)
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double entry = dir > 0 ? ask : bid, spread = ask - bid;
   double sl = NormalizeDouble(dir > 0 ? lo : hi, _Digits);
   double slDist = (entry - sl) * dir;
   if(slDist <= 0) return "ข้าม: ราคาเลย SL";
   if(spread > InpMaxSpreadUSD) return "ข้าม: spread กว้าง";
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double perLot = (tv > 0 && ts > 0) ? slDist / ts * tv : 0;
   double lots = perLot > 0 ? MathFloor(eq * fr / 100.0 / perLot / step) * step : 0;
   if(lots < vmin && perLot > 0 && vmin * perLot / eq * 100.0 <= InpMinLotCap) lots = vmin;
   lots = MathMin(lots, MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
   if(lots < vmin) return StringFormat("ข้าม: 0.01 lot เสี่ยง %.1f%% เกิน %.1f%%", vmin * perLot / eq * 100.0, InpMinLotCap);
   lots = NormalizeDouble(lots, 2);
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "ORB") : trade.Sell(lots, _Symbol, 0, sl, 0, "ORB");
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%.2f,%.2f,", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), dir, lots,
              DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
              DoubleToString(sl, _Digits), W, lots * perLot / eq * 100.0));
      return "เปิดไม้แล้ว";
   }
   gTradedDay = -1; GVSet("day", -1);
   return "order ล้มเหลว " + IntegerToString((int)trade.ResultRetcode());
}

void OnTick()
{
   datetime now = TimeCurrent();
   datetime utc = (datetime)((long)now - ServerOffsetSec(now));
   long day = (long)utc / 86400;
   int  mn  = (int)(((long)utc % 86400) / 60);
   MqlDateTime du; TimeToStruct(utc, du);

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet("peak", eq);
   if(eq > peak || !GlobalVariableCheck(gPfx + "peak")) { peak = MathMax(eq, peak); GVSet("peak", peak); }
   double dd = peak > 0 ? (peak - eq) / peak * 100.0 : 0;
   ulong tk = OpenTicket();
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GVSet("halted", 1);
      if(tk > 0) trade.PositionClose(tk);
      Print("XAU ORB: DD ถึงเพดาน หยุด EA — ตั้ง InpResetHalt=true เพื่อเริ่มใหม่");
   }
   if(tk > 0 && (mn >= InpExitHourUTC * 60 || du.day_of_week == 6 || du.day_of_week == 0)) trade.PositionClose(tk);

   double fr = InpRiskPct * (dd >= InpDDHalf ? 0.5 : 1.0);
   string status = gHalted ? "หยุดเพราะ DD ถึงเพดาน" : (OpenTicket() > 0 ? StringFormat("ถือไม้ ปิด %02d:00 UTC", InpExitHourUTC) : "รอสัญญาณ 01:05-06:00 UTC");
   datetime bar = iTime(_Symbol, PERIOD_M5, 0);
   if(bar != gLastBar)                                              // ประเมินครั้งเดียวต่อแท่ง M5 ใหม่
   {
      gLastBar = bar;
      string s = TryEntry(utc, day, eq, fr);
      if(s != "") status = s;
   }
   Comment(StringFormat("XAU ORB v6.00\nUTC %s\nDD %.1f%% | Risk %.2f%%\n%s", TimeToString(utc, TIME_DATE | TIME_MINUTES), dd, fr, status));
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
