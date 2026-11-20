//+------------------------------------------------------------------+
//|  XAU QUARTET v1.00 — วงสี่ประสานทองคำ (4 เครื่องยนต์ตามเทรนด์)      |
//|                                                                  |
//|  ติดตั้งกราฟ XAUUSD กราฟเดียว (TF ใดก็ได้) EA คำนวณ H1/H4 เอง        |
//|                                                                  |
//|  เครื่องยนต์ (ค่าเดิมของผู้สร้างอินดิเคเตอร์ ไม่ได้ออฟติไมซ์):         |
//|   1 KST H1   : KST (ROC 10/15/20/30, SMA 10/10/10/15) vs SMA 9     |
//|   2 Coral H1 : Coral Trend (smoothing 21, cd 0.4) ความชันขึ้น/ลง     |
//|   3 Gann H1  : Gann HiLo Activator (SMA High 13 / Low 21 แท่งก่อน)   |
//|   4 SSL H4   : SSL channel HMA60 ของ High/Low                     |
//|  ทุกเครื่อง: ตัดสินที่แท่งปิด สถานะเปลี่ยน -> ปิดไม้เดิมแล้วเปิดทางใหม่ |
//|   SL = 1.5 x ATR(14) ของ TF นั้น ไม่มี TP ถือจนสัญญาณกลับทิศ           |
//|                                                                  |
//|  ทดสอบ 2 ปี (พ.ย.2024-พ.ย.2026, Dukascopy M1 bid/ask, Cent USD 300): |
//|   0.5%  : $1,686  DD 24% | ปีก่อน $694  | ปีล่าสุด $729             |
//|   0.75% : $3,351  DD 35% | ปีก่อน $973  | ปีล่าสุด $1,033           |
//|   1%    : $5,992  DD 44% | ปีก่อน $1,300 | ปีล่าสุด $1,383          |
//|   1.5%  : ชน DD 50% หยุด (จึงไม่มีให้เลือก)                         |
//|   แต่ละเครื่องผ่านสุ่มทิศ 2 ปี >= 98.7%, Long และ Short บวกทั้งคู่      |
//|   ~85 ไม้/เดือน อัตราชนะ ~30-40% ยังไม่หัก swap                       |
//|   ชุดเครื่องยนต์เลือกหลังเห็นผล ผลจริงคาดว่าต่ำกว่านี้                  |
//|                                                                  |
//|  บัญชี: Cent แนะนำ (SL กว้าง 10-40$) | Standard ทุนน้อยจะข้ามไม้มาก    |
//|  ยังไม่ได้คอมไพล์/ทดสอบใน MT5 — ทดสอบ Strategy Tester + demo ก่อน     |
//+------------------------------------------------------------------+
#property copyright "XAU QUARTET"
#property version   "1.00"
#property strict
#include <Trade\Trade.mqh>

enum ENUM_Q_RISK { RISK_LOW = 0, RISK_MID = 1, RISK_HIGH = 2 };

input group "=== ความเสี่ยง (เปลี่ยนได้จากแดชบอร์ด) ==="
input ENUM_Q_RISK InpRisk = RISK_MID;   // ระดับความเสี่ยงเริ่มต้น
input double InpRiskLow  = 0.5;    // ต่ำ: % ต่อไม้
input double InpRiskMid  = 0.75;   // กลาง: % ต่อไม้
input double InpRiskHigh = 1.0;    // สูง: % ต่อไม้
input double InpMinLotCap = 5.5;   // ถ้าต้องใช้ lot ขั้นต่ำ: เข้าเฉพาะเมื่อเสี่ยงจริง <= % นี้
input double InpDDHalt    = 50.0;  // DD จากจุดสูงสุด (%) ปิดทุกไม้และหยุด
input double InpMaxSpreadUSD = 1.5;
input group "=== เครื่องยนต์ (เปิด/ปิดได้จากแดชบอร์ด) ==="
input bool   InpUseKST   = true;   // KST H1
input bool   InpUseCoral = true;   // Coral H1
input bool   InpUseGann  = true;   // Gann HiLo H1
input bool   InpUseSSL   = true;   // SSL H4
input double InpSLATR    = 1.5;    // SL = k x ATR(14)
input int    InpCoralLen = 21;     // Coral smoothing
input double InpCoralCd  = 0.4;    // Coral constant D
input int    InpGannHi   = 13;     // Gann HiLo: SMA ของ High
input int    InpGannLo   = 21;     // Gann HiLo: SMA ของ Low
input int    InpSSLLen   = 60;     // SSL H4: ความยาว HMA
input group "=== ทั่วไป ==="
input long   InpMagic  = 891000;   // magic: KST +0, Coral +1, Gann +2, SSL +3
input int    InpBars   = 1500;     // จำนวนแท่งย้อนหลังที่ใช้คำนวณ
input int    InpPanelX = 10;
input int    InpPanelY = 20;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_quartet_trades.csv";

