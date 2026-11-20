//+------------------------------------------------------------------+
//|  XAU QUARTET v1.10 — "MOTHERSHIP EDITION"                        |
//|  ยานแม่สี่ประสานทองคำ: 4 เครื่องยนต์ตามเทรนด์ + แดชบอร์ดยานอวกาศ      |
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
//|  v1.10: ความเสี่ยง 5 ระดับ 0.5-1.5% | เพดาน DD เริ่มต้น 70%          |
//|         โหมดล็อตอัตโนมัติ 5 แบบ: %Equity / %Balance / เงินเสี่ยงคงที่ /   |
//|         ล็อตต่อทุนทุก X / ล็อตคงที่ + ทบต้น/ไม่ทบต้น, ตัวคูณรายเครื่อง,   |
//|         ลดล็อตเมื่อ DD, เพดานล็อต, เพดานความเสี่ยงรวม, กติกาล็อตขั้นต่ำ |
//|         แดชบอร์ดยานแม่ (ดาว ระบบสแกน ไฟ UFO เครื่องยนต์เรืองแสง)     |
//|         ธีมกราฟอวกาศ (แท่งเทียนนีออน) + ลูกศรเข้าไม้ + เส้น SL สด     |
//|                                                                  |
//|  ทดสอบ 2 ปี (พ.ย.2024-พ.ย.2026, Dukascopy M1 bid/ask, Cent USD 300,  |
//|  เพดาน DD 70%):                                                   |
//|   0.5%  : $1,686   DD 24%   | โอกาสชน 70% (bootstrap) ~0%          |
//|   0.75% : $3,351   DD 35%   | ~0%                                 |
//|   1%    : $5,992   DD 44%   | ~3%                                 |
//|   1.25% : $9,718   DD 53%   | ~10%                                |
//|   1.5%  : $14,385  DD 60%   | ~22%  (เดือนแย่สุด -$3,902)          |
//|   เพดาน 50%: 1.25% และ 1.5% ชนเพดานหยุดตั้งแต่ ส.ค. 2025             |
//|   ชุดเครื่องยนต์เลือกหลังเห็นผล ยังไม่หัก swap ผลจริงคาดว่าต่ำกว่านี้    |
//|                                                                  |
//|  บัญชี: Cent แนะนำ (SL กว้าง 10-40$) | Standard ทุนน้อยจะข้ามไม้มาก    |
//|  ยังไม่ได้คอมไพล์/ทดสอบใน MT5 — ทดสอบ Strategy Tester + demo ก่อน     |
//+------------------------------------------------------------------+
#property copyright "XAU QUARTET"
#property version   "1.10"
#property strict
#include <Trade\Trade.mqh>

#define NRISK 5
#define NENG  4
#define NLOTMODE 5
enum ENUM_LOT_MODE
{
   LOT_RISK_EQUITY  = 0,   // อัตโนมัติ: % ของ Equity (ค่าเริ่มต้น ตรงกับแบ็กเทส)
   LOT_RISK_BALANCE = 1,   // อัตโนมัติ: % ของ Balance
   LOT_RISK_MONEY   = 2,   // อัตโนมัติ: เสี่ยงเงินคงที่ต่อไม้ (สกุลเงินบัญชี)
   LOT_PER_STEP     = 3,   // อัตโนมัติ: ล็อต X ต่อทุนทุก Y
   LOT_FIXED        = 4    // ล็อตคงที่
};
enum ENUM_MINLOT_RULE
{
   MINLOT_CAP    = 0,      // ใช้ล็อตขั้นต่ำถ้าเสี่ยงจริง <= InpMinLotCap ไม่งั้นข้าม
   MINLOT_ALWAYS = 1,      // ใช้ล็อตขั้นต่ำเสมอ (เสี่ยงเกินที่ตั้งได้)
   MINLOT_SKIP   = 2       // ข้ามไม้ทุกครั้งที่คำนวณได้ต่ำกว่าล็อตขั้นต่ำ
};

