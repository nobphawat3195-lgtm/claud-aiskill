//+------------------------------------------------------------------+
//|  XAU SENTINEL v1.10 — หุ่นยนต์ยามเฝ้าทองคำ (SSL + MACD, 5 เครื่องยนต์) |
//|                                                                  |
//|  ติดตั้งกราฟ XAUUSD กราฟเดียว (TF ใดก็ได้) EA คำนวณ M5/M15/H1 เอง    |
//|                                                                  |
//|  LOGIC (SSL channel จาก SSL Hybrid ของ Mihkel00, ปรับจากงานวิจัย):   |
//|   เส้นบน = HMA(High, N), เส้นล่าง = HMA(Low, N) บนแท่งที่ปิดแล้ว      |
//|   ราคาปิด > เส้นบน  -> สถานะ BUY | ราคาปิด < เส้นล่าง -> สถานะ SELL  |
//|   สถานะเปลี่ยน -> ปิดไม้เดิมของเครื่องยนต์นั้น แล้วเปิดไม้ทางใหม่       |
//|   (เครื่องยนต์ที่ใช้ตัวกรอง D1: เปิดเฉพาะทางเดียวกับ D1 close vs EMA20) |
//|   SL = 1.5 x ATR(14) ของ TF นั้น, ไม่มี TP — ถือจนสัญญาณกลับทิศ       |
//|                                                                  |
//|  เครื่องยนต์: H1 HMA60 (ไม่กรอง) | M15 HMA320 +D1 | M5 HMA960 +D1   |
//|  v1.10 เพิ่ม MACD (ฮิสโตแกรม 12/26/9 x (60 นาที/TF), กลับทิศเมื่อเปลี่ยนเครื่องหมาย) |
//|   MACD H1 12/26/9 | MACD M15 48/104/36 (ไม่กรอง D1), SL 1.5 ATR, ไม่มี TP   |
//|  โหมด: มาตรฐาน = SSL M15+H1 (~47 ไม้/เดือน) | ไม้เยอะ = SSL M5+M15+H1 (~84) |
//|        เทอร์โบ = SSL M15+H1 + MACD H1+M15 (~120 ไม้/เดือน)               |
//|  ความเสี่ยง/ไม้: ต่ำ 0.5% | กลาง 0.75% | สูง 1% | สูงสุด 1.5%         |
//|                                                                  |
//|  แบ็กเทส real tick Dukascopy พ.ย.25-พ.ย.26 (Cent USD 300):          |
//|   มาตรฐาน : 0.5% DD17% | 0.75% $1,443 DD24% | 1% $2,232 DD31% | 1.5% DD43% |
//|   ไม้เยอะ : 0.5% $1,650 DD33% | 0.75% $3,026 DD46% | 1%,1.5% ชน DD50% หยุด |
//|   เทอร์โบ : 0.25% $815 DD17% | 0.5% $1,854 DD32% | 0.75% $3,616 DD46% | 1%+ หยุด |
//|   เทอร์โบ หัก slippage 0.10$: 0.5% $1,726 | 0.75% $3,260                 |
//|   slippage 0.10$/ด้าน: มาตรฐาน 0.75% $1,371 | ไม้เยอะ 0.75% $2,643       |
//|   Standard USD 300 0.75%: ข้ามไม้จำนวนมาก แล้วชน DD 50% หยุด            |
//|   ค่าพารามิเตอร์เลือกจากปีเดียวกัน ผลจริงคาดว่าต่ำกว่านี้ ยังไม่หัก swap  |
//|   อัตราชนะ 15-33% แพ้ติดกัน 10-25 ไม้เป็นเรื่องปกติของระบบตามเทรนด์    |
//|                                                                  |
//|  บัญชี: Cent แนะนำ | Standard: ถ้า 0.01 lot เสี่ยงเกิน InpMinLotCap   |
//|  จะข้ามไม้ (ทุน $300 Standard จะเข้าได้น้อยมาก)                     |
//|  ยังไม่ได้คอมไพล์/ทดสอบใน MT5 — ทดสอบ Strategy Tester + demo ก่อน     |
//+------------------------------------------------------------------+
#property copyright "XAU SENTINEL"
#property version   "1.10"
#property strict
#include <Trade\Trade.mqh>