#define NENG 4
struct Engine
{
   string           name, nick, desc;
   ENUM_TIMEFRAMES  tf;
   long             magic;
   int              state;      // +1 ขาขึ้น / -1 ขาลง / 0 ยังไม่รู้
   double           atr;
   datetime         lastBar;
   string           note;
   bool             ready, on;
};

CTrade  trade;
Engine  E[NENG];
int     gRisk;
bool    gPaused = false, gHalted = false;
double  gPeak = 0;
string  gPfx;
string  P = "XQT_";
int     sTrades = 0, sWins = 0; double sGrossW = 0, sGrossL = 0, sToday = 0, sMonth = 0;
string  sLast[5];

//====================================================================
// ตัวช่วยคำนวณ (array เรียงจากเก่าไปใหม่, index สุดท้าย = แท่งปิดล่าสุด)
//====================================================================
double SMAat(const double &x[], int end, int n)
{
   if(end - n + 1 < 0) return EMPTY_VALUE;
   double s = 0; for(int k = 0; k < n; k++) s += x[end - k]; return s / n;
}
double WMAat(const double &x[], int end, int n)
{
   double s = 0, w = 0;
   for(int k = 0; k < n; k++) { double wk = n - k; s += x[end - k] * wk; w += wk; }
   return s / w;
}
double HMAat(const double &x[], int end, int n)      // sqrt แบบปัดลง ตรงกับสคริปต์ทดสอบ
{
   int h = n / 2, q = (int)MathFloor(MathSqrt(n));
   double tmp[]; ArrayResize(tmp, q);
   for(int k = 0; k < q; k++) tmp[k] = 2 * WMAat(x, end - (q - 1 - k), h) - WMAat(x, end - (q - 1 - k), n);
   return WMAat(tmp, q - 1, q);
}
double ATRcalc(const MqlRates &r[], int n)          // RMA(14) ของ True Range
{
   double a = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
   {
      double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      a += (tr - a) / 14.0;
   }
   return a;
}