input group "=== ความเสี่ยง (เปลี่ยนได้จากแดชบอร์ด) ==="
input int    InpRiskLevel = 2;     // ระดับเริ่มต้น 0-4 (0=0.5% 1=0.75% 2=1% 3=1.25% 4=1.5%) — 2 = 1% (สมดุล)
input double InpRisk0 = 0.5;       // ระดับ 1: % ต่อไม้
input double InpRisk1 = 0.75;      // ระดับ 2: % ต่อไม้
input double InpRisk2 = 1.0;       // ระดับ 3: % ต่อไม้
input double InpRisk3 = 1.25;      // ระดับ 4: % ต่อไม้
input double InpRisk4 = 1.5;       // ระดับ 5: % ต่อไม้
input group "=== โหมดล็อต (ออโต้ล็อต) — เปลี่ยนโหมดได้จากแดชบอร์ด ==="
input ENUM_LOT_MODE InpLotMode = LOT_RISK_EQUITY; // โหมดล็อตเริ่มต้น
input bool   InpCompound   = true;   // ทบต้น (false = คิดจากทุนตั้งต้นคงที่)
input double InpBaseCapital = 0;     // ทุนตั้งต้นเมื่อไม่ทบต้น (0 = Balance ตอนติดตั้ง EA)
input double InpRiskMoney  = 10.0;   // โหมดเงินคงที่: เสี่ยงต่อไม้ (สกุลเงินบัญชี เช่น USC)
input double InpStepMoney  = 3000;   // โหมดล็อตต่อทุน: ทุกๆ ทุนเท่านี้ ...
input double InpStepLot    = 0.01;   // ... ใช้ล็อตเท่านี้ (เช่น 0.01 ต่อ 3,000 USC)
input double InpFixedLot   = 0.01;   // โหมดล็อตคงที่
input double InpMultKST    = 1.0;    // ตัวคูณล็อต KST
input double InpMultCoral  = 1.0;    // ตัวคูณล็อต Coral
input double InpMultGann   = 1.0;    // ตัวคูณล็อต Gann
input double InpMultSSL    = 1.0;    // ตัวคูณล็อต SSL H4
input double InpDDReduceAt = 0;      // ลดล็อตเมื่อ DD >= % นี้ (0 = ปิด)
input double InpDDReduceMult = 0.5;  // ... ตัวคูณล็อตตอน DD สูง
input double InpMaxLot     = 0;      // ล็อตสูงสุดต่อไม้ (0 = ตามโบรกเกอร์)
input double InpMaxTotalRisk = 0;    // ความเสี่ยงรวมไม้ที่เปิดอยู่สูงสุด % (0 = ไม่จำกัด)
input ENUM_MINLOT_RULE InpMinLotRule = MINLOT_CAP; // กติกาเมื่อคำนวณได้ต่ำกว่าล็อตขั้นต่ำ
input double InpMinLotCap = 5.5;   // ถ้าต้องใช้ lot ขั้นต่ำ: เข้าเฉพาะเมื่อเสี่ยงจริง <= % นี้
input double InpDDHalt    = 70.0;  // DD จากจุดสูงสุด (%) ปิดทุกไม้และหยุด
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
input group "=== หน้าตา ==="
input bool   InpSpaceChart = true; // เปลี่ยนกราฟเป็นธีมอวกาศ (คืนค่าเดิมเมื่อถอด EA)
input bool   InpDrawTrades = true; // วาดลูกศรเข้าไม้ + เส้น SL บนกราฟ
input bool   InpAnimate    = true; // แอนิเมชัน (ดาวกะพริบ, เส้นสแกน, ไฟ UFO)
input group "=== ทั่วไป ==="
input long   InpMagic  = 891000;   // magic: KST +0, Coral +1, Gann +2, SSL +3 (เท่ากับ v1.00 ใช้แทนกันได้)
input int    InpBars   = 1500;     // จำนวนแท่งย้อนหลังที่ใช้คำนวณ
input int    InpPanelX = 10;
input int    InpPanelY = 20;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_quartet_trades.csv";

struct Engine
{
   string           name, nick, desc;
   ENUM_TIMEFRAMES  tf;
   long             magic;
   int              state;
   double           atr;
   datetime         lastBar, lastFlip;
   string           note;
   bool             ready, on;
};

CTrade  trade;
Engine  E[NENG];
int     gRisk, gLotMode;
double  gBase = 0;
int     gOY = 0;          // ระยะเลื่อนแนวตั้งของส่วนล่างแดชบอร์ด
bool    gPaused = false, gHalted = false;
double  gPeak = 0;
string  gPfx;
string  P = "XQT_";
int     sTrades = 0, sWins = 0; double sGrossW = 0, sGrossL = 0, sToday = 0, sMonth = 0;
string  sLast[5];
int     gFrame = 0;
// ค่าเดิมของกราฟ (คืนเมื่อถอด EA)
long    oBG, oFG, oGrid, oUp, oDn, oBull, oBear, oLine, oVol, oAsk, oBid, oShowGrid, oMode;

//====================================================================
// ตัวช่วยคำนวณ (array เรียงจากเก่าไปใหม่, index สุดท้าย = แท่งปิดล่าสุด)
//====================================================================
double SMAat(const double &x[], int end, int n)
{
   if(end - n + 1 < 0) return 0;
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
double ATRcalc(const MqlRates &r[], int n)
{
   double a = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
   {
      double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      a += (tr - a) / 14.0;
   }
   return a;
}
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
int StateCoral(const double &c[], int n)
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
   int st = k == 0 ? StateKST(c, n) : k == 1 ? StateCoral(c, n) : k == 2 ? StateGann(r, n) : StateSSL(r, n);
   E[k].atr = ATRcalc(r, n);
   if(st != 0) E[k].state = st;
   return true;
}

//====================================================================
// บัญชี / ความเสี่ยง
//====================================================================
bool   IsCent()  { string c = AccountInfoString(ACCOUNT_CURRENCY); return c == "USC" || c == "EUC" || StringFind(_Symbol, "c", 6) >= 0; }
double RiskOf(int r) { return r == 0 ? InpRisk0 : r == 1 ? InpRisk1 : r == 2 ? InpRisk2 : r == 3 ? InpRisk3 : InpRisk4; }
double RiskPct() { return RiskOf(gRisk); }
// ผลทดสอบ 2 ปี (Cent USD 300) ตามระดับ — ใช้ได้เมื่อความเสี่ยงเป็นค่าเริ่มต้น
string BtEnd(int r)  { string s[NRISK] = {"$1,686", "$3,351", "$5,992", "$9,718", "$14,385"}; return s[r]; }
int    BtDD(int r)   { int d[NRISK] = {24, 35, 44, 53, 60}; return d[r]; }
int    BtRuin(int r) { int p[NRISK] = {0, 0, 3, 10, 22}; return p[r]; }   // โอกาสชน DD 70% (bootstrap)

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

//====================================================================
// สีและรูปทรง
//====================================================================
color C_VOID = C'4,5,14', C_DEEP = C'9,11,28', C_PANEL = C'14,17,40', C_GLOW1 = C'60,20,120', C_GLOW2 = C'120,60,255', C_GLOW3 = C'0,255,200',
      C_TXT = C'225,232,255', C_MUTED = C'120,130,175', C_GOLD = C'255,205,60', C_GREEN = C'0,255,150', C_RED = C'255,50,110',
      C_ORANGE = C'255,150,40', C_OFF = C'48,52,80', C_ALIEN = C'120,255,90';
color C_ENG[NENG] = {C'0,220,255', C'255,90,200', C'255,205,60', C'120,255,90'};

