//+------------------------------------------------------------------+
//| YY_GoldHybrid_Grid.mq5                                           |
//| XAUUSD Hybrid: ไม้แรกเข้าตาม Liquidity Sweep + MSS                  |
//|                ผิดทาง → grid กู้ ระยะตาม ATR                         |
//|                ขนาด grid คำนวณตามงบ DD (risk-budgeted)              |
//|                Hard stop: Equity DD จาก peak ถึงเพดาน → ปิดทุกไม้       |
//|                                                                  |
//| ต้องใช้บัญชีแบบ Hedging · ทุกระยะเป็น points (_Point)                 |
//| ไฟล์ include อยู่ที่ MQL5/Include/YY/                               |
//+------------------------------------------------------------------+
#property copyright "YOUNGYUU"
#property version   "1.00"
#property description "XAUUSD Hybrid Liquidity Sweep + risk-budgeted ATR grid"

#include <YY/YY_TradeUtils.mqh>
#include <YY/YY_RiskBudget.mqh>
#include <YY/YY_Signal_LiqSweep.mqh>
#include <YY/YY_Basket.mqh>
#include <YY/YY_Panel.mqh>

//+------------------------------------------------------------------+
input group "══════ 💧 สัญญาณไม้แรก (Liquidity Sweep + MSS) ══════"
input ENUM_YY_BIAS_MODE InpBiasMode   = YY_BIAS_HTF_A; // กรองทิศ (Bias)
input ENUM_TIMEFRAMES   InpHtfA       = PERIOD_H4;     // TF โครงสร้าง 1
input ENUM_TIMEFRAMES   InpHtfB       = PERIOD_D1;     // TF โครงสร้าง 2
input int               InpSwLen      = 10;            // Swing liquidity (แท่ง)
input int               InpMssLen     = 3;             // Swing ย่อยสำหรับ MSS (แท่ง)
input int               InpWait       = 20;            // รอ MSS ไม่เกิน (แท่ง)
input bool              InpUsePD      = true;          // ใช้ PDH/PDL เป็น liquidity
input int               InpWarmupBars = 1000;          // แท่งย้อนหลังสำหรับสร้าง state ตอนเริ่ม

input group "══════ 🧱 Grid ══════"
input int    InpATRLen       = 14;     // ATR ยาว (TF กราฟ)
input double InpGridATR      = 1.0;    // ระยะห่างแต่ละชั้น (× ATR)
input double InpTPATR        = 0.5;    // เป้ากำไรชุด (× ATR × lot ไม้แรก)
input double InpMinTPMoney   = 0.30;   // เป้ากำไรชุดขั้นต่ำ ($)
input double InpCommPerLot   = 0.0;    // ค่าคอม $ ต่อ 1 lot ไป-กลับ (หักก่อนเทียบเป้า)
input int    InpMaxSpreadPts = 80;     // spread สูงสุดตอนเปิดไม้แรก (points, 0 = ไม่กรอง)

input group "══════ 🛡️ งบความเสี่ยง ══════"
input double InpDDCapPct      = 70.0;  // เพดาน Equity DD จาก peak (%) → ปิดทุกไม้และหยุด
input double InpBudgetUse     = 0.90;  // ใช้งบกี่ส่วนของห้องที่เหลือ (0.1–1.0)
input int    InpMaxLayers     = 6;     // จำนวนชั้นสูงสุด
input int    InpMinLayers     = 2;     // จำนวนชั้นต่ำสุด (งบไม่พอ = ไม่เข้า)
input double InpMaxMult       = 1.5;   // ตัวคูณ lot สูงสุด
input double InpMultStep      = 0.1;   // ลดตัวคูณทีละ
input double InpEquityPerBase = 200.0; // ทุก $X ของ equity = base lot +1 ขั้น
input double InpExtraSpacings = 1.0;   // ทดสอบแย่สุดเลยชั้นสุดท้ายอีกกี่ช่วง
input double InpMinMarginLvl  = 150.0; // margin level ขั้นต่ำ ณ จุดแย่สุด (%)