// สถานะของแต่ละอินดิเคเตอร์ที่แท่งปิดล่าสุด
int StateKST(const double &c[], int n)
{
   double r1[], r2[], r3[], r4[]; ArrayResize(r1, n); ArrayResize(r2, n); ArrayResize(r3, n); ArrayResize(r4, n);
   for(int i = 0; i < n; i++)
   {
      r1[i] = i >= 10 ? (c[i] / c[i - 10] - 1) * 100 : 0; r2[i] = i >= 15 ? (c[i] / c[i - 15] - 1) * 100 : 0;
      r3[i] = i >= 20 ? (c[i] / c[i - 20] - 1) * 100 : 0; r4[i] = i >= 30 ? (c[i] / c[i - 30] - 1) * 100 : 0;
   }
   double k[]; ArrayResize(k, n); int first = 30 + 15 - 1;
   for(int i = 0; i < n; i++)
      k[i] = i < first ? 0 : SMAat(r1, i, 10) + 2 * SMAat(r2, i, 10) + 3 * SMAat(r3, i, 10) + 4 * SMAat(r4, i, 15);
   if(n - 1 < first + 9) return 0;
   double d = k[n - 1] - SMAat(k, n - 1, 9);
   return d > 0 ? 1 : (d < 0 ? -1 : 0);
}
int StateCoral(const double &c[], int n, int &prevState)
{
   double di = (InpCoralLen - 1) / 2.0 + 1, c1 = 2 / (di + 1), c2 = 1 - c1, cd = InpCoralCd;
   double c3 = 3 * (cd * cd + cd * cd * cd), c4 = -3 * (2 * cd * cd + cd + cd * cd * cd), c5 = 3 * cd + 1 + cd * cd * cd + 3 * cd * cd;
   double v[6]; for(int j = 0; j < 6; j++) v[j] = c[0];
   double bf = 0, pbf = 0; int st = 0;
   for(int t = 0; t < n; t++)
   {
      double src = c[t];
      for(int j = 0; j < 6; j++) { v[j] = c1 * src + c2 * v[j]; src = v[j]; }
      pbf = bf; bf = -cd * cd * cd * v[5] + c3 * v[4] + c4 * v[3] + c5 * v[2];
      if(t > 0) st = bf > pbf ? 1 : (bf < pbf ? -1 : 0);
   }
   prevState = st;
   return st;
}
int StateGann(const MqlRates &r[], int n)
{
   double h[], l[]; ArrayResize(h, n); ArrayResize(l, n);
   for(int i = 0; i < n; i++) { h[i] = r[i].high; l[i] = r[i].low; }
   int st = 0, start = MathMax(InpGannHi, InpGannLo) + 1;
   for(int i = start; i < n; i++)
   {
      double hi = SMAat(h, i - 1, InpGannHi), lo = SMAat(l, i - 1, InpGannLo);
      if(r[i].close > hi) st = 1; else if(r[i].close < lo) st = -1;
   }
   return st;
}
int StateSSL(const MqlRates &r[], int n)
{
   double h[], l[]; ArrayResize(h, n); ArrayResize(l, n);
   for(int i = 0; i < n; i++) { h[i] = r[i].high; l[i] = r[i].low; }
   int st = 0, need = InpSSLLen + (int)MathSqrt(InpSSLLen) + 2;
   for(int i = need; i < n; i++)
   {
      double eh = HMAat(h, i, InpSSLLen), el = HMAat(l, i, InpSSLLen);
      if(r[i].close > eh) st = 1; else if(r[i].close < el) st = -1;
   }
   return st;
}
bool EngineCalc(int k)
{
   MqlRates r[];
   int n = CopyRates(_Symbol, E[k].tf, 1, InpBars, r);
   if(n < 300) return false;
   double c[]; ArrayResize(c, n); for(int i = 0; i < n; i++) c[i] = r[i].close;
   int st = 0, dummy;
   if(k == 0) st = StateKST(c, n);
   else if(k == 1) st = StateCoral(c, n, dummy);
   else if(k == 2) st = StateGann(r, n);
   else st = StateSSL(r, n);
   E[k].atr = ATRcalc(r, n);
   if(st != 0) E[k].state = st;
   return true;
}

//====================================================================
// บัญชี / ความเสี่ยง / คำสั่ง
//====================================================================
bool   IsCent()  { string c = AccountInfoString(ACCOUNT_CURRENCY); return c == "USC" || c == "EUC" || StringFind(_Symbol, "c", 6) >= 0; }
double RiskPct() { return gRisk == RISK_LOW ? InpRiskLow : gRisk == RISK_MID ? InpRiskMid : InpRiskHigh; }
string BtEnd(int r) { string s[3] = {"$1,686 · DD 24%", "$3,351 · DD 35%", "$5,992 · DD 44%"}; return s[r]; }
int    BtDD(int r)  { int d[3] = {24, 35, 44}; return d[r]; }