void Rect(string id, int x, int y, int w, int h, color bg, color bd = clrNONE, int bw = 1)
{
   string n = P + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + gOY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(1, w)); ObjectSetInteger(0, n, OBJPROP_YSIZE, MathMax(1, h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg); ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, bd == clrNONE ? bg : bd); ObjectSetInteger(0, n, OBJPROP_WIDTH, bw);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true); ObjectSetInteger(0, n, OBJPROP_BACK, false);
}
void Text(string id, int x, int y, string s, color c, int sz = 9, bool bold = false, ENUM_ANCHOR_POINT an = ANCHOR_LEFT_UPPER, string font = "")
{
   string n = P + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + gOY + y);
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, font != "" ? font : bold ? "Tahoma Bold" : "Tahoma");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz); ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetInteger(0, n, OBJPROP_ANCHOR, an);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
// ข้อความเรืองแสง: เงาสีเข้มซ้อนหลังข้อความหลัก
void GlowText(string id, int x, int y, string s, color c, color glow, int sz, string font = "Arial Black")
{
   Text(id + "_g1", x + 2, y + 2, s, glow, sz, true, ANCHOR_LEFT_UPPER, font);
   Text(id + "_g2", x - 1, y - 1, s, C_GLOW1, sz, true, ANCHOR_LEFT_UPPER, font);
   Text(id, x, y, s, c, sz, true, ANCHOR_LEFT_UPPER, font);
}
void Button(string id, int x, int y, int w, int h, string s, bool on, color onc, int fs = 8)
{
   string n = P + "B_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + gOY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, on ? "Tahoma Bold" : "Tahoma"); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? onc : C_DEEP); ObjectSetInteger(0, n, OBJPROP_COLOR, on ? C_VOID : C_TXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, on ? onc : C_OFF); ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
// กรอบนีออน 3 ชั้น
void NeonFrame(string id, int x, int y, int w, int h, color c)
{
   Rect(id + "_o", x - 3, y - 3, w + 6, h + 6, C_VOID, C_GLOW1, 1);
   Rect(id + "_m", x - 1, y - 1, w + 2, h + 2, C_VOID, c == C_OFF ? C_OFF : C_GLOW2, 1);
   Rect(id, x, y, w, h, C_PANEL, c, 2);
}
color RiskColor(int k) { return k == 0 ? C_GREEN : k == 1 ? C'120,255,90' : k == 2 ? C_GOLD : k == 3 ? C_ORANGE : C_RED; }
color DDColor(double dd) { return dd < 25 ? C_GREEN : dd < 45 ? C_GOLD : dd < 60 ? C_ORANGE : C_RED; }
color Mix(color a, color b, double t)
{
   int ia = (int)a, ib = (int)b;
   int ra = ia & 0xFF, ga = (ia >> 8) & 0xFF, ba = (ia >> 16) & 0xFF;
   int rb = ib & 0xFF, gb = (ib >> 8) & 0xFF, bb = (ib >> 16) & 0xFF;
   return (color)((int)(ra + (rb - ra) * t) | ((int)(ga + (gb - ga) * t) << 8) | ((int)(ba + (bb - ba) * t) << 16));
}

//====================================================================
// องค์ประกอบยานแม่
//====================================================================
const int W = 600, H = 802;
int  starX[70], starY[70], starB[70];
void InitStars()
{
   MathSrand(7);
   for(int i = 0; i < 70; i++) { starX[i] = 6 + MathRand() % (W - 12); starY[i] = 6 + MathRand() % (H - 12); starB[i] = MathRand() % 3; }
}
void Stars()
{
   for(int i = 0; i < 70; i++)
   {
      int ph = (gFrame + i * 7) % 12;
      color c = !InpAnimate ? C_MUTED : ph < 2 ? C'255,255,255' : ph < 6 ? C'110,120,170' : C'45,50,85';
      int s = starB[i] == 2 && ph < 2 ? 2 : 1;
      Rect("star" + IntegerToString(i), starX[i], starY[i], s, s, c);
   }
}
// UFO: โดม + จานบิน + ไฟวิ่ง + ลำแสง
void UFO(int x, int y, color st)
{
   Rect("u_beam1", x + 22, y + 34, 22, 6, Mix(C_VOID, C_ALIEN, 0.25));
   Rect("u_beam2", x + 16, y + 40, 34, 6, Mix(C_VOID, C_ALIEN, 0.15));
   Rect("u_beam3", x + 10, y + 46, 46, 6, Mix(C_VOID, C_ALIEN, 0.08));
   Rect("u_dome", x + 20, y + 2, 26, 16, Mix(C_VOID, C_GLOW3, 0.35), C_GLOW3, 1);
   Rect("u_eye1", x + 26, y + 8, 5, 5, C_ALIEN); Rect("u_eye2", x + 35, y + 8, 5, 5, C_ALIEN);
   Rect("u_body", x, y + 18, 66, 12, C_DEEP, C_GLOW2, 2);
   Rect("u_rim", x + 8, y + 30, 50, 5, C_GLOW1, C_GLOW2, 1);
   for(int i = 0; i < 6; i++)
   {
      bool lit = !InpAnimate || (gFrame + i) % 6 < 2;
      Rect("u_l" + IntegerToString(i), x + 6 + i * 10, y + 22, 5, 4, lit ? st : C_OFF);
   }
}
// เส้นสแกนวิ่งข้ามหัวแดชบอร์ด
void Scanner(int y)
{
   int span = W - 20, pos = InpAnimate ? (gFrame * 23) % span : span / 2;
   Rect("scan_bg", 10, y, span, 2, C_DEEP);
   Rect("scan_t3", 10 + MathMax(0, pos - 60), y, 60, 2, Mix(C_DEEP, C_GLOW3, 0.25));
   Rect("scan_t2", 10 + MathMax(0, pos - 25), y, 25, 2, Mix(C_DEEP, C_GLOW3, 0.6));
   Rect("scan_h",  10 + pos, y - 1, 6, 4, C_GLOW3);
}
// แท่งพลังงาน: เต็ม = กำไรลอย +2R, ว่าง = -1R (ชน SL)
void EnergyBar(string id, int x, int y, int w, double rr, color c)
{
   Rect(id + "_bg", x, y, w, 8, C_VOID, C_OFF);
   double t = MathMax(0, MathMin(1, (rr + 1) / 3.0));
   Rect(id + "_fg", x + 1, y + 1, (int)MathMax(1, (w - 2) * t), 6, rr >= 0 ? c : C_RED);
   Rect(id + "_z", x + (w - 2) / 3, y - 2, 1, 12, C_MUTED);      // จุด 0R (ทุนคืน)
}
// เกจ DD แบบแบ่งช่อง
void DDGauge(int x, int y, int w, double dd)
{
   int seg = 30, gw = (w - (seg - 1) * 2) / seg;
   for(int i = 0; i < seg; i++)
   {
      double lvl = (i + 1) * InpDDHalt / seg;
      color c = dd >= lvl - InpDDHalt / seg ? DDColor(lvl) : C'24,27,55';
      Rect("ddg" + IntegerToString(i), x + i * (gw + 2), y, gw, 14, c);
   }
}

//====================================================================
// ธีมกราฟ + วาดไม้บนกราฟ
//====================================================================
void SaveChart()
{
   oBG = ChartGetInteger(0, CHART_COLOR_BACKGROUND); oFG = ChartGetInteger(0, CHART_COLOR_FOREGROUND); oGrid = ChartGetInteger(0, CHART_COLOR_GRID);
   oUp = ChartGetInteger(0, CHART_COLOR_CHART_UP); oDn = ChartGetInteger(0, CHART_COLOR_CHART_DOWN); oBull = ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   oBear = ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR); oLine = ChartGetInteger(0, CHART_COLOR_CHART_LINE); oVol = ChartGetInteger(0, CHART_COLOR_VOLUME);
   oAsk = ChartGetInteger(0, CHART_COLOR_ASK); oBid = ChartGetInteger(0, CHART_COLOR_BID); oShowGrid = ChartGetInteger(0, CHART_SHOW_GRID); oMode = ChartGetInteger(0, CHART_MODE);
}
void SpaceChart()
{
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, C_VOID);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, C'130,140,200');
   ChartSetInteger(0, CHART_COLOR_GRID, C'22,24,50');
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, C'0,255,200');      // ไส้เทียน/ขอบ ขาขึ้น: นีออนเขียวฟ้า
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, C'0,120,110');   // ตัวเทียนขาขึ้น: เขียวฟ้าเข้ม (ดูเรืองแสงจากขอบ)
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, C'255,40,170');   // ไส้เทียน/ขอบ ขาลง: นีออนชมพู
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, C'110,0,80');    // ตัวเทียนขาลง: ม่วงชมพูเข้ม
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, C'255,205,60');
   ChartSetInteger(0, CHART_COLOR_VOLUME, C'120,60,255');
   ChartSetInteger(0, CHART_COLOR_ASK, C'255,90,90');
   ChartSetInteger(0, CHART_COLOR_BID, C'255,205,60');
   ChartRedraw();
}
void RestoreChart()
{
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, oBG); ChartSetInteger(0, CHART_COLOR_FOREGROUND, oFG); ChartSetInteger(0, CHART_COLOR_GRID, oGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, oUp); ChartSetInteger(0, CHART_COLOR_CHART_DOWN, oDn); ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, oBull);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, oBear); ChartSetInteger(0, CHART_COLOR_CHART_LINE, oLine); ChartSetInteger(0, CHART_COLOR_VOLUME, oVol);
   ChartSetInteger(0, CHART_COLOR_ASK, oAsk); ChartSetInteger(0, CHART_COLOR_BID, oBid); ChartSetInteger(0, CHART_SHOW_GRID, oShowGrid); ChartSetInteger(0, CHART_MODE, oMode);
}
string TP = "XQTT_";     // วัตถุบนกราฟราคา (ลบเมื่อถอด EA)
void DrawEntryArrow(int k, int dir, double price)
{
   if(!InpDrawTrades) return;
   string n = TP + "arr_" + IntegerToString(k) + "_" + IntegerToString((long)TimeCurrent());
   ObjectCreate(0, n, OBJ_ARROW, 0, TimeCurrent(), price);
   ObjectSetInteger(0, n, OBJPROP_ARROWCODE, dir > 0 ? 233 : 234);
   ObjectSetInteger(0, n, OBJPROP_COLOR, C_ENG[k]); ObjectSetInteger(0, n, OBJPROP_WIDTH, 3);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, dir > 0 ? ANCHOR_TOP : ANCHOR_BOTTOM);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   ObjectSetString(0, n, OBJPROP_TOOLTIP, "QUARTET " + E[k].name + (dir > 0 ? " BUY" : " SELL"));
}
void DrawSLLines()
{
   for(int k = 0; k < NENG; k++)
   {
      string n = TP + "sl_" + IntegerToString(k), lb = TP + "sllb_" + IntegerToString(k);
      ulong t = EngineTicket(E[k].magic);
      if(!InpDrawTrades || t == 0 || !PositionSelectByTicket(t)) { ObjectDelete(0, n); ObjectDelete(0, lb); continue; }
      double sl = PositionGetDouble(POSITION_SL);
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_HLINE, 0, 0, sl);
      ObjectSetDouble(0, n, OBJPROP_PRICE, sl); ObjectSetInteger(0, n, OBJPROP_COLOR, C_ENG[k]);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      if(ObjectFind(0, lb) < 0) ObjectCreate(0, lb, OBJ_TEXT, 0, TimeCurrent(), sl);
      ObjectMove(0, lb, 0, TimeCurrent() + PeriodSeconds() * 3, sl);
      ObjectSetString(0, lb, OBJPROP_TEXT, "◆ SL " + E[k].name); ObjectSetString(0, lb, OBJPROP_FONT, "Tahoma Bold");
      ObjectSetInteger(0, lb, OBJPROP_FONTSIZE, 8); ObjectSetInteger(0, lb, OBJPROP_COLOR, C_ENG[k]); ObjectSetInteger(0, lb, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
      ObjectSetInteger(0, lb, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, lb, OBJPROP_HIDDEN, true);
   }
}