enum ENUM_SENT_MODE { MODE_STANDARD = 0, MODE_HIGHFREQ = 1, MODE_TURBO = 2 };   // มาตรฐาน / ไม้เยอะ / เทอร์โบ
enum ENUM_SENT_RISK { RISK_LOW = 0, RISK_MID = 1, RISK_HIGH = 2, RISK_MAX = 3 };

input group "=== โหมดเริ่มต้น (เปลี่ยนได้จากแดชบอร์ด) ==="
input ENUM_SENT_MODE InpMode = MODE_STANDARD;   // โหมด
input ENUM_SENT_RISK InpRisk = RISK_MID;        // ระดับความเสี่ยง
input group "=== ความเสี่ยง % ต่อไม้ ==="
input double InpRiskLow  = 0.5;    // เสี่ยงต่ำ
input double InpRiskMid  = 0.75;   // เสี่ยงกลาง
input double InpRiskHigh = 1.0;    // เสี่ยงสูง
input double InpRiskMax  = 1.5;    // เสี่ยงสูงสุด
input double InpMinLotCap = 5.5;   // ถ้าต้องใช้ lot ขั้นต่ำ: เข้าเฉพาะเมื่อเสี่ยงจริง <= % นี้
input double InpDDHalt    = 50.0;  // DD จากจุดสูงสุด (%) หยุดเปิดไม้ใหม่และปิดทุกไม้
input double InpMaxSpreadUSD = 1.5;
input group "=== เครื่องยนต์ (ค่าจากงานวิจัย) ==="
input int    InpH1Len  = 60;       // H1: ความยาว HMA
input int    InpM15Len = 320;      // M15: ความยาว HMA
input int    InpM5Len  = 960;      // M5: ความยาว HMA
input int    InpD1EMA  = 20;       // EMA ของ D1 สำหรับตัวกรองเทรนด์
input double InpSLATR  = 1.5;      // SL = k x ATR(14)
input int    InpMACDFast = 12, InpMACDSlow = 26, InpMACDSig = 9;   // MACD ฐานบน H1 (M15 คูณ 4)
input group "=== ทั่วไป ==="
input long   InpMagic  = 889000;   // magic: SSL H1 +0, M15 +1, M5 +2, MACD H1 +3, MACD M15 +4
input int    InpPanelX = 10;
input int    InpPanelY = 20;
input bool   InpWriteLog = true;
input string InpLogFile  = "xau_sentinel_trades.csv";

struct Engine
{
   string           name, nick;
   ENUM_TIMEFRAMES  tf;
   int              len;
   int              type;       // 0 = SSL, 1 = MACD (len = ตัวคูณคาบ)
   bool             useD1;
   long             magic;
   int              state;      // สถานะ SSL ล่าสุด +1/-1
   double           atr;
   datetime         lastBar;
   string           note;       // ข้อความเหตุการณ์ล่าสุด
   bool             ready;
};

CTrade  trade;
#define NENG 5
Engine  E[NENG];
int     gMode, gRisk;
bool    gPaused = false, gHalted = false;
double  gPeak = 0;
string  gPfx;
string  P = "XSN_";             // prefix ของวัตถุบนกราฟ
// สถิติ
int     sTrades = 0, sWins = 0; double sGrossW = 0, sGrossL = 0, sToday = 0, sMonth = 0;
string  sLast[5];