input group "══════ ⚙️ ระบบ ══════"
input ulong  InpMagic     = 2611001;   // Magic number
input uint   InpDeviation = 50;        // slippage ที่ยอมรับ (points)
input bool   InpResetHalt = false;     // true = ล้างสถานะหยุดถาวร + ตั้ง peak ใหม่
input bool   InpShowPanel = true;      // แสดงแผง

input group "══════ 📱 รับคำสั่งภายนอก (แอปในอนาคต) ══════"
input string InpCmdURL     = "";       // URL รับคำสั่ง (ว่าง = ปิด) ต้องเพิ่มใน Tools > Options > Expert Advisors
input int    InpCmdPollSec = 10;       // ถามคำสั่งทุกกี่วินาที

//+------------------------------------------------------------------+
enum ENUM_YY_CMD { CMD_NONE = 0, CMD_PAUSE = 1, CMD_RESUME = 2, CMD_CLOSE = 3, CMD_CLOSE_PAUSE = 4 };

CYYTrade      g_trade;
CYYRiskBudget g_budget;
CYYLiqSweep   g_signal;
CYYBasket     g_basket;
CYYPanel      g_panel;
SYYGridPlan   g_plan;

int      g_atrHandle   = INVALID_HANDLE;
datetime g_lastBarTime = 0;
double   g_peak        = 0.0;
bool     g_halted      = false;
bool     g_paused      = false;
bool     g_isTester    = false;
bool     g_drawPanel   = true;
int      g_pendingCmd  = CMD_NONE;
string   g_gv;                 // prefix GlobalVariable
string   g_status      = "";   // ข้อความเหตุการณ์ล่าสุด
int      g_signals     = 0;
int      g_baskets     = 0;
int      g_basketsWin  = 0;
int      g_maxLayerHit = 0;
bool     g_webWarned   = false;

//+------------------------------------------------------------------+
void SaveState()
{
   if(g_isTester) return;
   GlobalVariableSet(g_gv + "PEAK", g_peak);
   GlobalVariableSet(g_gv + "HALT", g_halted ? 1.0 : 0.0);
   GlobalVariableSet(g_gv + "PAUSE", g_paused ? 1.0 : 0.0);
}

void SetStatus(const string s)
{
   g_status = TimeToString(TimeCurrent(), TIME_MINUTES) + "  " + s;
   Print("[YY] ", s);
}