//====================================================================
// คำสั่งเทรด
//====================================================================
string LotModeName(int m)
{
   return m == LOT_RISK_EQUITY ? "อัตโนมัติ % Equity" : m == LOT_RISK_BALANCE ? "อัตโนมัติ % Balance" : m == LOT_RISK_MONEY ? "เสี่ยงเงินคงที่" :
          m == LOT_PER_STEP ? "ล็อตตามขนาดทุน" : "ล็อตคงที่";
}
string LotModeDetail(int m)
{
   string cmp = InpCompound ? "ทบต้น" : StringFormat("ไม่ทบต้น (ฐาน %.0f)", gBase);
   if(m == LOT_RISK_EQUITY || m == LOT_RISK_BALANCE) return StringFormat("เสี่ยง %.2g%% ต่อไม้ · %s", RiskPct(), cmp);
   if(m == LOT_RISK_MONEY) return StringFormat("เสี่ยง %.2f %s ต่อไม้ (ไม่ขึ้นกับระดับ %%)", InpRiskMoney, AccountInfoString(ACCOUNT_CURRENCY));
   if(m == LOT_PER_STEP)   return StringFormat("%.2f lot ต่อทุกๆ %.0f %s · %s", InpStepLot, InpStepMoney, AccountInfoString(ACCOUNT_CURRENCY), cmp);
   return StringFormat("%.2f lot ทุกไม้ (ไม่ขึ้นกับ SL)", InpFixedLot);
}
double EngineMult(int k) { return k == 0 ? InpMultKST : k == 1 ? InpMultCoral : k == 2 ? InpMultGann : InpMultSSL; }
double PerLotLoss(double dist)               // เงินที่เสียต่อ 1.0 lot เมื่อชน SL
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return tv > 0 && ts > 0 && dist > 0 ? dist / ts * tv : 0;
}
double OpenRiskPct()                          // ความเสี่ยงรวม (% equity) ของไม้ QUARTET ที่เปิดอยู่
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), r = 0;
   for(int k = 0; k < NENG; k++)
   {
      ulong t = EngineTicket(E[k].magic);
      if(t == 0 || !PositionSelectByTicket(t)) continue;
      double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
      bool buy = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
      double d = buy ? op - sl : sl - op;     // ติดลบ = SL ล็อกกำไรแล้ว
      if(sl > 0 && d > 0) r += PerLotLoss(d) * PositionGetDouble(POSITION_VOLUME);
   }
   return eq > 0 ? r / eq * 100 : 0;
}
// คำนวณล็อต: คืน 0 = ข้ามไม้ (เหตุผลใน why)
double CalcLots(int k, double dist, string &why, double &riskReal)
{
   why = ""; riskReal = 0;
   double perLot = PerLotLoss(dist);
   if(perLot <= 0) { why = "ข้อมูลสัญญาไม่พร้อม"; return 0; }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0) step = 0.01;
   double raw = 0;
   switch(gLotMode)
   {
      case LOT_RISK_EQUITY:  raw = (InpCompound ? eq  : gBase) * RiskPct() / 100.0 / perLot; break;
      case LOT_RISK_BALANCE: raw = (InpCompound ? bal : gBase) * RiskPct() / 100.0 / perLot; break;
      case LOT_RISK_MONEY:   raw = InpRiskMoney / perLot; break;
      case LOT_PER_STEP:     raw = InpStepMoney > 0 ? MathFloor((InpCompound ? bal : gBase) / InpStepMoney) * InpStepLot : 0; break;
      default:               raw = InpFixedLot;
   }
   raw *= EngineMult(k);
   double dd = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   if(InpDDReduceAt > 0 && dd >= InpDDReduceAt) raw *= InpDDReduceMult;
   if(InpMaxLot > 0) raw = MathMin(raw, InpMaxLot);
   raw = MathMin(raw, vmax);
   double lots = MathFloor(raw / step + 1e-9) * step;
   if(lots < vmin)
   {
      double rp = eq > 0 ? vmin * perLot / eq * 100.0 : 999;
      if(InpMinLotRule == MINLOT_SKIP || (InpMinLotRule == MINLOT_CAP && rp > InpMinLotCap))
      { why = StringFormat("ล็อตต่ำกว่าขั้นต่ำ (0.01 เสี่ยง %.1f%%)", rp); return 0; }
      lots = vmin;
   }
   riskReal = eq > 0 ? lots * perLot / eq * 100.0 : 0;
   if(InpMaxTotalRisk > 0 && OpenRiskPct() + riskReal > InpMaxTotalRisk)
   { why = StringFormat("ความเสี่ยงรวมจะเกิน %.1f%%", InpMaxTotalRisk); return 0; }
   return NormalizeDouble(lots, 2);
}
void OpenEngine(int k, int dir)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), spread = ask - bid;
   if(spread > InpMaxSpreadUSD) { E[k].note = "ข้าม: spread กว้าง"; return; }
   double entry = dir > 0 ? ask : bid, dist = InpSLATR * E[k].atr;
   double sl = NormalizeDouble(entry - dir * dist, _Digits);
   string why; double riskReal;
   double lots = CalcLots(k, dist, why, riskReal);
   if(lots <= 0) { E[k].note = "ข้าม: " + why; return; }
   trade.SetExpertMagicNumber(E[k].magic);
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "QUARTET " + E[k].name) : trade.Sell(lots, _Symbol, 0, sl, 0, "QUARTET " + E[k].name);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      E[k].note = (dir > 0 ? "ปล่อยยาน BUY " : "ปล่อยยาน SELL ") + DoubleToString(lots, 2) + " lot";
      DrawEntryArrow(k, dir, trade.ResultPrice() > 0 ? trade.ResultPrice() : entry);
      LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%s,%.2f,", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), dir, lots,
              DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
              DoubleToString(sl, _Digits), E[k].name, riskReal));
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
         sLast[nl++] = StringFormat("%s  %-5s %s  %+.2f", TimeToString(t, TIME_DATE | TIME_MINUTES), E[(int)(mg - InpMagic)].name, ty == DEAL_TYPE_SELL ? "BUY " : "SELL", p);
      }
   }
}