//====================================================================
// HMA / ATR
//====================================================================
double WMA(const double &x[], int end, int n)
{
   double s = 0, w = 0;
   for(int k = 0; k < n; k++) { double wk = n - k; s += x[end - k] * wk; w += wk; }
   return s / w;
}
double HMAat(const double &x[], int end, int n)
{
   int h = n / 2, q = (int)MathRound(MathSqrt(n));
   double tmp[]; ArrayResize(tmp, q);
   for(int k = 0; k < q; k++) tmp[k] = 2 * WMA(x, end - (q - 1 - k), h) - WMA(x, end - (q - 1 - k), n);
   return WMA(tmp, q - 1, q);
}
// full = คำนวณย้อนหลังทั้งหมด (ตอนเริ่ม) / ไม่ full = อัปเดตเฉพาะแท่งที่เพิ่งปิด
bool MACDCalc(Engine &e)
{
   int f = InpMACDFast * e.len, sl = InpMACDSlow * e.len, sg = InpMACDSig * e.len, cnt = sl * 10 + 200;
   MqlRates r[];
   int n = CopyRates(_Symbol, e.tf, 1, cnt, r);
   if(n < sl * 4) return false;
   double af = 2.0 / (f + 1), as = 2.0 / (sl + 1), ag = 2.0 / (sg + 1);
   double ef = r[0].close, es = r[0].close, m = 0, sgl = 0, a = r[0].high - r[0].low;
   for(int i = 1; i < n; i++)
   {
      ef += af * (r[i].close - ef); es += as * (r[i].close - es); m = ef - es; sgl += ag * (m - sgl);
      double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      a += (tr - a) / 14.0;
   }
   double h = m - sgl;
   e.state = h > 0 ? 1 : (h < 0 ? -1 : e.state);
   e.atr = a;
   return true;
}
bool EngineCalc(Engine &e, bool full)
{
   if(e.type == 1) return MACDCalc(e);
   int need = e.len + (int)MathSqrt(e.len) + 5;
   int cnt  = full ? need + 1500 : need + 3;
   MqlRates r[];
   int n = CopyRates(_Symbol, e.tf, 1, cnt, r);                    // r[n-1] = แท่งที่ปิดล่าสุด
   if(n < need + 2) return false;
   double hi[], lo[]; ArrayResize(hi, n); ArrayResize(lo, n);
   for(int i = 0; i < n; i++) { hi[i] = r[i].high; lo[i] = r[i].low; }
   int st = full ? 0 : e.state;
   for(int i = full ? need : n - 1; i < n; i++)
   {
      double eh = HMAat(hi, i, e.len), el = HMAat(lo, i, e.len);
      if(r[i].close > eh) st = 1; else if(r[i].close < el) st = -1;
   }
   if(full)
   {
      double a = r[0].high - r[0].low;
      for(int i = 1; i < n; i++)
      {
         double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
         a += (tr - a) / 14.0;
      }
      e.atr = a;
   }
   else
   {
      double pc = r[n - 2].close, tr = MathMax(r[n - 1].high - r[n - 1].low, MathMax(MathAbs(r[n - 1].high - pc), MathAbs(r[n - 1].low - pc)));
      e.atr += (tr - e.atr) / 14.0;
   }
   e.state = st;
   return true;
}
int gD1h = INVALID_HANDLE;
int D1Trend()
{
   double v[]; int t = 0;
   if(gD1h != INVALID_HANDLE && CopyBuffer(gD1h, 0, 1, 1, v) == 1) t = iClose(_Symbol, PERIOD_D1, 1) > v[0] ? 1 : -1;
   return t;
}

//====================================================================
// บัญชี / ความเสี่ยง
//====================================================================
bool   IsCent()        { string c = AccountInfoString(ACCOUNT_CURRENCY); return c == "USC" || c == "EUC" || StringFind(_Symbol, "c", 6) >= 0; }
double RiskPct()       { return gRisk == RISK_LOW ? InpRiskLow : gRisk == RISK_MID ? InpRiskMid : gRisk == RISK_HIGH ? InpRiskHigh : InpRiskMax; }
bool   EngineOn(int k) { return k < 2 || (k == 2 && gMode == MODE_HIGHFREQ) || (k >= 3 && gMode == MODE_TURBO); }  // 0 SSL H1, 1 SSL M15, 2 SSL M5, 3 MACD H1, 4 MACD M15
// DD ที่ได้จากแบ็กเทส (Cent USD 300) ตามโหมด/ระดับ — แสดงบนแดชบอร์ด
int BacktestDD(int mode, int risk)
{
   int std[4] = {17, 24, 31, 43}, hf[4] = {33, 46, 50, 50}, tb[4] = {32, 46, 50, 50};   // 1%+ ในไม้เยอะ/เทอร์โบ: ชน DD 50% หยุด
   return mode == MODE_STANDARD ? std[risk] : mode == MODE_HIGHFREQ ? hf[risk] : tb[risk];
}
string BacktestEnd(int mode, int risk)
{
   string std[4] = {"$895", "$1,443", "$2,232", "$4,776"}, hf[4] = {"$1,650", "$3,026", "หยุดที่ DD 50%", "หยุดที่ DD 50%"},
          tb[4] = {"$1,854", "$3,616", "หยุดที่ DD 50%", "หยุดที่ DD 50%"};
   return mode == MODE_STANDARD ? std[risk] : mode == MODE_HIGHFREQ ? hf[risk] : tb[risk];
}

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

