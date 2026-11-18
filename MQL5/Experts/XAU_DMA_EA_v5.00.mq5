//+------------------------------------------------------------------+
//|  XAU_DMA_EA v5.00 — Day Momentum 01:00 UTC (โมดูล DM_A จาก v4.10)  |
//|  สำหรับบัญชี Standard ทุน $300                                       |
//|                                                                  |
//|  Logic (= DM_A ของ XAU Growth EA v4.10 ที่ทำกับ Grok Bot):            |
//|   01:00 UTC: ถ้า ADX(H1,14 Wilder) < 25                             |
//|   ทิศ = ราคาปิดแท่ง H1 00:00 เทียบราคาเปิดของวันเทรดก่อนหน้า           |
//|   SL = 1.0 × ATR(H1,14 Wilder) จากราคาปิดนั้น, ไม่มี TP               |
//|   ปิดที่ 20:30 UTC (ศุกร์ 20:00) ช่วง DST สหรัฐเร็วขึ้น 1 ชม.          |
//|                                                                  |
//|  ทดสอบซ้ำนอกช่วงที่ Grok ใช้ปรับค่า (Dukascopy M1 bid/ask):            |
//|   พ.ย.23–ต.ค.24 +35.9R (106) | พ.ย.24–ต.ค.25 +53.2R (117)            |
//|   พ.ย.25–พ.ค.26 +22.1R (71)  | ช่วงของ Grok พ.ค.–พ.ย.26 +27.7R (66)  |
//|   real tick เม.ย.–พ.ย. 2026: +38.9R เทียบ M1 +40.9R (72 ไม้)          |
//|  $300 Standard, risk 3%, ข้ามไม้ถ้า 0.01 lot เสี่ยงเกิน 5%:            |
//|   เริ่ม $300 แต่ละปี → $521 / $986 / $929, DD สูงสุด 29–37%            |
//|   สุ่ม 2000 รอบ: ค่ากลาง $639, ขาดทุน 25%, ชนจุดหยุด 45% = 26%         |
//|                                                                  |
//|  เวลาเซิร์ฟเวอร์ต้องเป็น GMT+0 (Exness) ให้วันเทรดตรงกับงานวิจัย        |
//+------------------------------------------------------------------+
#property copyright "XAU DMA EA"
#property version   "5.00"
#property strict

#include <Trade\Trade.mqh>

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

input group "=== เวลา ==="
input int           InpServerGMTWinter = 0;        // GMT offset เซิร์ฟเวอร์ฤดูหนาว (Exness = 0)
input ENUM_DST_MODE InpServerDST       = DST_NONE; // กฎ DST เซิร์ฟเวอร์ (Exness = DST_NONE)
input int           InpEntryMinuteUTC  = 60;       // เวลาเข้า (นาที UTC) 60 = 01:00
input int           InpEntryWindowMin  = 10;       // เข้าได้ภายในกี่นาทีหลังเวลาเข้า

input group "=== สัญญาณ ==="
input int    InpPeriod   = 14;    // ATR / ADX period (H1, Wilder)
input double InpADXMax   = 25.0;  // เข้าเฉพาะเมื่อ ADX(H1) ต่ำกว่านี้
input double InpSLATR    = 1.0;   // SL = k × ATR(H1)

input group "=== ความเสี่ยง ==="
input double InpRiskPct     = 3.0;   // Risk ต่อไม้ (% equity)
input double InpMinLotCap   = 5.0;   // ถ้าต้องใช้ lot ขั้นต่ำ: เข้าเฉพาะเมื่อ risk จริง ≤ ค่านี้ (%) ไม่งั้นข้าม
input double InpDDHalf      = 25.0;  // DD จาก peak (%) ลด risk เหลือครึ่ง
input double InpDDQuarter   = 40.0;  // DD จาก peak (%) ลด risk เหลือหนึ่งในสี่
input double InpDDHalt      = 45.0;  // DD จาก peak (%) หยุด EA
input bool   InpResetHalt   = false; // true = ล้างสถานะหยุดตอนเริ่ม
input double InpMaxLot      = 5.0;   // Lot สูงสุดต่อไม้
input double InpMaxSpreadUSD = 1.5;  // Spread สูงสุดตอนเข้า ($)