//====================================================================
// แดชบอร์ดยานแม่
//====================================================================
string NextLotText(int k)
{
   string why; double rr;
   double l = CalcLots(k, InpSLATR * E[k].atr, why, rr);
   return l > 0 ? StringFormat("  ·  ล็อตถัดไป %.2f (%.1f%%)", l, rr) : "  ·  ไม้ถัดไป: ข้าม";
}
void DrawPanel()
{
   gOY = 0;
   bool   cent = IsCent(); string cur = AccountInfoString(ACCOUNT_CURRENCY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   color  sc  = gHalted ? C_RED : gPaused ? C_ORANGE : C_GREEN;
   string stat = gHalted ? "ยานจอด: DD ถึงเพดาน" : gPaused ? "ลอยนิ่ง (หยุดชั่วคราว)" : "ยานแม่ออนไลน์";
   bool   pulse = InpAnimate && gFrame % 2 == 0;

   // ฉากหลัง + กรอบนีออน + ดาว
   Rect("bg_o", -4, -4, W + 8, H + 8, C_VOID, C_GLOW1, 1);
   Rect("bg_m", -2, -2, W + 4, H + 4, C_VOID, C_GLOW2, 1);
   Rect("bg", 0, 0, W, H, C_VOID, pulse ? C_GLOW3 : C_GLOW2, 2);
   Stars();
   // มุมเป้าเล็งสี่มุม
   int cx[4] = {4, 576, 4, 576}, cy[4] = {4, 4, 794, 794};
   for(int i = 0; i < 4; i++) { Rect("cnh" + IntegerToString(i), cx[i], cy[i], 20, 2, C_GLOW3); Rect("cnv" + IntegerToString(i), i % 2 == 0 ? cx[i] : cx[i] + 18, i < 2 ? cy[i] : cy[i] - 16, 2, 18, C_GLOW3); }

   // หัว
   UFO(18, 12, sc);
   GlowText("title", 98, 10, "XAU QUARTET", C_GOLD, C'110,60,0', 20);
   Text("sub", 100, 44, "MOTHERSHIP EDITION · v1.10 · สัญญาณจากนอกโลก 4 ดวง", C_GLOW3, 8, true);
   Text("sub2", 100, 60, "KST · CORAL · GANN · SSL-H4", C_MUTED, 7, false, ANCHOR_LEFT_UPPER, "Consolas");
   NeonFrame("stat", 420, 14, 165, 28, sc);
   Text("stat_t", 502, 20, (pulse ? "● " : "○ ") + stat, sc, 8, true, ANCHOR_UPPER);
   Text("acct", 420, 50, (cent ? "บัญชี CENT · " : "บัญชี STANDARD · ") + cur + (cent ? "  OK" : "  ! แนะนำ Cent"), cent ? C_GREEN : C_ORANGE, 8, true);
   Text("clock", 420, 64, "เวลายาน " + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), C_MUTED, 7, false, ANCHOR_LEFT_UPPER, "Consolas");
   Scanner(84);

   // ความเสี่ยง
   Text("l_risk", 14, 94, "พลังขับเคลื่อน (เสี่ยง/ไม้)", C_MUTED, 8, true);
   for(int k = 0; k < NRISK; k++)
      Button("r" + IntegerToString(k), 14 + k * 115, 110, 110, 28, StringFormat("%s %.2g%%", k == 4 ? "!!" : k == 3 ? "▲" : "●", RiskOf(k)), gRisk == k, RiskColor(k), 9);
   int bdd = BtDD(gRisk);
   bool pctMode = gLotMode == LOT_RISK_EQUITY || gLotMode == LOT_RISK_BALANCE;
   string halt50 = InpDDHalt < 54 && gRisk >= 3 ? "  !! เพดาน " + DoubleToString(InpDDHalt, 0) + "% แบ็กเทสชนเพดานหยุด" : "";
   if(pctMode)
      Text("bt", 14, 144, StringFormat("ทดสอบ 2 ปี: $300 → %s · DD %d%% · โอกาสชน DD 70%% ≈ %d%%", BtEnd(gRisk), bdd, BtRuin(gRisk)) + halt50 +
           (InpCompound ? "" : " · (ผลแบ็กเทสเป็นแบบทบต้น)"), DDColor(bdd), 8, true);
   else
      Text("bt", 14, 144, "ระดับ % ไม่ใช้ในโหมดล็อตนี้ · ผลแบ็กเทสอ้างอิงโหมด % Equity", C_MUTED, 8, true);

   // โหมดล็อต
   Text("l_lot", 14, 164, "โหมดล็อต", C_MUTED, 8, true);
   for(int m = 0; m < NLOTMODE; m++)
   {
      string lb[NLOTMODE] = {"%Equity", "%Balance", "เงินคงที่", "ตามทุน", "คงที่"};
      Button("lm" + IntegerToString(m), 80 + m * 102, 160, 98, 22, lb[m], gLotMode == m, C_GLOW3, 8);
   }
   Text("lotd", 14, 186, "► " + LotModeName(gLotMode) + ": " + LotModeDetail(gLotMode) +
        (InpDDReduceAt > 0 ? StringFormat(" · DD>=%.0f%% ลดล็อต x%.2g", InpDDReduceAt, InpDDReduceMult) : "") +
        (InpMaxTotalRisk > 0 ? StringFormat(" · เสี่ยงรวม<=%.1f%%", InpMaxTotalRisk) : ""), C_GLOW3, 8);
   gOY = 42;
   // ห้องควบคุมบัญชี
   NeonFrame("acc", 10, 166, W - 20, 118, C_GLOW2);
   Text("acc_h", 22, 172, "■ ห้องควบคุม", C_GLOW3, 8, true);
   Text("a1", 22, 190, "ทุน (BALANCE)", C_MUTED, 7);         Text("a1v", 22, 202, StringFormat("%.2f", bal), C_TXT, 13, true);
   Text("a2", 210, 190, "มูลค่าสุทธิ (EQUITY)", C_MUTED, 7);  Text("a2v", 210, 202, StringFormat("%.2f", eq), eq >= bal ? C_GREEN : C_RED, 13, true);
   Text("a3", 400, 190, cent ? "เทียบเป็น USD" : "กำไรลอย", C_MUTED, 7);
   Text("a3v", 400, 202, cent ? StringFormat("$%.2f", eq * 0.01) : StringFormat("%+.2f", eq - bal), C_GOLD, 13, true);
   Text("a4", 22, 228, StringFormat("วันนี้ %+.2f", sToday), sToday >= 0 ? C_GREEN : C_RED, 9, true);
   Text("a5", 210, 228, StringFormat("เดือนนี้ %+.2f", sMonth), sMonth >= 0 ? C_GREEN : C_RED, 9, true);
   Text("a6", 400, 228, StringFormat("จุดสูงสุด %.2f", gPeak), C_MUTED, 8);
   Text("dd_l", 22, 252, StringFormat("โล่ป้องกัน DD %.1f%%", dd), DDColor(dd), 8, true);
   DDGauge(160, 252, 410, dd);
   Text("dd_m", 570, 268, StringFormat("เพดาน %.0f%%", InpDDHalt), C_MUTED, 7, false, ANCHOR_RIGHT_UPPER);

   // ห้องเครื่อง 2 x 2
   Text("l_eng", 14, 294, "■ ห้องเครื่องยนต์ — กดปุ่มที่การ์ดเพื่อ เปิด/ปิด", C_GLOW3, 8, true);
   for(int k = 0; k < NENG; k++)
   {
      int x = 12 + (k % 2) * 292, y = 314 + (k / 2) * 140;
      ulong t = EngineTicket(E[k].magic); int pd = 0; double pp = 0, pl = 0, rr = 0;
      if(t > 0 && PositionSelectByTicket(t))
      {
         pd = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; pp = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         pl = PositionGetDouble(POSITION_VOLUME);
         double op = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL), cp = PositionGetDouble(POSITION_PRICE_CURRENT);
         if(MathAbs(op - sl) > 0) rr = pd * (cp - op) / MathAbs(op - sl);
      }
      color ec = !E[k].on ? C_OFF : pd > 0 ? C_GREEN : pd < 0 ? C_RED : C_ENG[k];
      string id = "e" + IntegerToString(k);
      NeonFrame(id, x, y, 284, 130, ec);
      Rect(id + "_bar", x + 2, y + 2, 6, 126, E[k].on ? (pulse && pd != 0 ? C_TXT : C_ENG[k]) : C_OFF);
      Text(id + "_no", x + 16, y + 6, "POD-0" + IntegerToString(k + 1), C_MUTED, 7, false, ANCHOR_LEFT_UPPER, "Consolas");
      Text(id + "n", x + 16, y + 18, E[k].name + " · " + E[k].nick, E[k].on ? C_ENG[k] : C_MUTED, 11, true);
      Button("t" + IntegerToString(k), x + 216, y + 8, 60, 22, E[k].on ? "● ON" : "○ OFF", E[k].on, C_ENG[k]);
      Text(id + "s", x + 16, y + 42, !E[k].on ? "ดับเครื่อง (ไม่เปิดไม้ใหม่)" : pd > 0 ? "▲ ถือ BUY" : pd < 0 ? "▼ ถือ SELL" : "○ สแกนหาสัญญาณกลับทิศ", ec, 11, true);
      Text(id + "p", x + 16, y + 64, pd != 0 ? StringFormat("%.2f lot  %+.2f  (%+.2fR)", pl, pp, rr) : " ", pp >= 0 ? C_GREEN : C_RED, 9, true);
      if(pd != 0) EnergyBar(id + "_en", x + 16, y + 82, 256, rr, C_ENG[k]);
      else { EnergyBar(id + "_en", x + 16, y + 82, 256, -1, C_OFF); }
      Text(id + "t", x + 16, y + 96, "สัญญาณ " + (E[k].state > 0 ? "ขาขึ้น ▲" : E[k].state < 0 ? "ขาลง ▼" : "-") + StringFormat("  ·  SL %.1f$", InpSLATR * E[k].atr) + NextLotText(k), C_TXT, 8);
      Text(id + "d", x + 16, y + 110, E[k].note != "" ? E[k].note : E[k].desc, C_MUTED, 7);
   }

   // สถิติ + บันทึกการบิน
   NeonFrame("st", 12, 600, 246, 108, C_GLOW2);
   double wr = sTrades > 0 ? 100.0 * sWins / sTrades : 0, pf = sGrossL > 0 ? sGrossW / sGrossL : 0;
   Text("st0", 24, 606, "■ สถิติภารกิจ", C_GLOW3, 8, true);
   Text("st1", 24, 624, StringFormat("ไม้ที่ปิด %d · ชนะ %.0f%%", sTrades, wr), C_TXT, 9);
   Text("st2", 24, 642, StringFormat("Profit Factor %.2f  (เป้า > 1.3)", pf), pf >= 1.3 ? C_GREEN : pf >= 1.0 ? C_GOLD : C_RED, 9, true);
   Text("st3", 24, 660, StringFormat("กำไรสุทธิ %+.2f", sGrossW - sGrossL), sGrossW >= sGrossL ? C_GREEN : C_RED, 10, true);
   Text("st4", 24, 684, "ชนะ 30-40% · แพ้ติดกันเป็นปกติของระบบเทรนด์", C_MUTED, 7);
   NeonFrame("lt", 268, 600, 320, 108, C_GLOW2);
   Text("lt0", 280, 606, "■ บันทึกการบิน (5 ไม้ล่าสุด)", C_GLOW3, 8, true);
   for(int i = 0; i < 5; i++)
   {
      bool pos = StringFind(sLast[i], "+") >= 0;
      Text("lt" + IntegerToString(i + 1), 280, 624 + i * 16, sLast[i] == "" ? "· · ·" : sLast[i], sLast[i] == "" ? C_OFF : pos ? C_GREEN : C_RED, 7, false, ANCHOR_LEFT_UPPER, "Consolas");
   }
   Button("pause", 12, 718, 284, 32, gPaused ? "▶ ออกบินต่อ" : "|| ลอยนิ่ง (หยุดเปิดไม้ใหม่)", gPaused, C_ORANGE, 9);
   Button("close", 304, 718, 284, 32, "X ดีดตัวออก: ปิดทุกไม้", false, C_RED, 9);
   gOY = 0;
   ChartRedraw();
}