void OpenEngine(Engine &e, int dir)
{
   double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double spread = ask - bid;
   if(spread > InpMaxSpreadUSD) { e.note = "ข้าม: spread กว้าง"; return; }
   double entry = dir > 0 ? ask : bid, dist = InpSLATR * e.atr;
   double sl = NormalizeDouble(entry - dir * dist, _Digits);
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(tv <= 0 || ts <= 0 || dist <= 0) { e.note = "ข้าม: ข้อมูลสัญญาไม่พร้อม"; return; }
   double perLot = dist / ts * tv;
   double lots = MathFloor(eq * RiskPct() / 100.0 / perLot / step) * step;
   if(lots < vmin)
   {
      double rp = vmin * perLot / eq * 100.0;
      if(rp > InpMinLotCap) { e.note = StringFormat("ข้าม: lot ขั้นต่ำเสี่ยง %.1f%% (ทุนน้อยไป)", rp); return; }
      lots = vmin;
   }
   lots = NormalizeDouble(MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), 2);
   trade.SetExpertMagicNumber(e.magic);
   bool ok = dir > 0 ? trade.Buy(lots, _Symbol, 0, sl, 0, "SENTINEL " + e.name) : trade.Sell(lots, _Symbol, 0, sl, 0, "SENTINEL " + e.name);
   if(ok && (trade.ResultRetcode() == TRADE_RETCODE_DONE || trade.ResultRetcode() == TRADE_RETCODE_PLACED))
   {
      e.note = (dir > 0 ? "เปิด BUY " : "เปิด SELL ") + DoubleToString(lots, 2) + " lot";
      LogLine(StringFormat("%s,OPEN,%d,%.2f,%s,%s,%s,%s,%s,%.2f,", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), dir, lots,
              DoubleToString(entry, _Digits), DoubleToString(trade.ResultPrice(), _Digits), DoubleToString(spread, _Digits),
              DoubleToString(sl, _Digits), e.name, lots * perLot / eq * 100.0));
   }
   else e.note = "ส่งคำสั่งไม่สำเร็จ " + IntegerToString((int)trade.ResultRetcode());
}

void CloseAll()
{
   for(int k = 0; k < NENG; k++) { ulong t = EngineTicket(E[k].magic); if(t > 0) trade.PositionClose(t); }
}

//====================================================================
// สถิติจากประวัติ
//====================================================================
void UpdateStats()
{
   datetime now = TimeCurrent();
   MqlDateTime d; TimeToStruct(now, d);
   datetime dayStart = now - (d.hour * 3600 + d.min * 60 + d.sec);
   datetime monStart = dayStart - (d.day - 1) * 86400;
   if(!HistorySelect(0, now)) return;
   sTrades = 0; sWins = 0; sGrossW = 0; sGrossL = 0; sToday = 0; sMonth = 0;
   for(int i = 0; i < 5; i++) sLast[i] = "";
   int nl = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong dl = HistoryDealGetTicket(i);
      long  mg = HistoryDealGetInteger(dl, DEAL_MAGIC);
      if(mg < InpMagic || mg > InpMagic + NENG - 1 || HistoryDealGetString(dl, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(dl, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      double p = HistoryDealGetDouble(dl, DEAL_PROFIT) + HistoryDealGetDouble(dl, DEAL_SWAP) + HistoryDealGetDouble(dl, DEAL_COMMISSION);
      datetime t = (datetime)HistoryDealGetInteger(dl, DEAL_TIME);
      sTrades++; if(p > 0) { sWins++; sGrossW += p; } else sGrossL -= p;
      if(t >= dayStart) sToday += p;
      if(t >= monStart) sMonth += p;
      if(nl < 5)
      {
         string en = E[(int)(mg - InpMagic)].name;
         long   ty = HistoryDealGetInteger(dl, DEAL_TYPE);       // ดีลปิดของ BUY คือ SELL
         sLast[nl++] = StringFormat("%s  %-3s  %s  %+.2f", TimeToString(t, TIME_MINUTES), en, ty == DEAL_TYPE_SELL ? "BUY " : "SELL", p);
      }
   }
}

//====================================================================
// แดชบอร์ด (วัตถุบนกราฟ)
//====================================================================
color C_BG = C'12,14,28', C_PANEL = C'22,26,48', C_EDGE = C'0,200,255', C_GOLD = C'255,196,0', C_TXT = C'225,230,240',
      C_MUTED = C'130,140,165', C_GREEN = C'0,230,118', C_RED = C'255,70,90', C_ORANGE = C'255,150,0', C_OFF = C'60,64,85';
string FONT = "Tahoma";

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
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, bold ? "Tahoma Bold" : FONT);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz); ObjectSetInteger(0, n, OBJPROP_COLOR, c); ObjectSetInteger(0, n, OBJPROP_ANCHOR, an);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
void Button(string id, int x, int y, int w, int h, string s, bool on, color onc)
{
   string n = P + "B_" + id;
   if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, InpPanelX + x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w); ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, s); ObjectSetString(0, n, OBJPROP_FONT, FONT); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, on ? onc : C_PANEL); ObjectSetInteger(0, n, OBJPROP_COLOR, on ? C_BG : C_TXT);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, on ? onc : C_OFF); ObjectSetInteger(0, n, OBJPROP_STATE, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false); ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
}
color DDColor(double dd) { return dd < 20 ? C_GREEN : dd < 35 ? C_GOLD : dd < 45 ? C_ORANGE : C_RED; }