//+------------------------------------------------------------------+
int OnInit()
{
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
   {
      Alert("YY_GoldHybrid_Grid: ต้องใช้บัญชีแบบ Hedging เท่านั้น");
      return INIT_FAILED;
   }
   if(InpMaxLayers < 1 || InpMaxLayers > YY_MAX_LAYERS || InpMinLayers < 1 || InpMinLayers > InpMaxLayers)
   {
      Alert("YY_GoldHybrid_Grid: ตั้งจำนวนชั้นไม่ถูกต้อง (1..", YY_MAX_LAYERS, " และ Min <= Max)");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(InpDDCapPct <= 0.0 || InpDDCapPct >= 100.0 || InpGridATR <= 0.0 || InpMaxMult < 1.0)
      return INIT_PARAMETERS_INCORRECT;

   g_isTester  = (bool)MQLInfoInteger(MQL_TESTER);
   g_drawPanel = InpShowPanel && (!g_isTester || (bool)MQLInfoInteger(MQL_VISUAL_MODE));
   g_gv        = StringFormat("YYGH_%I64u_", InpMagic);

   g_atrHandle = iATR(_Symbol, _Period, InpATRLen);
   if(g_atrHandle == INVALID_HANDLE) { Print("[YY] สร้าง ATR ไม่ได้"); return INIT_FAILED; }

   g_trade.Init(_Symbol, InpMagic, InpDeviation);
   g_basket.Init(_Symbol, InpMagic);

   g_budget.ddCap          = InpDDCapPct / 100.0;
   g_budget.budgetUse      = MathMax(0.1, MathMin(1.0, InpBudgetUse));
   g_budget.maxLayers      = InpMaxLayers;
   g_budget.minLayers      = InpMinLayers;
   g_budget.maxMult        = InpMaxMult;
   g_budget.multStep       = InpMultStep;
   g_budget.equityPerBase  = InpEquityPerBase;
   g_budget.extraSpacings  = InpExtraSpacings;
   g_budget.minMarginLevel = InpMinMarginLvl;

   g_signal.Init(_Symbol, _Period, InpBiasMode, InpHtfA, InpHtfB, InpSwLen, InpMssLen, InpWait, InpUsePD);
   g_signal.Warmup(InpWarmupBars);
   g_lastBarTime = iTime(_Symbol, _Period, 0);

   // peak / สถานะหยุด: live ใช้ GlobalVariable เพื่อให้รอดการ restart
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_peak = eq;
   if(!g_isTester && !InpResetHalt)
   {
      if(GlobalVariableCheck(g_gv + "PEAK"))  g_peak   = MathMax(eq, GlobalVariableGet(g_gv + "PEAK"));
      if(GlobalVariableCheck(g_gv + "HALT"))  g_halted = GlobalVariableGet(g_gv + "HALT") > 0.5;
      if(GlobalVariableCheck(g_gv + "PAUSE")) g_paused = GlobalVariableGet(g_gv + "PAUSE") > 0.5;
   }
   if(!g_isTester && !GlobalVariableCheck(g_gv + "CMD")) GlobalVariableSet(g_gv + "CMD", 0.0);
   SaveState();

   if(StringLen(InpCmdURL) > 0 && !g_isTester) EventSetTimer(MathMax(2, InpCmdPollSec));

   if(g_drawPanel) g_panel.Init("YYGH_PNL_");
   SetStatus(StringFormat("เริ่มทำงาน · peak $%.2f · เพดาน DD %.0f%%", g_peak, InpDDCapPct));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_atrHandle != INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   if(g_drawPanel) g_panel.Destroy();
   SaveState();
}

//+------------------------------------------------------------------+
//| คำสั่งภายนอก                                                      |
//|  GlobalVariable YYGH_<magic>_CMD : 1 หยุดชั่วคราว 2 ทำงานต่อ          |
//|                                   3 ปิดชุด 4 ปิดชุด+หยุดชั่วคราว      |
//|  URL: ตอบเป็นข้อความ PAUSE / RESUME / CLOSE / CLOSE_PAUSE / NONE     |
//+------------------------------------------------------------------+
void ReadGVCommand()
{
   if(g_isTester) return;
   string name = g_gv + "CMD";
   if(!GlobalVariableCheck(name)) return;
   int v = (int)GlobalVariableGet(name);
   if(v != CMD_NONE)
   {
      g_pendingCmd = v;
      GlobalVariableSet(name, 0.0);
   }
}

void ApplyCommand()
{
   if(g_pendingCmd == CMD_NONE) return;
   int cmd = g_pendingCmd;
   g_pendingCmd = CMD_NONE;
   switch(cmd)
   {
      case CMD_PAUSE:
         g_paused = true;  SetStatus("คำสั่งภายนอก: หยุดเปิดชุดใหม่ชั่วคราว"); break;
      case CMD_RESUME:
         g_paused = false;
         if(g_halted)
         {
            g_halted = false;
            g_peak   = AccountInfoDouble(ACCOUNT_EQUITY);
            SetStatus("คำสั่งภายนอก: ทำงานต่อ + ตั้ง peak ใหม่หลังแตะเพดาน DD");
         }
         else SetStatus("คำสั่งภายนอก: ทำงานต่อ");
         break;
      case CMD_CLOSE:
         g_trade.CloseAll(); SetStatus("คำสั่งภายนอก: ปิดชุดปัจจุบัน"); break;
      case CMD_CLOSE_PAUSE:
         g_trade.CloseAll(); g_paused = true; SetStatus("คำสั่งภายนอก: ปิดชุด + หยุดชั่วคราว"); break;
   }
   SaveState();
}

void OnTimer()
{
   if(StringLen(InpCmdURL) == 0) return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd = (g_peak > 0.0) ? (g_peak - eq) / g_peak * 100.0 : 0.0;
   string sep = (StringFind(InpCmdURL, "?") >= 0) ? "&" : "?";
   string url = InpCmdURL + sep + StringFormat("magic=%I64u&eq=%.2f&peak=%.2f&dd=%.2f&layers=%d&dir=%d&halt=%d&pause=%d",
                InpMagic, eq, g_peak, dd, g_basket.count, g_basket.dir, (int)g_halted, (int)g_paused);
   char   data[], result[];
   string headers;
   ResetLastError();
   int code = WebRequest("GET", url, "", 5000, data, result, headers);
   if(code == -1)
   {
      if(!g_webWarned)
      {
         PrintFormat("[YY] WebRequest ไม่สำเร็จ err=%d (เพิ่ม URL ใน Tools > Options > Expert Advisors)", GetLastError());
         g_webWarned = true;
      }
      return;
   }
   if(code != 200) return;
   string body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
   StringTrimLeft(body); StringTrimRight(body); StringToUpper(body);
   if(body == "PAUSE")            g_pendingCmd = CMD_PAUSE;
   else if(body == "RESUME")      g_pendingCmd = CMD_RESUME;
   else if(body == "CLOSE")       g_pendingCmd = CMD_CLOSE;
   else if(body == "CLOSE_PAUSE") g_pendingCmd = CMD_CLOSE_PAUSE;
}

//+------------------------------------------------------------------+
double CurrentATR()
{
   double buf[1];
   if(CopyBuffer(g_atrHandle, 0, 1, 1, buf) != 1) return 0.0;
   return buf[0];
}

void TryOpenBasket(const int sig)
{
   if(g_halted || g_paused) return;
   if(g_basket.count > 0) return;   // มีชุดค้าง: ไม่เปิดชุดใหม่ (ล็อกทิศ)

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(InpMaxSpreadPts > 0 && spread > InpMaxSpreadPts)
   {
      SetStatus(StringFormat("ข้ามสัญญาณ: spread %d > %d points", (int)spread, InpMaxSpreadPts));
      return;
   }

   double atr = CurrentATR();
   if(atr <= 0.0) { SetStatus("ข้ามสัญญาณ: ATR ยังไม่พร้อม"); return; }

   ENUM_ORDER_TYPE type = (sig == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double spacing = atr * InpGridATR;
   string reason;
   if(!g_budget.Build(_Symbol, type, spacing, g_peak, g_plan, reason))
   {
      SetStatus("ข้ามสัญญาณ: " + reason);
      return;
   }

   double vpp    = YY_ValuePerPricePerLot(_Symbol);
   double target = MathMax(InpTPATR * atr * g_plan.baseLot * vpp, InpMinTPMoney);
   int    spPts  = (int)MathRound(spacing / _Point);
   string cmt    = CYYBasket::MakeComment(1, spPts, g_plan.layers, g_plan.mult, target);

   if(g_trade.Open(type, g_plan.lots[0], cmt))
   {
      g_baskets++;
      SetStatus(StringFormat("เปิดชุด %s · %d ชั้น ×%.1f · ห่าง %d pts · เป้า $%.2f · แย่สุด $%.2f",
                (sig == 1 ? "BUY" : "SELL"), g_plan.layers, g_plan.mult, spPts, target, g_plan.worstLoss));
   }
}

void ManageBasket()
{
   if(g_basket.count == 0) return;
   if(g_basket.mixedDir) SetStatus("เตือน: พบไม้สองทิศใน magic เดียวกัน");

   double target = g_basket.paramsOk ? g_basket.target : InpMinTPMoney;
   double net    = g_basket.profit - g_basket.totalLots * InpCommPerLot;
   if(net >= target)
   {
      int failed = g_trade.CloseAll();
      if(failed == 0)
      {
         g_basketsWin++;
         if(g_basket.topLayer > g_maxLayerHit) g_maxLayerHit = g_basket.topLayer;
         SetStatus(StringFormat("ปิดชุดกำไร $%.2f · ใช้ %d ชั้น", net, g_basket.topLayer));
      }
      return;
   }

   // เพิ่มชั้นเมื่อราคาสวนจากไม้ล่าสุดครบระยะ (ไม่มีพารามิเตอร์ชุด = ไม่เพิ่ม เพื่อความปลอดภัย)
   if(!g_basket.paramsOk || g_basket.topLayer >= g_basket.layers) return;

   double sp  = g_basket.spacingPts * _Point;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   bool add = (g_basket.dir == 1) ? (ask <= g_basket.lastPrice - sp)
                                  : (bid >= g_basket.lastPrice + sp);
   if(!add) return;

   int    k    = g_basket.topLayer + 1;
   double lot  = g_basket.LotForLayer(k);
   ENUM_ORDER_TYPE type = (g_basket.dir == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

   double margin = 0.0;
   double price  = (type == ORDER_TYPE_BUY) ? ask : bid;
   if(!OrderCalcMargin(type, _Symbol, lot, price, margin) ||
      margin > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
   {
      SetStatus(StringFormat("เพิ่มชั้น %d ไม่ได้: margin ไม่พอ", k));
      return;
   }
   if(g_trade.Open(type, lot, StringFormat("GH|L%d", k)))
      SetStatus(StringFormat("เพิ่มชั้น %d/%d · %.2f lot", k, g_basket.layers, lot));
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   if(!g_drawPanel) return;
   double eq   = AccountInfoDouble(ACCOUNT_EQUITY);
   double dd   = (g_peak > 0.0) ? (g_peak - eq) / g_peak * 100.0 : 0.0;
   double stop = g_peak * (1.0 - InpDDCapPct / 100.0);
   string st   = g_halted ? "⛔ หยุดถาวร (แตะเพดาน DD)" : g_paused ? "⏸ หยุดชั่วคราว" : "▶ ทำงาน";
   color  stc  = g_halted ? clrTomato : g_paused ? clrGold : clrLimeGreen;
   string bias = (g_signal.lastBias == 2) ? "ไม่กรอง" : (g_signal.lastBias == 1) ? "ขึ้น ▲" :
                 (g_signal.lastBias == -1) ? "ลง ▼" : "ไม่ชัด";

   int i = 0;
   g_panel.SetLine(i++, "YY Gold Hybrid Grid v1.00", clrGold);
   g_panel.SetLine(i++, "สถานะ: " + st, stc);
   g_panel.SetLine(i++, StringFormat("Equity $%.2f · Peak $%.2f", eq, g_peak));
   g_panel.SetLine(i++, StringFormat("DD %.1f%% / เพดาน %.0f%% (ตัดที่ $%.2f)", dd, InpDDCapPct, stop),
                   dd > InpDDCapPct * 0.7 ? clrTomato : clrWhiteSmoke);

   if(g_basket.count > 0)
   {
      double net = g_basket.profit - g_basket.totalLots * InpCommPerLot;
      g_panel.SetLine(i++, StringFormat("ชุด %s · ชั้น %d/%d · %.2f lot", g_basket.dir == 1 ? "BUY" : "SELL",
                      g_basket.topLayer, g_basket.paramsOk ? g_basket.layers : g_basket.topLayer, g_basket.totalLots),
                      g_basket.dir == 1 ? clrDeepSkyBlue : clrOrange);
      g_panel.SetLine(i++, StringFormat("P/L $%.2f · เป้า $%.2f", net,
                      g_basket.paramsOk ? g_basket.target : InpMinTPMoney), net >= 0 ? clrLimeGreen : clrTomato);
   }
   else
   {
      g_panel.SetLine(i++, "ชุด: ไม่มี (รอสัญญาณ)");
      g_panel.SetLine(i++, g_plan.ok ? StringFormat("แผนล่าสุด: %d ชั้น ×%.1f · แย่สุด $%.2f",
                      g_plan.layers, g_plan.mult, g_plan.worstLoss) : "แผนล่าสุด: -");
   }

   g_panel.SetLine(i++, "Bias: " + bias + (g_signal.State() != 0 ? " · กวาดแล้ว รอ MSS" : ""));
   g_panel.SetLine(i++, StringFormat("ตัวนับ: sweep %d · ผ่าน bias %d · MSS %d · หมดเวลา %d",
                   g_signal.cntSweep, g_signal.cntBias, g_signal.cntMss, g_signal.cntExpire), clrSilver);
   g_panel.SetLine(i++, StringFormat("ชุดทั้งหมด %d · ปิดกำไร %d · ชั้นลึกสุด %d",
                   g_baskets, g_basketsWin, g_maxLayerHit), clrSilver);
   g_panel.SetLine(i++, g_status, clrSilver);
}

//+------------------------------------------------------------------+
void OnTick()
{
   ReadGVCommand();
   ApplyCommand();

   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peak) { g_peak = eq; SaveState(); }

   g_basket.Scan();

   // Hard stop: equity แตะเพดาน DD จาก peak
   double stopLevel = g_peak * (1.0 - InpDDCapPct / 100.0);
   if(!g_halted && eq <= stopLevel)
   {
      g_halted = true;
      g_trade.CloseAll();
      SaveState();
      SetStatus(StringFormat("⛔ แตะเพดาน DD %.0f%% (equity $%.2f ≤ $%.2f) ปิดทุกไม้และหยุด", InpDDCapPct, eq, stopLevel));
      if(!g_isTester) Alert("YY_GoldHybrid_Grid: แตะเพดาน DD ปิดทุกไม้และหยุดทำงาน");
   }
   if(g_halted)
   {
      if(g_basket.count > 0) g_trade.CloseAll();   // ปิดไม่หมด: ลองใหม่ทุก tick
   }
   else
   {
      ManageBasket();
   }

   // สัญญาณ: คำนวณเฉพาะตอนขึ้นแท่งใหม่ (แท่งที่ปิดแล้ว)
   datetime t0 = iTime(_Symbol, _Period, 0);
   if(t0 != g_lastBarTime && t0 != 0)
   {
      g_lastBarTime = t0;
      int sig = g_signal.OnNewBar();
      if(sig != 0)
      {
         g_signals++;
         g_basket.Scan();
         TryOpenBasket(sig);
      }
      if(g_isTester) UpdatePanel();
   }

   if(!g_isTester)
   {
      static uint lastDraw = 0;
      uint now = GetTickCount();
      if(now - lastDraw > 500) { lastDraw = now; UpdatePanel(); }
   }
}

//+------------------------------------------------------------------+
//| เกณฑ์ optimize: Recovery Factor (Net Profit ÷ Max DD)              |
//| ตัดทิ้ง (0) ถ้า Equity DD เกินเพดาน หรือเทรดน้อยกว่า 30 ไม้            |
//+------------------------------------------------------------------+
double OnTester()
{
   double ddPct  = TesterStatistics(STAT_EQUITYDD_PERCENT);
   double trades = TesterStatistics(STAT_TRADES);
   double profit = TesterStatistics(STAT_PROFIT);
   // +2% เผื่อ slippage ตอน hard stop ปิดไม้
   if(trades < 30 || profit <= 0.0 || ddPct > InpDDCapPct + 2.0) return 0.0;
   return TesterStatistics(STAT_RECOVERY_FACTOR);
}