//====================================================================
// ระบบหลัก
//====================================================================
void InitEngine(int k, string name, string nick, string desc, ENUM_TIMEFRAMES tf, bool on)
{
   E[k].name = name; E[k].nick = nick; E[k].desc = desc; E[k].tf = tf; E[k].magic = InpMagic + k;
   E[k].state = 0; E[k].atr = 0; E[k].lastBar = 0; E[k].lastFlip = 0; E[k].note = ""; E[k].ready = false;
   string g = gPfx + "on" + IntegerToString(k);
   E[k].on = GlobalVariableCheck(g) ? GlobalVariableGet(g) > 0 : on;
}
int OnInit()
{
   gPfx = "XQT_" + IntegerToString(InpMagic) + "_";
   InitEngine(0, "KST",   "นักวัดแรง", "KST 10/15/20/30 vs SMA9 · H1 · ~26 ไม้/เดือน", PERIOD_H1, InpUseKST);
   InitEngine(1, "Coral", "สายน้ำ",   StringFormat("Coral %d / %.1f ความชัน · H1 · ~22 ไม้/เดือน", InpCoralLen, InpCoralCd), PERIOD_H1, InpUseCoral);
   InitEngine(2, "Gann",  "ขั้นบันได", StringFormat("Gann HiLo %d/%d · H1 · ~30 ไม้/เดือน", InpGannHi, InpGannLo), PERIOD_H1, InpUseGann);
   InitEngine(3, "SSL",   "ยานแม่ H4", StringFormat("SSL HMA%d · H4 · ~7 ไม้/เดือน", InpSSLLen), PERIOD_H4, InpUseSSL);
   int r0  = GlobalVariableCheck(gPfx + "risk5") ? (int)GlobalVariableGet(gPfx + "risk5") : InpRiskLevel;
   gRisk   = MathMax(0, MathMin(NRISK - 1, r0));
   gLotMode = GlobalVariableCheck(gPfx + "lotmode") ? (int)GlobalVariableGet(gPfx + "lotmode") : (int)InpLotMode;
   gLotMode = MathMax(0, MathMin(NLOTMODE - 1, gLotMode));
   if(InpBaseCapital > 0) gBase = InpBaseCapital;
   else if(GlobalVariableCheck(gPfx + "base")) gBase = GlobalVariableGet(gPfx + "base");
   else { gBase = AccountInfoDouble(ACCOUNT_BALANCE); GlobalVariableSet(gPfx + "base", gBase); }
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
   SaveChart();
   if(InpSpaceChart) SpaceChart();
   InitStars();
   EventSetMillisecondTimer(500);
   UpdateStats(); DrawPanel();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, P);
   if(reason == REASON_REMOVE || reason == REASON_CHARTCLOSE || reason == REASON_PROGRAM)
   {
      ObjectsDeleteAll(0, TP);
      if(InpSpaceChart) RestoreChart();
   }
   ChartRedraw();
}

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
      ulong t = EngineTicket(E[k].magic);
      if(t > 0) trade.PositionClose(t);
      E[k].lastFlip = TimeCurrent();
      E[k].note = E[k].state > 0 ? "รับสัญญาณ: กลับเป็นขาขึ้น" : "รับสัญญาณ: กลับเป็นขาลง";
      if(gHalted || gPaused || !E[k].on) continue;
      OpenEngine(k, E[k].state);
   }
}