// หัวหุ่นยนต์: ตาเปลี่ยนสีตามสถานะ (เขียว = ทำงาน, ส้ม = หยุดชั่วคราว, แดง = หยุดเพราะ DD)
void Robot(int x, int y, color eye)
{
   Rect("rb_ant", x + 21, y, 4, 8, C_EDGE);
   Rect("rb_antb", x + 18, y - 4, 10, 5, eye);
   Rect("rb_head", x, y + 8, 46, 36, C_PANEL, C_EDGE, 2);
   Rect("rb_eyeL", x + 8, y + 17, 11, 8, eye);
   Rect("rb_eyeR", x + 27, y + 17, 11, 8, eye);
   Rect("rb_mouth", x + 12, y + 32, 22, 4, C_EDGE);
   Rect("rb_earL", x - 5, y + 18, 5, 14, C_EDGE);
   Rect("rb_earR", x + 46, y + 18, 5, 14, C_EDGE);
}

void DrawPanel()
{
   const int W = 560;
   bool   cent = IsCent();
   string cur  = AccountInfoString(ACCOUNT_CURRENCY);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd  = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   color  eye = gHalted ? C_RED : gPaused ? C_ORANGE : C_GREEN;
   string stat = gHalted ? "หยุด: DD ถึงเพดาน" : gPaused ? "หยุดชั่วคราว" : "กำลังทำงาน";

   Rect("bg", 0, 0, W, 746, C_BG, C_EDGE, 2);
   // ---- หัว ----
   Robot(16, 14, eye);
   Text("title", 80, 14, "XAU SENTINEL", C_GOLD, 18, true);
   Text("sub", 82, 44, "หุ่นยนต์ยามเฝ้าทองคำ · SSL + MACD · v1.10", C_MUTED, 8);
   Rect("stat_bg", 400, 18, 145, 26, C_PANEL, eye, 2);
   Text("stat", 472, 23, "● " + stat, eye, 9, true, ANCHOR_UPPER);
   Text("acct", 400, 50, (cent ? "บัญชี Cent (" : "บัญชี Standard (") + cur + ")", cent ? C_GREEN : C_ORANGE, 8);

   // ---- โหมด ----
   Text("l_mode", 14, 78, "โหมด", C_MUTED, 9);
   Button("m0", 70, 74, 155, 26, "มาตรฐาน · ~47/เดือน", gMode == MODE_STANDARD, C_EDGE);
   Button("m1", 230, 74, 155, 26, "ไม้เยอะ · ~84/เดือน", gMode == MODE_HIGHFREQ, C_GOLD);
   Button("m2", 390, 74, 155, 26, "เทอร์โบ · ~120/เดือน", gMode == MODE_TURBO, C_RED);
   // ---- ความเสี่ยง ----
   Text("l_risk", 14, 112, "ความเสี่ยง", C_MUTED, 9);
   string rn[4] = {"ต่ำ", "กลาง", "สูง", "สูงสุด"}; double rv[4] = {InpRiskLow, InpRiskMid, InpRiskHigh, InpRiskMax};
   color  rc[4] = {C_GREEN, C_GOLD, C_ORANGE, C_RED};
   for(int k = 0; k < 4; k++) Button("r" + IntegerToString(k), 90 + k * 115, 108, 108, 26, StringFormat("%s %.2g%%", rn[k], rv[k]), gRisk == k, rc[k]);
   int bdd = BacktestDD(gMode, gRisk);
   Text("bt", 14, 142, StringFormat("แบ็กเทสปีล่าสุด ($300 → %s) · DD สูงสุด %d%%  %s", BacktestEnd(gMode, gRisk), bdd,
        bdd >= 50 ? "!! เกินเพดาน 50%" : bdd >= 40 ? "! ใกล้เพดาน" : "อยู่ในเกณฑ์"), DDColor(bdd), 8);

   // ---- การ์ดบัญชี ----
   Rect("acc", 10, 162, W - 20, 104, C_PANEL, C_OFF);
   double k1 = cent ? 0.01 : 1.0;   // แปลง USC -> USD
   Text("a1", 22, 170, "ทุน (Balance)", C_MUTED, 8);       Text("a1v", 22, 184, StringFormat("%.2f %s", bal, cur), C_TXT, 12, true);
   Text("a2", 200, 170, "มูลค่าสุทธิ (Equity)", C_MUTED, 8); Text("a2v", 200, 184, StringFormat("%.2f %s", eq, cur), eq >= bal ? C_GREEN : C_RED, 12, true);
   Text("a3", 380, 170, cent ? "เท่ากับ (USD)" : "กำไร/ขาดทุนลอย", C_MUTED, 8);
   Text("a3v", 380, 184, cent ? StringFormat("$%.2f", eq * k1) : StringFormat("%+.2f", eq - bal), C_GOLD, 12, true);
   Text("a4", 22, 210, StringFormat("วันนี้ %+.2f", sToday), sToday >= 0 ? C_GREEN : C_RED, 9);
   Text("a5", 200, 210, StringFormat("เดือนนี้ %+.2f", sMonth), sMonth >= 0 ? C_GREEN : C_RED, 9);
   Text("a6", 380, 210, StringFormat("จุดสูงสุด %.2f", gPeak), C_MUTED, 9);
   // แถบ DD
   Text("dd_l", 22, 234, StringFormat("DD ตอนนี้ %.1f%%", dd), DDColor(dd), 9, true);
   int gx = 150, gw = 380;
   Rect("dd_bg", gx, 236, gw, 14, C_BG, C_OFF);
   Rect("dd_fg", gx + 1, 237, (int)MathMax(1, MathMin(gw - 2, (gw - 2) * dd / InpDDHalt)), 12, DDColor(dd));
   Text("dd_m", gx + gw, 252, StringFormat("เพดาน %.0f%%", InpDDHalt), C_MUTED, 7, false, ANCHOR_RIGHT_UPPER);

   // ---- เครื่องยนต์ ----
   Text("l_eng", 14, 274, "เครื่องยนต์", C_MUTED, 9);
   int d1 = D1Trend();
   for(int k = 0; k < NENG; k++)
   {
      int x = 10 + (k % 3) * 183, y = 292 + (k / 3) * 136;
      bool on = EngineOn(k);
      ulong t = EngineTicket(E[k].magic);
      int pd = 0; double pp = 0, pl = 0;
      if(t > 0 && PositionSelectByTicket(t)) { pd = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1; pp = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); pl = PositionGetDouble(POSITION_VOLUME); }
      color ec = !on ? C_OFF : pd > 0 ? C_GREEN : pd < 0 ? C_RED : C_EDGE;
      string id = "e" + IntegerToString(k);
      Rect(id, x, y, 175, 128, C_PANEL, ec, 2);
      Text(id + "n", x + 10, y + 6, E[k].name + " · " + E[k].nick, on ? C_GOLD : C_MUTED, 10, true);
      Text(id + "s", x + 10, y + 28, !on ? "ปิด (ไม่ใช้ในโหมดนี้)" : pd > 0 ? "▲ ถือ BUY" : pd < 0 ? "▼ ถือ SELL" : "● รอสัญญาณ", ec, 12, true);
      Text(id + "p", x + 10, y + 52, pd != 0 ? StringFormat("%.2f lot  %+.2f", pl, pp) : " ", pp >= 0 ? C_GREEN : C_RED, 9);
      string sig = E[k].state > 0 ? "ขาขึ้น" : E[k].state < 0 ? "ขาลง" : "-";
      Text(id + "t", x + 10, y + 72, (E[k].type == 1 ? "MACD: " : "SSL: ") + sig + (E[k].useD1 ? "  · D1: " + (d1 > 0 ? "ขึ้น" : d1 < 0 ? "ลง" : "-") : "  · ไม่กรอง D1"), C_TXT, 8);
      Text(id + "a", x + 10, y + 88, E[k].type == 1 ? StringFormat("MACD %d/%d/%d · SL %.1f$", InpMACDFast * E[k].len, InpMACDSlow * E[k].len, InpMACDSig * E[k].len, InpSLATR * E[k].atr) : StringFormat("HMA %d · SL %.1f$", E[k].len, InpSLATR * E[k].atr), C_MUTED, 8);
      Text(id + "x", x + 10, y + 106, E[k].note == "" ? " " : E[k].note, C_MUTED, 7);
   }

   // ---- สถิติ ----
   Rect("st", 10, 564, 270, 128, C_PANEL, C_OFF);
   Text("st0", 22, 570, "ผลงานทั้งหมด", C_MUTED, 9);
   double wr = sTrades > 0 ? 100.0 * sWins / sTrades : 0, pf = sGrossL > 0 ? sGrossW / sGrossL : 0;
   Text("st1", 22, 590, StringFormat("ไม้ที่ปิดแล้ว  %d", sTrades), C_TXT, 9);
   Text("st2", 22, 608, StringFormat("อัตราชนะ  %.0f%%  (ปกติ 15-35%%)", wr), C_TXT, 9);
   Text("st3", 22, 626, StringFormat("Profit Factor  %.2f  (เป้า > 1.3)", pf), pf >= 1.3 ? C_GREEN : pf >= 1.0 ? C_GOLD : C_RED, 9);
   Text("st4", 22, 644, StringFormat("กำไรสุทธิ  %+.2f", sGrossW - sGrossL), sGrossW >= sGrossL ? C_GREEN : C_RED, 9, true);
   Text("st5", 22, 666, "ชนะน้อยแต่ไม้ชนะใหญ่ — แพ้ติดกันเป็นเรื่องปกติ", C_MUTED, 7);
   Rect("lt", 290, 564, 260, 128, C_PANEL, C_OFF);
   Text("lt0", 302, 570, "5 ไม้ล่าสุด", C_MUTED, 9);
   for(int i = 0; i < 5; i++)
   {
      bool pos = StringFind(sLast[i], "+") >= 0;
      Text("lt" + IntegerToString(i + 1), 302, 590 + i * 18, sLast[i] == "" ? "-" : sLast[i], sLast[i] == "" ? C_MUTED : pos ? C_GREEN : C_RED, 8);
   }
   // ---- ปุ่มควบคุม ----
   Button("pause", 10, 702, 268, 32, gPaused ? "▶ ทำงานต่อ" : "|| หยุดเปิดไม้ใหม่ชั่วคราว", gPaused, C_ORANGE);
   Button("close", 290, 702, 260, 32, "X  ปิดทุกไม้ของ SENTINEL", false, C_RED);
   ChartRedraw();
}