ulong EngineTicket(long magic)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == magic) return t;
   }
   return 0;
}
void LogLine(string s)
{
   if(!InpWriteLog) return;
   int f = FileOpen(InpLogFile, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(f == INVALID_HANDLE) return;
   if(FileSize(f) == 0) FileWriteString(f, "time,event,dir,lots,req_price,fill_price,spread,sl,engine,risk_pct_real,net_profit\r\n");
   FileSeek(f, 0, SEEK_END); FileWriteString(f, s + "\r\n"); FileClose(f);
}
void OpenEngine(int k, int dir)
{
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), spread = ask - bid;
   if(spread > InpMaxSpreadUSD) { E[k].note = "ข้าม: spread กว้าง"; return; }
   double entry = dir > 0 ? ask : bid, dist = InpSLATR * E[k].atr;
   double sl = NormalizeDouble(entry - dir * dist, _Digits);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tv <= 0 || ts <= 0 || dist <= 0) { E[k].note = "ข้าม: ข้อมูลสัญญาไม่พร้อม"; return; }
   double perLot = dist / ts * tv;
   double lots = MathFloor(eq * RiskPct() / 100.0 / perLot / step) * step;
   if(lots < vmin)
   {
      double rp = vmin * perLot / eq * 100.0;
      if(rp > InpMinLotCap) { E[k].note = StringFormat("ข้าม: lot ขั้นต่ำเสี่ยง %.1f%%", rp); return; }
      lots = vmin;
   }
   lots = NormalizeDouble(MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), 2);
   trade.SetExpertMagicNumber(E[k].magic);
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "QUARTET " + E[k].name) : trade.Sell(lots, _Symbol, 0, sl, 0, "QUARTET " + E[k].name);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      E[k].note = (dir > 0 ? "เปิด BUY " : "เปิด SELL ") + DoubleToString(lots, 2) + " lot";
      LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%s,%.2f,", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), dir, lots,
              DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
              DoubleToString(sl, _Digits), E[k].name, lots * perLot / eq * 100.0));
   }
   else E[k].note = "ส่งคำสั่งไม่สำเร็จ " + IntegerToString((int)trade.ResultRetcode());
}
void CloseAll() { for(int k = 0; k < NENG; k++) { ulong t = EngineTicket(E[k].magic); if(t > 0) trade.PositionClose(t); } }

void UpdateStats()
{
   datetime now = TimeCurrent(); MqlDateTime d; TimeToStruct(now, d);
   datetime dayStart = now - (d.hour * 3600 + d.min * 60 + d.sec), monStart = dayStart - (d.day - 1) * 86400;
   if(!HistorySelect(0, now)) return;
   sTrades = 0; sWins = 0; sGrossW = 0; sGrossL = 0; sToday = 0; sMonth = 0;
   for(int i = 0; i < 5; i++) sLast[i] = "";
   int nl = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dl = HistoryDealGetTicket(i); long mg = HistoryDealGetInteger(dl, DEAL_MAGIC);
      if(mg < InpMagic || mg > InpMagic + NENG - 1 || HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(dl, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
      sTrades++; if(p > 0) { sWins++; sGrossW += p; } else sGrossL -= p;
      if(t >= dayStart) sToday += p;
      if(t >= monStart) sMonth += p;
      if(nl < 5)
      {
         long ty = HistoryDealGetInteger(dl, DEAL_TYPE);
         sLast[nl++] = StringFormat("%s  %-5s  %s  %+.2f", TimeToString(t, TIME_DATE | TIME_MINUTES), E[(int)(mg - InpMagic)].name, ty == DEAL_TYPE_SELL ? "BUY " : "SELL", p);
      }
   }
}

//====================================================================
// แดชบอร์ด
//====================================================================
color C_BG = C'10,12,24', C_PANEL = C'20,24,44', C_EDGE = C'170,120,255', C_GOLD = C'255,196,0', C_TXT = C'225,230,240',
      C_MUTED = C'130,140,165', C_GREEN = C'0,230,118', C_RED = C'255,70,90', C_ORANGE = C'255,150,0', C_OFF = C'60,64,85';
color C_ENG[NENG] = {C'0,200,255', C'255,120,90', C'255,196,0', C'0,230,160'};

void Rect(string id, int x, int y, int w, int h, color bg, color bd = clrNONE, int bw = 1)
{
   string n = P + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, bd == clrNONE ? bg : bd); ObjectSetInteger(0, n, OBJPROP_WIDTH, bw);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true); ObjectSetInteger(0, n, OBJPROP_BACK, false);
}
void Text(string id, int x, int y, string s, color c, int sz = 9, bool bold = false, ENUM_ANCHOR_POINT an = ANCHOR_LEFT_UPPER)
{
   string n = P + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, bold ? "Tahoma Bold" : "Tahoma");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz); ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetInteger(0, n, OBJPROP_ANCHOR, an);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