input group "=== ทั่วไป ==="
input long   InpMagic    = 885000;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_dma_trades.csv";

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
   if(FileSize(f) == 0) FileWriteString(f, "time,event,dir,lots,req_price,fill_price,spread,sl,adx,risk_pct_real,net_profit\r\n");
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

//--- Wilder ATR / ADX ของแท่ง H1 ที่ปิดแล้วล่าสุด (shift 1) — สูตรเดียวกับงานวิจัย
bool H1Wilder(double &atr, double &adxv, double &close1)
{
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_H1, 1, 600, r);           // r[n-1] = แท่งที่ปิดล่าสุด
   if(n < 200) return false;
   double al = 1.0 / InpPeriod, a = 0, p = 0, m = 0, x = 0;
   for(int i = 0; i < n; i++)
   {
      double tr = r[i].high - r[i].low, up = 0, dn = 0;
      if(i > 0)
      {
         double pc = r[i - 1].close;
         tr = MathMax(tr, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
         up = r[i].high - r[i - 1].high; dn = r[i - 1].low - r[i].low;
      }
      double pdm = (up > dn && up > 0) ? up : 0, mdm = (dn > up && dn > 0) ? dn : 0;
      if(i == 0) { a = tr; p = pdm; m = mdm; }
      else { a += al * (tr - a); p += al * (pdm - p); m += al * (mdm - m); }
      double pdi = a > 0 ? 100 * p / a : 0, mdi = a > 0 ? 100 * m / a : 0;
      double dx = 100 * MathAbs(pdi - mdi) / MathMax(pdi + mdi, 1e-9);
      if(i == 0) x = dx; else x += al * (dx - x);
   }
   atr = a; adxv = x; close1 = r[n - 1].close;
   return true;
}

//--- ราคาเปิดของวันเทรดก่อนหน้า (วันอาทิตย์รวมเข้ากับวันจันทร์) — วันตาม UTC (เซิร์ฟเวอร์ GMT+0)
double PrevTradingDayOpen()
{
   int found = -1; double op = 0;
   for(int sh = 0; sh < 15; sh++)
   {
      datetime t = iTime(_Symbol, PERIOD_D1, sh);
      if(t == 0) return 0;
      MqlDateTime s; TimeToStruct(t, s);
      if(s.day_of_week == 0) { if(found == 1) op = iOpen(_Symbol, PERIOD_D1, sh); continue; }
      if(found == 1) return op;
      found++;
      op = iOpen(_Symbol, PERIOD_D1, sh);
      if(found == 1 && s.day_of_week != 1) return op;
   }
   return (found == 1) ? op : 0;
}

int OnInit()
{
   gPfx = "XDMA_" + IntegerToString(InpMagic) + "_" + _Symbol + "_";
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(50);
   if(InpResetHalt) { GlobalVariableDel(gPfx + "halted"); GVSet("peak", AccountInfoDouble(ACCOUNT_EQUITY)); }
   gHalted = GVGet("halted", 0) > 0;
   gTradedDay = (long)GVGet("day", -1);
   if(InpServerGMTWinter != 0 || InpServerDST != DST_NONE)
      Print("คำเตือน: งานวิจัยใช้วันเทรดแบบ GMT+0 (Exness) — เซิร์ฟเวอร์อื่นราคาเปิดของวันจะต่าง ผลอาจไม่ตรง");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason) { Comment(""); }