//====================================================================
// ระบบหลัก
//====================================================================
void InitEngine(int k, string name, string nick, ENUM_TIMEFRAMES tf, int len, bool d1, int type = 0)
{
   E[k].type = type;
   E[k].name = name; E[k].nick = nick; E[k].tf = tf; E[k].len = len; E[k].useD1 = d1;
   E[k].magic = InpMagic + k; E[k].state = 0; E[k].atr = 0; E[k].lastBar = 0; E[k].note = ""; E[k].ready = false;
}
int OnInit()
{
   gPfx = "XSN_" + IntegerToString(InpMagic) + "_";
   InitEngine(0, "H1",  "พี่ใหญ่", PERIOD_H1,  InpH1Len,  false);
   InitEngine(1, "M15", "พี่กลาง", PERIOD_M15, InpM15Len, true);
   InitEngine(2, "M5",  "น้องเล็ก", PERIOD_M5,  InpM5Len,  true);
   InitEngine(3, "MACD H1",  "สายฟ้า", PERIOD_H1,  1, false, 1);
   InitEngine(4, "MACD M15", "สายลม",  PERIOD_M15, 4, false, 1);
   gMode   = GlobalVariableCheck(gPfx + "mode")  ? (int)GlobalVariableGet(gPfx + "mode")  : (int)InpMode;
   gRisk   = GlobalVariableCheck(gPfx + "risk")  ? (int)GlobalVariableGet(gPfx + "risk")  : (int)InpRisk;
   gPaused = GlobalVariableCheck(gPfx + "pause") && GlobalVariableGet(gPfx + "pause") > 0;
   gHalted = GlobalVariableCheck(gPfx + "halt")  && GlobalVariableGet(gPfx + "halt") > 0;
   gPeak   = GlobalVariableCheck(gPfx + "peak")  ? GlobalVariableGet(gPfx + "peak") : AccountInfoDouble(ACCOUNT_EQUITY);
   trade.SetTypeFillingBySymbol(_Symbol); trade.SetDeviationInPoints(50);
   gD1h = iMA(_Symbol, PERIOD_D1, InpD1EMA, 0, MODE_EMA, PRICE_CLOSE);
   for(int k = 0; k < NENG; k++)                                   // เริ่มจากสถานะปัจจุบัน: ไม่เปิดไม้จนกว่าจะเกิดการกลับทิศครั้งถัดไป
   {
      E[k].ready = EngineCalc(E[k], true);
      E[k].lastBar = iTime(_Symbol, E[k].tf, 0);
      if(!E[k].ready) E[k].note = "รอข้อมูลกราฟย้อนหลัง";
   }
   if(StringFind(_Symbol, "XAU") < 0 && StringFind(_Symbol, "GOLD") < 0) Print("XAU SENTINEL: ออกแบบมาสำหรับ XAUUSD");
   EventSetTimer(1);
   UpdateStats(); DrawPanel();
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); if(gD1h != INVALID_HANDLE) IndicatorRelease(gD1h); ObjectsDeleteAll(0, P); ChartRedraw(); }