void Button(string id, int x, int y, int w, int h, string s, bool on, color onc)
{
   string n = P + "B_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, "Tahoma"); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? onc : C_PANEL); ObjectSetInteger(0, n, OBJPROP_COLOR, on ? C_BG : C_TXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, on ? onc : C_OFF); ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
color DDColor(double dd) { return dd < 20 ? C_GREEN : dd < 35 ? C_GOLD : dd < 45 ? C_ORANGE : C_RED; }

// โลโก้: 4 แท่งเสียง (เครื่องยนต์ละสี) สูงตามสถานะ
void Logo(int x, int y)
{
   for(int k = 0; k < NENG; k++)
   {
      int h = E[k].state > 0 ? 36 : E[k].state < 0 ? 14 : 24;
      Rect("lg" + IntegerToString(k), x + k * 12, y + 40 - h, 9, h, E[k].on ? C_ENG[k] : C_OFF);
   }
}

void DrawPanel()
{
   const int W = 560;
   bool   cent = IsCent(); string cur = AccountInfoString(ACCOUNT_CURRENCY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   color  sc  = gHalted ? C_RED : gPaused ? C_ORANGE : C_GREEN;
   string stat = gHalted ? "หยุด: DD ถึงเพดาน" : gPaused ? "หยุดชั่วคราว" : "กำลังทำงาน";

   Rect("bg", 0, 0, W, 640, C_BG, C_EDGE, 2);
   Logo(18, 12);
   Text("title", 80, 12, "XAU QUARTET", C_GOLD, 18, true);
   Text("sub", 82, 42, "วงสี่ประสานทองคำ · KST · Coral · Gann · SSL · v1.00", C_MUTED, 8);
   Rect("stat_bg", 400, 16, 145, 26, C_PANEL, sc, 2);
   Text("stat", 472, 21, "● " + stat, sc, 9, true, ANCHOR_UPPER);
   Text("acct", 400, 48, (cent ? "บัญชี Cent (" : "บัญชี Standard (") + cur + ")", cent ? C_GREEN : C_ORANGE, 8);

   // ความเสี่ยง
   Text("l_risk", 14, 76, "ความเสี่ยง/ไม้", C_MUTED, 9);
   string rn[3] = {"ต่ำ", "กลาง", "สูง"}; double rv[3] = {InpRiskLow, InpRiskMid, InpRiskHigh}; color rc[3] = {C_GREEN, C_GOLD, C_ORANGE};
   for(int k = 0; k < 3; k++) Button("r" + IntegerToString(k), 110 + k * 145, 72, 138, 26, StringFormat("%s %.2g%%", rn[k], rv[k]), gRisk == k, rc[k]);
   int bdd = BtDD(gRisk);
   Text("bt", 14, 106, "ทดสอบ 2 ปี ($300 → " + BtEnd(gRisk) + ")" + (bdd >= 40 ? "  ! ใกล้เพดาน" : "  อยู่ในเกณฑ์") + " · เปิดครบ 4 เครื่อง", DDColor(bdd), 8);

   // บัญชี
   Rect("acc", 10, 126, W - 20, 100, C_PANEL, C_OFF);
   Text("a1", 22, 134, "ทุน (Balance)", C_MUTED, 8);       Text("a1v", 22, 148, StringFormat("%.2f %s", bal, cur), C_TXT, 12, true);
   Text("a2", 200, 134, "มูลค่าสุทธิ (Equity)", C_MUTED, 8); Text("a2v", 200, 148, StringFormat("%.2f %s", eq, cur), eq >= bal ? C_GREEN : C_RED, 12, true);
   Text("a3", 380, 134, cent ? "เท่ากับ (USD)" : "กำไร/ขาดทุนลอย", C_MUTED, 8);
   Text("a3v", 380, 148, cent ? StringFormat("$%.2f", eq * 0.01) : StringFormat("%+.2f", eq - bal), C_GOLD, 12, true);
   Text("a4", 22, 174, StringFormat("วันนี้ %+.2f", sToday), sToday >= 0 ? C_GREEN : C_RED, 9);
   Text("a5", 200, 174, StringFormat("เดือนนี้ %+.2f", sMonth), sMonth >= 0 ? C_GREEN : C_RED, 9);
   Text("a6", 380, 174, StringFormat("จุดสูงสุด %.2f", gPeak), C_MUTED, 9);
   Text("dd_l", 22, 198, StringFormat("DD ตอนนี้ %.1f%%", dd), DDColor(dd), 9, true);
   int gx = 150, gw = 380;
   Rect("dd_bg", gx, 200, gw, 14, C_BG, C_OFF);
   Rect("dd_fg", gx + 1, 201, (int)MathMax(1, MathMin(gw - 2, (gw - 2) * dd / InpDDHalt)), 12, DDColor(dd));
   Text("dd_m", gx + gw, 215, StringFormat("เพดาน %.0f%%", InpDDHalt), C_MUTED, 7, false, ANCHOR_RIGHT_UPPER);

   // เครื่องยนต์ 2 x 2
   Text("l_eng", 14, 232, "เครื่องยนต์ (กดปุ่ม เปิด/ปิด ที่การ์ด)", C_MUTED, 9);
   for(int k = 0; k < NENG; k++)
   {
      int x = 10 + (k % 2) * 275, y = 250 + (k / 2) * 122;
      ulong t = EngineTicket(E[k].magic); int pd = 0; double pp = 0, pl = 0;
      if(t > 0 && PositionSelectByTicket(t)) { pd = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; pp = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); pl = PositionGetDouble(POSITION_VOLUME); }
      color ec = !E[k].on ? C_OFF : pd > 0 ? C_GREEN : pd < 0 ? C_RED : C_ENG[k];
      string id = "e" + IntegerToString(k);
      Rect(id, x, y, 265, 114, C_PANEL, ec, 2);
      Rect(id + "c", x + 2, y + 2, 5, 110, E[k].on ? C_ENG[k] : C_OFF);
      Text(id + "n", x + 14, y + 6, E[k].name + " · " + E[k].nick, E[k].on ? C_ENG[k] : C_MUTED, 10, true);
      Button("t" + IntegerToString(k), x + 200, y + 6, 56, 20, E[k].on ? "เปิด" : "ปิด", E[k].on, C_GREEN);
      Text(id + "s", x + 14, y + 30, !E[k].on ? "ปิดอยู่ (ไม่เปิดไม้ใหม่)" : pd > 0 ? "▲ ถือ BUY" : pd < 0 ? "▼ ถือ SELL" : "● รอสัญญาณกลับทิศ", ec, 11, true);
      Text(id + "p", x + 14, y + 52, pd != 0 ? StringFormat("%.2f lot  %+.2f", pl, pp) : " ", pp >= 0 ? C_GREEN : C_RED, 9);
      Text(id + "t", x + 14, y + 70, "สัญญาณ: " + (E[k].state > 0 ? "ขาขึ้น" : E[k].state < 0 ? "ขาลง" : "-") + StringFormat("  · SL %.1f$", InpSLATR * E[k].atr), C_TXT, 8);
      Text(id + "d", x + 14, y + 84, E[k].desc, C_MUTED, 7);
      Text(id + "x", x + 14, y + 97, E[k].note == "" ? " " : E[k].note, C_MUTED, 7);
   }

   // สถิติ + ไม้ล่าสุด
   Rect("st", 10, 496, 230, 98, C_PANEL, C_OFF);
   double wr = sTrades > 0 ? 100.0 * sWins / sTrades : 0, pf = sGrossL > 0 ? sGrossW / sGrossL : 0;
   Text("st0", 22, 502, "ผลงานทั้งหมด", C_MUTED, 9);
   Text("st1", 22, 520, StringFormat("ไม้ที่ปิดแล้ว %d · ชนะ %.0f%%", sTrades, wr), C_TXT, 9);
   Text("st2", 22, 538, StringFormat("Profit Factor %.2f (เป้า > 1.3)", pf), pf >= 1.3 ? C_GREEN : pf >= 1.0 ? C_GOLD : C_RED, 9);
   Text("st3", 22, 556, StringFormat("กำไรสุทธิ %+.2f", sGrossW - sGrossL), sGrossW >= sGrossL ? C_GREEN : C_RED, 9, true);
   Text("st4", 22, 576, "แพ้ติดกันเป็นปกติของระบบตามเทรนด์", C_MUTED, 7);
   Rect("lt", 250, 496, 300, 98, C_PANEL, C_OFF);
   Text("lt0", 262, 502, "5 ไม้ล่าสุด", C_MUTED, 9);
   for(int i = 0; i < 5; i++)
   {
      bool pos = StringFind(sLast[i], "+") >= 0;
      Text("lt" + IntegerToString(i + 1), 262, 518 + i * 15, sLast[i] == "" ? "-" : sLast[i], sLast[i] == "" ? C_MUTED : pos ? C_GREEN : C_RED, 7);
   }
   Button("pause", 10, 600, 268, 30, gPaused ? "▶ ทำงานต่อ" : "|| หยุดเปิดไม้ใหม่ชั่วคราว", gPaused, C_ORANGE);
   Button("close", 290, 600, 260, 30, "X  ปิดทุกไม้ของ QUARTET", false, C_RED);
   ChartRedraw();
}

//====================================================================
// ระบบหลัก
//====================================================================
void InitEngine(int k, string name, string nick, string desc, ENUM_TIMEFRAMES tf, bool on)
{
   E[k].name = name; E[k].nick = nick; E[k].desc = desc; E[k].tf = tf; E[k].magic = InpMagic + k;
   E[k].state = 0; E[k].atr = 0; E[k].lastBar = 0; E[k].note = ""; E[k].ready = false;
   string g = gPfx + "on" + IntegerToString(k);
   E[k].on = GlobalVariableCheck(g) ? GlobalVariableGet(g) > 0 : on;
}
int OnInit()
{
   gPfx = "XQT_" + IntegerToString(InpMagic) + "_";
   InitEngine(0, "KST",   "นักวัดแรง", "KST 10/15/20/30 vs SMA9 · H1 · ~26 ไม้/เดือน", PERIOD_H1, InpUseKST);
   InitEngine(1, "Coral", "สายน้ำ",   StringFormat("Coral %d / %.1f ความชัน · H1 · ~22 ไม้/เดือน", InpCoralLen, InpCoralCd), PERIOD_H1, InpUseCoral);
   InitEngine(2, "Gann",  "ขั้นบันได", StringFormat("Gann HiLo %d/%d · H1 · ~30 ไม้/เดือน", InpGannHi, InpGannLo), PERIOD_H1, InpUseGann);
   InitEngine(3, "SSL",   "พี่ใหญ่ H4", StringFormat("SSL HMA%d · H4 · ~7 ไม้/เดือน", InpSSLLen), PERIOD_H4, InpUseSSL);
   gRisk   = GlobalVariableCheck(gPfx + "risk")  ? (int)GlobalVariableGet(gPfx + "risk") : (int)InpRisk;
   gPaused = GlobalVariableCheck(gPfx + "pause") && GlobalVariableGet(gPfx + "pause") > 0;
   gHalted = GlobalVariableCheck(gPfx + "halt")  && GlobalVariableGet(gPfx + "halt") > 0;
   gPeak   = GlobalVariableCheck(gPfx + "peak")  ? GlobalVariableGet(gPfx + "peak") : AccountInfoDouble(ACCOUNT_EQUITY);
   trade.SetTypeFillingBySymbol(_Symbol); trade.SetDeviationInPoints(50);
   for(int k = 0; k < NENG; k++)                // เริ่มจากสถานะปัจจุบัน: ไม่เปิดไม้จนกว่าจะเกิดการกลับทิศครั้งถัดไป
   {
      E[k].ready = EngineCalc(k);
      E[k].lastBar = iTime(_Symbol, E[k].tf, 0);
      if(!E[k].ready) E[k].note = "รอข้อมูลกราฟย้อนหลัง";
   }
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) Print("XAU QUARTET: ออกแบบมาสำหรับ XAUUSD");
   EventSetTimer(1);
   UpdateStats(); DrawPanel();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); ObjectsDeleteAll(0, P); ChartRedraw(); }