void OnTick()
{
   datetime now = TimeCurrent();
   datetime utc = (datetime)((long)now - ServerOffsetSec(now));
   long day = (long)utc / 86400;
   int  mn  = (int)(((long)utc % 86400) / 60);
   MqlDateTime du; TimeToStruct(utc, du);
   int flatMn = (du.day_of_week == 5 ? 1200 : 1230) - (IsUSDST(utc) ? 60 : 0);

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double peak = GVGet("peak", eq);
   if(eq > peak || !GlobalVariableCheck(gPfx + "peak")) { peak = MathMax(eq, peak); GVSet("peak", peak); }
   double dd = peak > 0 ? (peak - eq) / peak * 100.0 : 0;
   ulong tk = OpenTicket();
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GVSet("halted", 1);
      if(tk > 0) trade.PositionClose(tk);
      Print("XAU DMA: DD ถึงเพดาน หยุด EA — ตั้ง InpResetHalt=true เพื่อเริ่มใหม่");
   }
   if(tk > 0 && (mn >= flatMn || du.day_of_week == 6 || du.day_of_week == 0)) trade.PositionClose(tk);

   string status = gHalted ? "หยุดเพราะ DD ถึงเพดาน" : (OpenTicket() > 0 ? "ถือไม้อยู่ ปิด " + StringFormat("%02d:%02d UTC", flatMn / 60, flatMn % 60) : "รอ 01:00 UTC");
   double fr = InpRiskPct * (dd >= InpDDQuarter ? 0.25 : (dd >= InpDDHalf ? 0.5 : 1.0));

   if(!gHalted && OpenTicket() == 0 && gTradedDay != day && du.day_of_week >= 1 && du.day_of_week <= 5 &&
      mn >= InpEntryMinuteUTC && mn < InpEntryMinuteUTC + InpEntryWindowMin)
   {
      double atr, adxv, c1, po = PrevTradingDayOpen();
      if(H1Wilder(atr, adxv, c1) && po > 0)
      {
         gTradedDay = day; GVSet("day", (double)day);
         if(adxv >= InpADXMax) status = StringFormat("วันนี้ข้าม: ADX %.1f ≥ %.0f (เทรนด์แรง)", adxv, InpADXMax);
         else if(c1 == po) status = "วันนี้ข้าม: ราคาเท่าราคาเปิดวันก่อน";
         else
         {
            int dir = c1 > po ? 1 : -1;
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double entry = dir > 0 ? ask : bid, spread = ask - bid;
            double sl = NormalizeDouble(c1 - dir * InpSLATR * atr, _Digits);
            double slDist = (entry - sl) * dir;
            double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
            double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
            double perLot = (tv > 0 && ts > 0) ? slDist / ts * tv : 0;
            double lots = perLot > 0 ? MathFloor(eq * fr / 100.0 / perLot / step) * step : 0;
            if(lots < vmin && perLot > 0 && vmin * perLot / eq * 100.0 <= InpMinLotCap) lots = vmin;
            lots = MathMin(lots, MathMin(InpMaxLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)));
            if(slDist <= 0) status = "วันนี้ข้าม: ราคาเลย SL แล้ว";
            else if(spread > InpMaxSpreadUSD) status = "วันนี้ข้าม: spread กว้างเกิน";
            else if(lots < vmin) status = StringFormat("วันนี้ข้าม: 0.01 lot เสี่ยง %.1f%% เกิน %.0f%%", vmin * perLot / eq * 100.0, InpMinLotCap);
            else
            {
               lots = NormalizeDouble(lots, 2);
               bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "DMA") : trade.Sell(lots, _Symbol, 0, sl, 0, "DMA");
               if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
               {
                  status = "เปิดไม้แล้ว";
                  LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%.2f,%.2f,", TimeToString(now, TIME_DATE | TIME_SECONDS), dir, lots,
                          DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
                          DoubleToString(sl, _Digits), adxv, lots * perLot / eq * 100.0));
               }
               else { status = "order ล้มเหลว " + IntegerToString((int)trade.ResultRetcode()); gTradedDay = -1; GVSet("day", -1); }
            }
         }
      }
   }

   Comment(StringFormat("XAU DMA v5.00\nUTC %s\nDD %.1f%% | Risk %.2f%%\n%s", TimeToString(utc, TIME_DATE | TIME_MINUTES), dd, fr, status));
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