void OnTick()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > gPeak) { gPeak = eq; GlobalVariableSet(gPfx + "peak", gPeak); }
   double dd = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   if(!gHalted && dd >= InpDDHalt)
   {
      gHalted = true; GlobalVariableSet(gPfx + "halt", 1); CloseAll();
      Print("XAU SENTINEL: DD ", DoubleToString(dd, 1), "% ถึงเพดาน — ปิดทุกไม้และหยุด (ลบ Global Variable ", gPfx, "halt เพื่อเริ่มใหม่)");
   }
   for(int k = 0; k < NENG; k++)
   {
      datetime b = iTime(_Symbol, E[k].tf, 0);
      if(b == E[k].lastBar) continue;
      E[k].lastBar = b;
      int prev = E[k].state;
      if(!E[k].ready) { E[k].ready = EngineCalc(E[k], true); continue; }
      if(!EngineCalc(E[k], false)) continue;
      if(E[k].state == 0 || E[k].state == prev) continue;
      // สัญญาณกลับทิศ: ปิดไม้เดิมของเครื่องยนต์นี้ (ทำเสมอ แม้เครื่องยนต์ถูกปิดในโหมด)
      ulong t = EngineTicket(E[k].magic);
      if(t > 0) trade.PositionClose(t);
      E[k].note = (E[k].type == 1 ? "MACD" : "SSL") + (E[k].state > 0 ? " กลับเป็นขาขึ้น" : " กลับเป็นขาลง");
      if(gHalted || gPaused || !EngineOn(k)) continue;
      if(E[k].useD1 && D1Trend() != E[k].state) { E[k].note = "ไม่เข้า: สวนเทรนด์ D1"; continue; }
      OpenEngine(E[k], E[k].state);
   }
}

void OnTimer() { UpdateStats(); DrawPanel(); }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK || StringFind(sparam, P + "B_") != 0) return;
   string b = StringSubstr(sparam, StringLen(P + "B_"));
   if(b == "m0") gMode = MODE_STANDARD;
   else if(b == "m1") gMode = MODE_HIGHFREQ;
   else if(b == "m2") gMode = MODE_TURBO;
   else if(StringSubstr(b, 0, 1) == "r") gRisk = (int)StringToInteger(StringSubstr(b, 1));
   else if(b == "pause") { gPaused = !gPaused; GlobalVariableSet(gPfx + "pause", gPaused ? 1 : 0); }
   else if(b == "close")
   {
      if(MessageBox("ปิดทุกไม้ของ XAU SENTINEL ตอนนี้?", "ยืนยัน", MB_YESNO | MB_ICONQUESTION) == IDYES) CloseAll();
   }
   GlobalVariableSet(gPfx + "mode", gMode); GlobalVariableSet(gPfx + "risk", gRisk);
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