void OnTick()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > gPeak) { gPeak = eq; GlobalVariableSet(gPfx + "peak", gPeak); }
   double dd = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GlobalVariableSet(gPfx + "halt", 1); CloseAll();
      Print("XAU QUARTET: DD ", DoubleToString(dd, 1), "% ถึงเพดาน — ปิดทุกไม้และหยุด (ลบ Global Variable ", gPfx, "halt เพื่อเริ่มใหม่)");
   }
   for(int k = 0; k < NENG; k++)
   {
      datetime b = iTime(_Symbol, E[k].tf, 0);
      if(b == 0 || b == E[k].lastBar) continue;
      E[k].lastBar = b;
      int prev = E[k].state;
      if(!E[k].ready) { E[k].ready = EngineCalc(k); continue; }
      if(!EngineCalc(k)) continue;
      if(E[k].state == 0 || E[k].state == prev || prev == 0) continue;
      // กลับทิศ: ปิดไม้เดิมของเครื่องนี้เสมอ (แม้เครื่องถูกปิด) แล้วเปิดทางใหม่
      ulong t = EngineTicket(E[k].magic);
      if(t > 0) trade.PositionClose(t);
      E[k].note = E[k].state > 0 ? "กลับเป็นขาขึ้น" : "กลับเป็นขาลง";
      if(gHalted || gPaused || !E[k].on) continue;
      OpenEngine(k, E[k].state);
   }
}