void OnTimer()
{
   gFrame++;
   if(gFrame % 4 == 0) UpdateStats();       // ทุก 2 วินาที
   DrawSLLines();
   DrawPanel();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, P + "B_") != 0) return;
   string b = StringSubstr(sparam, StringLen(P + "B_"));
   if(StringSubstr(b, 0, 2) == "lm") { gLotMode = (int)MathMax(0, MathMin(NLOTMODE - 1, StringToInteger(StringSubstr(b, 2)))); GlobalVariableSet(gPfx + "lotmode", gLotMode); }
   else if(StringSubstr(b, 0, 1) == "r") gRisk = (int)MathMax(0, MathMin(NRISK - 1, StringToInteger(StringSubstr(b, 1))));
   else if(StringSubstr(b, 0, 1) == "t")
   {
      int k = (int)StringToInteger(StringSubstr(b, 1));
      if(k >= 0 && k < NENG) { E[k].on = !E[k].on; GlobalVariableSet(gPfx + "on" + IntegerToString(k), E[k].on ? 1 : 0); }
   }
   else if(b == "pause") { gPaused = !gPaused; GlobalVariableSet(gPfx + "pause", gPaused ? 1 : 0); }
   else if(b == "close")
   {
      if(MessageBox("ดีดตัวออก: ปิดทุกไม้ของ XAU QUARTET ตอนนี้?", "ยืนยัน", MB_YESNO | MB_ICONQUESTION) == IDYES) CloseAll();
   }
   GlobalVariableSet(gPfx + "risk5", gRisk);
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