void OnTimer() { UpdateStats(); DrawPanel(); }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, P + "B_") != 0) return;
   string b = StringSubstr(sparam, StringLen(P + "B_"));
   if(StringSubstr(b, 0, 1) == "r") gRisk = (int)StringToInteger(StringSubstr(b, 1));
   else if(StringSubstr(b, 0, 1) == "t")
   {
      int k = (int)StringToInteger(StringSubstr(b, 1));
      if(k >= 0 && k < NENG) { E[k].on = !E[k].on; GlobalVariableSet(gPfx + "on" + IntegerToString(k), E[k].on ? 1 : 0); }
   }
   else if(b == "pause") { gPaused = !gPaused; GlobalVariableSet(gPfx + "pause", gPaused ? 1 : 0); }
   else if(b == "close")
   {
      if(MessageBox("ปิดทุกไม้ของ XAU QUARTET ตอนนี้?", "ยืนยัน", MB_YESNO | MB_ICONQUESTION) == IDYES) CloseAll();
   }
   GlobalVariableSet(gPfx + "risk", gRisk);
   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   DrawPanel();
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
{
   if(!InpWriteLog || trans.type != TRADE_TRANSACTION_DEAL_ADD || !HistoryDealSelect(trans.deal)) return;
   long mg = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   if(mg < InpMagic || mg > InpMagic + NENG - 1 || HistoryDealGetInteger(trans.deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) return;
   double net = HistoryDealGetDouble(trans.deal, DEAL_PROFIT) + HistoryDealGetDouble(trans.deal, DEAL_SWAP) + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
   LogLine(StringFormat("%s,CLOSE,,%.2f,,%s,,,%s,,%.2f", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), HistoryDealGetDouble(trans.deal, DEAL_VOLUME),
           DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits), E[(int)(mg - InpMagic)].name, net));
}
//+------------------------------------------------------------------+
