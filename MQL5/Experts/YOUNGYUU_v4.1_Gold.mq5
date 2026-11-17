//+------------------------------------------------------------------+
//|  YOUNGYUU Master v4.1 — GOLD EDITION                              |
//|  MetaTrader 5 Expert Advisor · XAUUSD Scalping M1/M5              |
//|                                                                   |
//|  v4.1 CHANGELOG (เทียบ v4.0)                                       |
//|  ── ENGINE ─────────────────────────────────────────────────────  |
//|  [NEW] ENGINE_PINE: Wilder ATR (ta.atr/RMA) + ta.supertrend แบบ    |
//|        2 แบนด์ + iADXWilder  → ตรง Pine กว่า v4.0                  |
//|  [KEEP] ENGINE_LEGACY: logic v4.0 เดิม ไว้เทียบ A/B                |
//|  [NEW] HTF Bias filter (optional, trend signals only)             |
//|  [NEW] Max SL (ATR) filter — Swing SL กว้างเกิน = ไม่เข้า          |
//|  ── TRADE LIFECYCLE ────────────────────────────────────────────  |
//|  [FIX] State persistence (GlobalVariables) → restart ไม่ยิง TP1    |
//|  [FIX] P&L ต่อไม้ = รวมทุก deal ของ position (partials+comm+fee)  |
//|  [FIX] จุด Finalize เดียว (กันนับซ้ำ/นับผิด)                         |
//|  [FIX] TP ladder บังคับ TP1 < TP2 < TP3                            |
//|  [FIX] Scalp ใช้ ATR SL จริง                                       |
//|  [FIX] Lock Profit หลัง TP1 + คิดจาก MFE                          |
//|  [FIX] SL modify รวมศูนย์ (Trail/Lock/BE ไม่ชนกัน) + freeze level |
//|  [FIX] Filling mode by symbol, ticket จาก ResultOrder             |
//|  [NEW] Hard TP ฝั่ง server, Time Stop, retry partial/close        |
//|  ── RISK ───────────────────────────────────────────────────────  |
//|  [DEL] Martingale ถูกถอดออก                                        |
//|  [NEW] Fractional Kelly / capped WinStreak / AI Regime Gate (R)   |
//|  [FIX] Max DD จาก Peak Equity — ถาวร + persist ข้าม restart        |
//|  [FIX] Daily start balance persist (restart กลางวันไม่ reset)      |
//|  [NEW] Margin check, Min-lot over-risk guard                      |
//|  [NEW] Spread/ATR filter, Rollover filter, MQL5 Calendar news     |
//|  ── VISUAL ─────────────────────────────────────────────────────  |
//|  [NEW] Glass HUD: KPI, Risk meters, Regime gauge, Confluence      |
//|        chips, AI sparkline, Position track SL→TP3 (คลิกหัวเพื่อย่อ) |
//|  [NEW] On-chart: Supertrend line, Signal arrows + score,          |
//|        blocked-flip markers (hover = เหตุผล), Position zones,      |
//|        Result marks (+R / $)                                      |
//|  [NEW] 3 Themes + Chart theme (restore ตอนถอด EA)                   |
//|  ── DEV ────────────────────────────────────────────────────────  |
//|  [NEW] Parity CSV dump, OnTester custom criterion                 |
//+------------------------------------------------------------------+
#property copyright   "YOUNGYUU Systems"
#property version     "4.10"
#property description "YOUNGYUU v4.1 Gold — Pine-exact engine · Fixed trade lifecycle · Glass HUD"

#include <Trade\Trade.mqh>
CTrade Trade;

//══════════════════════════════════════════════════════════════════
// ENUMS
//══════════════════════════════════════════════════════════════════
enum ENUM_YY_ENGINE
{
   ENGINE_PINE   = 0, // Pine exact (RMA ATR + ta.supertrend + Wilder ADX)
   ENGINE_LEGACY = 1  // Legacy v4.0 (iATR SMA + single band + iADX)
};
enum ENUM_YY_SLMODE
{
   SLM_SWING = 0, // Swing High/Low
   SLM_ATR   = 1, // Dynamic ATR
   SLM_FIXED = 2  // Fixed Points
};
enum ENUM_YY_SCALE
{
   SCM_OFF       = 0, // Off (Fixed Risk %)
   SCM_WINSTREAK = 1, // Win Streak (capped)
   SCM_KELLY     = 2  // Fractional Kelly (AI memory)
};
enum ENUM_YY_GATE
{
   GATE_OFF    = 0, // Off
   GATE_REDUCE = 1, // ลด Risk ใน Regime ที่ Expectancy ติดลบ
   GATE_BLOCK  = 2  // บล็อก Regime ที่ Expectancy ติดลบ
};
enum ENUM_YY_NEWS
{
   NEWS_CALENDAR = 0, // MQL5 Economic Calendar (live only)
   NEWS_MANUAL   = 1, // Manual times (server time)
   NEWS_BOTH     = 2  // Calendar + Manual
};
enum ENUM_YY_THEME
{
   THEME_NEON = 0, // Neon Cyber
   THEME_GOLD = 1, // Royal Gold
   THEME_MONO = 2  // Stealth Mono
};

//══════════════════════════════════════════════════════════════════
// INPUTS
//══════════════════════════════════════════════════════════════════
input group "══════ ⚙️ MAIN ENGINE ══════"
input ENUM_YY_ENGINE p_Engine   = ENGINE_PINE;  // Calculation engine
input int            p_ATR_Len  = 13;           // ATR / ADX Length
input double         p_BaseMult = 2.5;          // Supertrend Factor

input group "══════ 🤖 AUTO SENSITIVITY ══════"
input bool   p_AutoSens   = true;
input int    p_ADX_Manual = 18;
input double p_BBW_Manual = 0.004;

input group "══════ 📊 SIDEWAYS SCALP MODE ══════"
input bool   p_UseScalp   = true;
input int    p_ScalpRange = 20;
input double p_ScalpTP    = 0.8;
input double p_ScalpSL    = 0.5;
input bool   p_ScalpATRSL = true;   // Scalp ใช้ SL = ScalpSL x ATR (v4.0 ใช้ Swing)

input group "══════ 💪 TREND STRENGTH FILTER ══════"
input bool   p_UseTSF   = true;
input int    p_TSF_Look = 50;
input double p_TSF_Min  = 1.05;

input group "══════ ✅ CONFIRMATION ══════"
input bool p_UseEMA      = true;
input int  p_EMA_Len     = 21;
input bool p_UseRSI      = true;
input int  p_RSI_Len     = 14;
input int  p_RSI_OB      = 70;
input int  p_RSI_OS      = 30;
input bool p_UseMomentum = true;
input bool p_UseBody     = true;

input group "══════ 🧭 HTF BIAS ══════"
input bool            p_UseHTF  = false;      // ใช้ HTF EMA กรองสัญญาณ Trend
input ENUM_TIMEFRAMES p_HTF_TF  = PERIOD_M15;
input int             p_HTF_EMA = 50;

input group "══════ 🛡️ STOP LOSS ══════"
input ENUM_YY_SLMODE p_SL_Mode = SLM_SWING;
input int    p_Swing_Len   = 10;
input double p_SL_ATR_Mult = 1.5;
input int    p_SL_Pips     = 500;   // Fixed SL (points)
input double p_SL_Buffer   = 0.3;
input double p_MaxSL_ATR   = 4.0;   // SL กว้างเกินกี่ ATR = ไม่เข้า (0=ปิด)

input group "══════ 🎯 TAKE PROFIT ══════"
input int    p_TP_Levels = 3;       // 1-3
input double p_TP1_Mult  = 1.5;
input double p_TP2_Mult  = 3.0;
input double p_TP3_Mult  = 5.0;
input bool   p_ServerTP  = true;    // ตั้ง Hard TP ฝั่ง Server ที่ TP สุดท้าย

input group "══════ 📈 SUPER TRAILING / LOCK PROFIT ══════"
input bool   p_UseTrail      = true;
input int    p_TrailStart    = 1;     // เริ่ม Trail หลัง TP# (0 = ทันที)
input double p_TrailATR      = 1.5;
input double p_TrailStep     = 0.3;
input bool   p_UseBreakeven  = true;
input int    p_BE_ExtraPts   = 0;     // เผื่อค่าคอมฯ (points) เพิ่มจาก spread x1.5
input bool   p_AdaptTrail    = true;
input bool   p_UseLockProfit = true;
input bool   p_LockAfterTP1  = true;  // Lock เริ่มหลัง TP1 เท่านั้น
input double p_LockMinATR    = 1.0;   // MFE ขั้นต่ำก่อน Lock (ATR)
input double p_LockStep      = 0.5;
input double p_LockPct       = 70.0;

input group "══════ ⏱️ TIME STOP ══════"
input bool   p_UseTimeStop    = true;
input int    p_TimeStopBars   = 30;   // ยังไม่ถึง TP1 ภายใน N แท่ง
input double p_TimeStopMinATR = 0.5;  // และ MFE < x ATR → ปิด

input group "══════ 💰 RISK & MONEY MANAGEMENT ══════"
input double p_Risk_Pct        = 1.0;
input double p_Max_Lot         = 10.0;
input double p_Min_Lot         = 0.01;
input double p_PC1_Pct         = 33.0;
input double p_PC2_Pct         = 50.0;
input double p_RR_Min          = 1.5;
input double p_MaxMarginPct    = 30.0;  // ใช้ Free Margin สูงสุด %
input double p_MaxRiskOverMult = 1.5;   // Min lot ทำให้ Risk เกินกี่เท่า = ไม่เข้า

input group "══════ 📊 ADAPTIVE SIZING (ไม่มี Martingale) ══════"
input ENUM_YY_SCALE p_ScaleMode     = SCM_OFF;
input double        p_ScaleFactor   = 1.15;
input int           p_MaxScale      = 3;
input double        p_KellyFrac     = 0.25;
input double        p_RiskCapMult   = 2.0;  // Risk สูงสุด = Risk% x
input double        p_RiskFloorMult = 0.5;  // Risk ต่ำสุด = Risk% x

input group "══════ 🔴 DAILY / ACCOUNT PROTECTION ══════"
input bool   p_UseDailyLim  = true;
input double p_Daily_Loss   = 3.0;
input double p_Daily_Profit = 6.0;
input int    p_Max_ConLoss  = 3;
input int    p_Cooldown     = 30;
input double p_MaxDD_Pct    = 10.0;   // จาก Peak Equity — หยุดถาวร
input bool   p_ResetDDKill  = false;  // true = ล้าง DD Kill + Peak ตอนโหลด EA

input group "══════ 🕐 SESSION / ROLLOVER ══════"
input bool   p_UseSession   = true;
input int    p_London_Open  = 7;
input int    p_London_Close = 16;
input int    p_NY_Open      = 12;
input int    p_NY_Close     = 20;
input bool   p_Trade_Asia   = false;
input int    p_GMTOffset    = 0;        // บวกกับเวลา Server ให้เป็น GMT (Server GMT+2 → -2)
input bool   p_UseRollover  = true;
input string p_Roll_Start   = "23:50";  // Server time
input string p_Roll_End     = "01:10";

input group "══════ 📡 SPREAD FILTER ══════"
input bool   p_UseSpread    = true;
input int    p_Max_Spread   = 500;    // Hard cap (points)
input double p_MaxSpreadATR = 0.10;   // Spread ≤ x ATR (0=ปิด)

input group "══════ 📰 NEWS FILTER ══════"
input bool         p_UseNews      = true;
input ENUM_YY_NEWS p_NewsSource   = NEWS_BOTH;
input string       p_NewsCurrency = "USD";
input int          p_News_Before  = 30;
input int          p_News_After   = 30;
input string       p_News_Times   = "13:30,15:00,17:00,19:00,20:30"; // Manual (server time)

input group "══════ 🤖 AI ADAPTIVE CORE ══════"
input bool         p_UseAI         = true;
input int          p_AI_Memory     = 30;      // 5-200 ไม้
input double       p_AI_WinThresh  = 0.55;
input double       p_AI_LossThresh = 0.40;
input ENUM_YY_GATE p_AI_GateMode   = GATE_REDUCE;
input int          p_AI_GateMinN   = 10;      // ไม้ขั้นต่ำต่อ Regime ก่อน Gate ทำงาน
input double       p_AI_GateMinExp = 0.0;     // Expectancy ขั้นต่ำ (R)

input group "══════ 🎨 HUD & CHART VISUALS ══════"
input bool          p_ShowDash    = true;
input ENUM_YY_THEME p_Theme       = THEME_NEON;
input int           p_Dash_X      = 10;
input int           p_Dash_Y      = 25;
input bool          p_ChartTheme  = true;   // เปลี่ยนสีกราฟตาม Theme (คืนค่าตอนถอด)
input bool          p_ShowSignals = true;
input bool          p_ShowSTLine  = true;
input int           p_STLineBars  = 150;
input bool          p_ShowZones   = true;

input group "══════ ⚡ EA SETTINGS ══════"
input int  p_Magic      = 202404;
input int  p_Slippage   = 20;
input bool p_Debug      = false;
input bool p_ParityDump = false;   // เขียน CSV เทียบ Pine (Common\Files)

//══════════════════════════════════════════════════════════════════
// CONSTANTS
//══════════════════════════════════════════════════════════════════
#define OBJ       "YY41_"
#define CALC_BARS 700
#define DW        320
#define SPARK_N   20
#define FONT_UI   "Segoe UI"
#define FONT_B    "Segoe UI Semibold"
#define FONT_M    "Consolas"

//══════════════════════════════════════════════════════════════════
// STRUCTS
//══════════════════════════════════════════════════════════════════
struct SignalData
{
   bool   valid;
   bool   buy, sell, is_scalp;
   bool   trend_buy, trend_sell, scalp_buy, scalp_sell;
   bool   strong_trend, weak_trend, sideways, pass_st;
   double atr, adx, adx_thresh, bbw, bbw_thresh, tsf_ratio, ema, rsi, htf_ema;
   double body_ratio, body_min;
   int    st_dir, st_dir_prev;
   double st_band;
   double range_high, range_low, range_mid;
   double sl_price, tp1, tp2, tp3;
   int    ch_st, ch_reg, ch_ema, ch_rsi, ch_body, ch_mom, ch_htf; // 2=pass 1=partial 0=fail -1=off
   string block_reason;
};

struct TradeState
{
   ulong    ticket;
   int      dir;
   double   entry, sl_init, sl, tp1, tp2, tp3;
   double   orig_vol, risk_money, mfe_price, trail_ref, adx_entry;
   bool     tp1_hit, tp2_hit, tp3_hit, be_done, trail_active, lock_active, p1_done, p2_done;
   bool     is_scalp, is_strong, nostate;
   int      regime, lock_level, fin_tries, pc_fail;
   datetime open_time;
};

struct RiskData
{
   double   day_start_bal, daily_pnl, peak_equity, current_dd, max_dd;
   double   total_profit, total_loss;
   int      consec_loss, trades_today, wins_today, losses_today;
   int      total_trades, total_wins, total_losses;
   datetime cooldown_until, day_start;
   bool     limit_hit, dd_kill;
   string   limit_reason;
};

struct AIStats
{
   int    n, wins, consec_w, consec_l, max_w, max_l;
   double wr, pf, exp_r, avg_win_r, avg_loss_r, risk_mult, confidence;
   string signal;
};

struct Palette
{
   color bg, panel, card, border, accent, gold, text, muted;
   color good, bad, warn, off, track, goodDim, badDim, warnDim;
   color zr, z1, z2, z3, candleUp, candleDn;
};

//══════════════════════════════════════════════════════════════════
// GLOBALS
//══════════════════════════════════════════════════════════════════
SignalData G_Sig,   G_EmptySig;
TradeState G_Trade, G_EmptyTrade;
RiskData   G_Risk,  G_EmptyRisk;
AIStats    G_AI,    G_EmptyAI;
Palette    P;

// AI ring buffer
double AI_Pnl[], AI_R[];
int    AI_Reg[];
int    AI_Size = 30, AI_Count = 0, AI_Head = 0;

// Supertrend engine series (index 0 = forming bar)
double   ST_Band[], ST_Atr[];
int      ST_Dir[];
datetime ST_Time[];
int      ST_Got = 0;

int hATR = INVALID_HANDLE, hADX = INVALID_HANDLE, hEMA = INVALID_HANDLE;
int hRSI = INVALID_HANDLE, hBB  = INVALID_HANDLE, hHTF = INVALID_HANDLE;

datetime G_LastBar = 0;
bool     G_IsTester = false, G_IsVisual = true;
bool     G_HudMin = false, G_HudBuilt = false;
bool     G_PendingOpen = false;
datetime G_PendingSince = 0;
ulong    G_LastHudMs = 0, G_LastModMs = 0;
double   G_NextLot = 0;
datetime G_NewsCacheT = 0;
bool     G_NewsCacheBlock = false;
string   G_NewsCacheName = "";
int      G_RollS = -1, G_RollE = -1;
int      G_ParityFH = INVALID_HANDLE;

// HUD layout anchors
int G_MeterX = 0, G_MeterW = 0, G_AIBarX = 0, G_AIBarW = 0;
int G_SparkX = 0, G_SparkY = 0, G_SparkH = 0, G_SparkBW = 0;
int G_TrkX = 0, G_TrkW = 0, G_TrkY = 0;

// Saved chart colors
bool G_ChartApplied = false;
long G_CBg, G_CFg, G_CGrid, G_CUp, G_CDn, G_CBull, G_CBear, G_CLine, G_CShowGrid, G_CMode, G_CFore;

//══════════════════════════════════════════════════════════════════
// SMALL HELPERS
//══════════════════════════════════════════════════════════════════
string GKey(string k)          { return "YY41_" + IntegerToString(p_Magic) + "_" + _Symbol + "_" + k; }
string TKey(ulong t, string k) { return "YY41_T" + IntegerToString((long)t) + "_" + k; }
double GGet(string name, double def) { return GlobalVariableCheck(name) ? GlobalVariableGet(name) : def; }

double ValuePerPrice()
{
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   return (ts > 0 && tv > 0) ? tv / ts : 0;
}

int VolDigits()
{
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0) return 2;
   int d = (int)MathRound(-MathLog10(step));
   return MathMax(0, MathMin(8, d));
}

double MinStopDist(int extra)
{
   long st = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long fz = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)(MathMax(st, fz) + extra) * _Point;
}

int GetSpread() { return (int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD); }

int ParseHHMM(string s)
{
   string p[];
   if(StringSplit(s, ':', p) < 2) return -1;
   int h = (int)StringToInteger(p[0]), m = (int)StringToInteger(p[1]);
   if(h < 0 || h > 23 || m < 0 || m > 59) return -1;
   return h * 60 + m;
}

string TFName() { return StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7); }

string Money(double v, bool sign = false)
{
   string s  = DoubleToString(MathAbs(v), 2);
   int dot   = StringFind(s, ".");
   string ip = StringSubstr(s, 0, dot), fp = StringSubstr(s, dot);
   string out = "";
   int L = StringLen(ip);
   for(int i = 0; i < L; i++)
   {
      out += StringSubstr(ip, i, 1);
      int rem = L - 1 - i;
      if(rem > 0 && rem % 3 == 0) out += ",";
   }
   string pre = (v < 0) ? "-" : (sign ? "+" : "");
   return pre + "$" + out + fp;
}

bool Better(double a, double b, int dir)
{
   if(b <= 0) return true;
   return (dir == 1) ? (a > b + _Point * 0.5) : (a < b - _Point * 0.5);
}

bool Throttle()
{
   if(G_IsTester) return true;
   ulong now = GetTickCount64();
   if(now - G_LastModMs < 500) return false;
   G_LastModMs = now;
   return true;
}

int CurrentRegime()     { return G_Sig.strong_trend ? 1 : (G_Sig.weak_trend ? 0 : -1); }
string RegimeName(int r){ return r == 1 ? "STRONG" : (r == 0 ? "WEAK" : (r == -1 ? "SIDE" : "N/A")); }

int ParseRegime(string c)
{
   if(StringFind(c, "|STRONG") >= 0) return 1;
   if(StringFind(c, "|WEAK")   >= 0) return 0;
   if(StringFind(c, "|SCALP")  >= 0) return -1;
   return -9;
}

double ParseRisk(string c)
{
   int p = StringFind(c, "|r");
   if(p < 0) return 0;
   return StringToDouble(StringSubstr(c, p + 2));
}

datetime GetDayStart()
{
   MqlDateTime d; TimeToStruct(TimeCurrent(), d);
   d.hour = 0; d.min = 0; d.sec = 0;
   return StructToTime(d);
}

int CountPositions()
{
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == p_Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) c++;
   }
   return c;
}

ulong FindTick()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetInteger(POSITION_MAGIC) == p_Magic && PositionGetString(POSITION_SYMBOL) == _Symbol) return t;
   }
   return 0;
}

double LastTP()
{
   if(p_TP_Levels >= 3) return G_Trade.tp3;
   if(p_TP_Levels == 2) return G_Trade.tp2;
   return G_Trade.tp1;
}

bool Reached(double cp, double tp)
{
   if(tp <= 0) return false;
   return (G_Trade.dir == 1) ? (cp >= tp) : (cp <= tp);
}

//══════════════════════════════════════════════════════════════════
// THEME
//══════════════════════════════════════════════════════════════════
void SetTheme()
{
   if(p_Theme == THEME_GOLD)
   {
      P.bg = C'14,11,6';    P.panel = C'22,17,9';   P.card = C'28,22,12';  P.border = C'72,56,26';
      P.accent = C'255,196,60'; P.gold = C'255,214,102'; P.text = C'245,236,214'; P.muted = C'160,140,100';
      P.good = C'130,220,120'; P.bad = C'240,96,84'; P.warn = C'255,170,40'; P.off = C'84,70,46';
      P.track = C'40,32,18'; P.goodDim = C'26,50,24'; P.badDim = C'62,22,16'; P.warnDim = C'64,44,10';
      P.zr = C'54,22,16'; P.z1 = C'30,40,18'; P.z2 = C'36,50,20'; P.z3 = C'44,60,22';
      P.candleUp = C'240,200,100'; P.candleDn = C'120,88,58';
   }
   else if(p_Theme == THEME_MONO)
   {
      P.bg = C'10,10,12';   P.panel = C'18,18,21';  P.card = C'24,24,28';  P.border = C'50,50,58';
      P.accent = C'230,230,235'; P.gold = C'255,255,255'; P.text = C'235,235,240'; P.muted = C'130,130,140';
      P.good = C'110,231,183'; P.bad = C'252,129,129'; P.warn = C'250,204,21'; P.off = C'70,70,78';
      P.track = C'36,36,42'; P.goodDim = C'20,48,38'; P.badDim = C'56,24,24'; P.warnDim = C'52,44,10';
      P.zr = C'46,24,26'; P.z1 = C'22,40,34'; P.z2 = C'24,48,40'; P.z3 = C'26,56,46';
      P.candleUp = C'200,200,205'; P.candleDn = C'90,90,98';
   }
   else
   {
      P.bg = C'7,9,18';     P.panel = C'11,14,28';  P.card = C'15,19,36';  P.border = C'32,40,72';
      P.accent = C'0,210,255'; P.gold = C'255,204,64'; P.text = C'226,233,247'; P.muted = C'112,124,158';
      P.good = C'0,229,143'; P.bad = C'255,77,109'; P.warn = C'255,193,7'; P.off = C'58,66,96';
      P.track = C'24,30,54'; P.goodDim = C'0,52,38'; P.badDim = C'64,16,30'; P.warnDim = C'60,46,4';
      P.zr = C'52,16,30'; P.z1 = C'6,40,36'; P.z2 = C'6,52,44'; P.z3 = C'6,64,52';
      P.candleUp = C'0,200,150'; P.candleDn = C'240,70,100';
   }
}

void ApplyChartTheme()
{
   G_CBg       = ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   G_CFg       = ChartGetInteger(0, CHART_COLOR_FOREGROUND);
   G_CGrid     = ChartGetInteger(0, CHART_COLOR_GRID);
   G_CUp       = ChartGetInteger(0, CHART_COLOR_CHART_UP);
   G_CDn       = ChartGetInteger(0, CHART_COLOR_CHART_DOWN);
   G_CBull     = ChartGetInteger(0, CHART_COLOR_CANDLE_BULL);
   G_CBear     = ChartGetInteger(0, CHART_COLOR_CANDLE_BEAR);
   G_CLine     = ChartGetInteger(0, CHART_COLOR_CHART_LINE);
   G_CShowGrid = ChartGetInteger(0, CHART_SHOW_GRID);
   G_CMode     = ChartGetInteger(0, CHART_MODE);
   G_CFore     = ChartGetInteger(0, CHART_FOREGROUND);

   ChartSetInteger(0, CHART_COLOR_BACKGROUND, P.bg);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, P.muted);
   ChartSetInteger(0, CHART_COLOR_GRID, P.track);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   ChartSetInteger(0, CHART_MODE, CHART_CANDLES);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, P.candleUp);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, P.candleUp);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, P.candleDn);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, P.candleDn);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, P.muted);
   ChartSetInteger(0, CHART_FOREGROUND, false);
   G_ChartApplied = true;
}

void RestoreChartTheme()
{
   if(!G_ChartApplied) return;
   ChartSetInteger(0, CHART_COLOR_BACKGROUND, G_CBg);
   ChartSetInteger(0, CHART_COLOR_FOREGROUND, G_CFg);
   ChartSetInteger(0, CHART_COLOR_GRID, G_CGrid);
   ChartSetInteger(0, CHART_COLOR_CHART_UP, G_CUp);
   ChartSetInteger(0, CHART_COLOR_CHART_DOWN, G_CDn);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BULL, G_CBull);
   ChartSetInteger(0, CHART_COLOR_CANDLE_BEAR, G_CBear);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, G_CLine);
   ChartSetInteger(0, CHART_SHOW_GRID, G_CShowGrid);
   ChartSetInteger(0, CHART_MODE, G_CMode);
   ChartSetInteger(0, CHART_FOREGROUND, G_CFore);
   G_ChartApplied = false;
}

//══════════════════════════════════════════════════════════════════
// ON INIT / DEINIT
//══════════════════════════════════════════════════════════════════
int OnInit()
{
   G_IsTester = (bool)MQLInfoInteger(MQL_TESTER);
   G_IsVisual = !G_IsTester || (bool)MQLInfoInteger(MQL_VISUAL_MODE);

   if(p_Risk_Pct <= 0 || p_TP_Levels < 1 || p_TP_Levels > 3 || p_ATR_Len < 2 || p_TSF_Look < 2)
   {
      Print("❌ Invalid inputs: Risk%>0, TP_Levels 1-3, ATR_Len>=2, TSF_Look>=2");
      return INIT_PARAMETERS_INCORRECT;
   }

   Trade.SetExpertMagicNumber(p_Magic);
   Trade.SetDeviationInPoints(p_Slippage);
   Trade.SetTypeFillingBySymbol(_Symbol);
   Trade.SetAsyncMode(false);
   Trade.LogLevel(p_Debug ? LOG_LEVEL_ALL : LOG_LEVEL_ERRORS);

   if(p_Engine == ENGINE_LEGACY)
   {
      hATR = iATR(_Symbol, PERIOD_CURRENT, p_ATR_Len);
      hADX = iADX(_Symbol, PERIOD_CURRENT, p_ATR_Len);
   }
   else
      hADX = iADXWilder(_Symbol, PERIOD_CURRENT, p_ATR_Len);

   hEMA = iMA(_Symbol, PERIOD_CURRENT, p_EMA_Len, 0, MODE_EMA, PRICE_CLOSE);
   hRSI = iRSI(_Symbol, PERIOD_CURRENT, p_RSI_Len, PRICE_CLOSE);
   hBB  = iBands(_Symbol, PERIOD_CURRENT, 20, 0, 2.0, PRICE_CLOSE);
   if(p_UseHTF) hHTF = iMA(_Symbol, p_HTF_TF, p_HTF_EMA, 0, MODE_EMA, PRICE_CLOSE);

   if((p_Engine == ENGINE_LEGACY && hATR == INVALID_HANDLE) || hADX == INVALID_HANDLE ||
      hEMA == INVALID_HANDLE || hRSI == INVALID_HANDLE || hBB == INVALID_HANDLE ||
      (p_UseHTF && hHTF == INVALID_HANDLE))
   {
      Print("❌ Indicator handles failed: ", GetLastError());
      return INIT_FAILED;
   }

   // Reset globals (EA globals survive TF change)
   G_Sig = G_EmptySig; G_Trade = G_EmptyTrade; G_Risk = G_EmptyRisk; G_AI = G_EmptyAI;
   G_LastBar = 0; G_PendingOpen = false; G_NewsCacheT = 0; G_HudBuilt = false;

   AI_Size = MathMax(5, MathMin(p_AI_Memory, 200));
   ArrayResize(AI_Pnl, AI_Size); ArrayResize(AI_R, AI_Size); ArrayResize(AI_Reg, AI_Size);
   ArrayInitialize(AI_Pnl, 0); ArrayInitialize(AI_R, 0); ArrayInitialize(AI_Reg, -9);
   AI_Count = 0; AI_Head = 0;

   G_RollS = ParseHHMM(p_Roll_Start);
   G_RollE = ParseHHMM(p_Roll_End);

   // Persistence
   if(G_IsTester) GlobalVariablesDeleteAll("YY41_");
   if(p_ResetDDKill)
   {
      GlobalVariableDel(GKey("peak")); GlobalVariableDel(GKey("ddkill")); GlobalVariableDel(GKey("maxdd"));
   }
   double eq = AccountInfoDouble(ACCOUNT_EQUITY), bal = AccountInfoDouble(ACCOUNT_BALANCE);
   G_Risk.peak_equity    = MathMax(eq, GGet(GKey("peak"), eq));
   G_Risk.dd_kill        = GGet(GKey("ddkill"), 0) > 0.5;
   G_Risk.max_dd         = GGet(GKey("maxdd"), 0);
   G_Risk.cooldown_until = (datetime)(long)GGet(GKey("cool"), 0);
   G_Risk.day_start      = GetDayStart();
   if((datetime)(long)GGet(GKey("dayt"), 0) == G_Risk.day_start)
      G_Risk.day_start_bal = GGet(GKey("daybal"), bal);
   else
   {
      G_Risk.day_start_bal = bal;
      GlobalVariableSet(GKey("dayt"), (double)G_Risk.day_start);
      GlobalVariableSet(GKey("daybal"), bal);
   }
   if(G_Risk.dd_kill) { G_Risk.limit_hit = true; G_Risk.limit_reason = "MAX DD KILL"; }

   SetTheme();
   LoadTradeHistory();
   ComputeAIStats();
   ScanExistingPositions();
   CalcSignals(G_Sig); // อาจยังไม่พร้อม — จะคำนวณใหม่ที่แท่งถัดไป

   if(p_UseNews && p_NewsSource == NEWS_CALENDAR && G_IsTester)
      Print("⚠️ News source = Calendar ใช้ใน Tester ไม่ได้ → ไม่มี news filter ใน backtest (ใช้ BOTH/MANUAL)");

   if(G_IsVisual)
   {
      if(p_ChartTheme) ApplyChartTheme();
      if(p_ShowDash) BuildHUD();
      EventSetMillisecondTimer(500);
   }

   if(p_ParityDump)
   {
      string fn = "YY_parity_" + _Symbol + "_" + TFName() + ".csv";
      G_ParityFH = FileOpen(fn, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ',');
      if(G_ParityFH != INVALID_HANDLE)
         FileWrite(G_ParityFH, "time", "st_dir", "st_band", "atr", "adx", "bbw", "ema", "rsi");
   }

   Print("══════════════════════════════════════════");
   Print(" YOUNGYUU v4.1 GOLD | ", _Symbol, " | ", TFName(), " | Engine: ", EnumToString(p_Engine));
   Print(" Magic:", p_Magic, " Risk:", p_Risk_Pct, "% | Sizing:", EnumToString(p_ScaleMode),
         " | AI:", p_UseAI ? "ON" : "OFF", " Gate:", EnumToString(p_AI_GateMode));
   Print(" Peak EQ:", DoubleToString(G_Risk.peak_equity, 2), " DayStartBal:", DoubleToString(G_Risk.day_start_bal, 2),
         G_Risk.dd_kill ? " | ⛔ DD KILL ACTIVE" : "");
   Print("══════════════════════════════════════════");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   ObjectsDeleteAll(0, OBJ);
   RestoreChartTheme();
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX != INVALID_HANDLE) IndicatorRelease(hADX);
   if(hEMA != INVALID_HANDLE) IndicatorRelease(hEMA);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hBB  != INVALID_HANDLE) IndicatorRelease(hBB);
   if(hHTF != INVALID_HANDLE) IndicatorRelease(hHTF);
   hATR = hADX = hEMA = hRSI = hBB = hHTF = INVALID_HANDLE;
   if(G_ParityFH != INVALID_HANDLE) { FileClose(G_ParityFH); G_ParityFH = INVALID_HANDLE; }
   ChartRedraw(0);
}

//══════════════════════════════════════════════════════════════════
// ON TICK / TIMER / CHART EVENT
//══════════════════════════════════════════════════════════════════
void OnTick()
{
   UpdateRisk();

   if(G_PendingOpen)
   {
      ulong t = FindTick();
      if(t > 0) { G_Trade.ticket = t; G_PendingOpen = false; SaveState(); }
      else if(TimeCurrent() - G_PendingSince > 10) { G_PendingOpen = false; G_Trade = G_EmptyTrade; }
   }

   if(G_Trade.ticket > 0) ManagePosition();

   if(IsNewBar())
   {
      if(!CalcSignals(G_Sig))
         G_LastBar = 0; // ข้อมูลยังไม่พร้อม → ลองใหม่ tick ถัดไป
      else
      {
         if(G_IsVisual) { DrawSTLine(); DrawSignalMarks(); }
         if(G_ParityFH != INVALID_HANDLE) DumpParity();
         if(G_Trade.ticket > 0) { CheckTimeStop(); SaveState(); }
         RefreshNextLot();

         string why = "";
         bool fresh = (TimeCurrent() - iTime(_Symbol, PERIOD_CURRENT, 0)) < PeriodSeconds() / 2;
         if(fresh && AllowTrading(why) && G_Trade.ticket == 0 && !G_PendingOpen && CountPositions() == 0)
         {
            if(G_Sig.buy)       OpenTrade(ORDER_TYPE_BUY);
            else if(G_Sig.sell) OpenTrade(ORDER_TYPE_SELL);
         }
      }
   }

   if(G_IsVisual && p_ShowDash)
   {
      ulong now = GetTickCount64();
      if(now - G_LastHudMs >= 250) { G_LastHudMs = now; UpdateHUD(); }
   }
}

void OnTimer()
{
   if(G_IsVisual && p_ShowDash) UpdateHUD();
}

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK || !p_ShowDash) return;
   if(StringFind(sparam, OBJ + "H_HD") == 0 || sparam == OBJ + "H_TOG")
   {
      G_HudMin = !G_HudMin;
      BuildHUD();
   }
}

bool IsNewBar()
{
   datetime cur = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(cur == 0) return false;
   if(cur != G_LastBar) { G_LastBar = cur; return true; }
   return false;
}

//══════════════════════════════════════════════════════════════════
// FILTERS
//══════════════════════════════════════════════════════════════════
bool AllowTrading(string &why)
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.day_of_week == 0 || dt.day_of_week == 6)      { why = "Weekend"; return false; }
   if(G_Risk.dd_kill)                                  { why = "MAX DD KILL"; return false; }
   if(p_UseDailyLim && G_Risk.limit_hit)               { why = G_Risk.limit_reason; return false; }
   if(CooldownActive())                                { why = "Cooldown → " + TimeToString(G_Risk.cooldown_until, TIME_MINUTES); return false; }
   if(p_UseSession && !SessionOK())                    { why = "Out of session"; return false; }
   if(p_UseRollover && InRollover())                   { why = "Rollover window"; return false; }
   if(p_UseSpread && !SpreadOK())                      { why = "Spread too wide"; return false; }
   string ev = "";
   if(p_UseNews && NewsBlocked(ev))                    { why = "News: " + ev; return false; }
   if(!G_IsTester && (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED)))
                                                       { why = "AutoTrading OFF"; return false; }
   if(p_UseAI && !AIAllowTrade(why)) return false;
   why = "Ready";
   return true;
}

bool AIAllowTrade(string &why)
{
   if(G_AI.n >= 5 && G_AI.wr < 0.25 && G_AI.consec_l >= p_Max_ConLoss)
   { why = "AI: losing streak lock"; return false; }
   if(p_AI_GateMode == GATE_BLOCK && G_Sig.valid)
   {
      double e; int n;
      if(RegimeGateFails(CurrentRegime(), e, n))
      { why = StringFormat("AI gate: %s %+.2fR (n%d)", RegimeName(CurrentRegime()), e, n); return false; }
   }
   return true;
}

bool SessionOK()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = (dt.hour + p_GMTOffset + 24) % 24;
   if(dt.day_of_week == 0 || dt.day_of_week == 6) return false;
   if(dt.day_of_week == 5 && h >= 19) return false;
   bool london = (h >= p_London_Open && h < p_London_Close);
   bool ny     = (h >= p_NY_Open && h < p_NY_Close);
   bool asia   = p_Trade_Asia && (h >= 0 && h < 6);
   return london || ny || asia;
}

string GetSessionStr()
{
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int h = (dt.hour + p_GMTOffset + 24) % 24;
   bool lo = (h >= p_London_Open && h < p_London_Close), ny = (h >= p_NY_Open && h < p_NY_Close);
   if(lo && ny) return "LDN+NY";
   if(lo) return "LONDON";
   if(ny) return "NEW YORK";
   if(h >= 0 && h < 6) return "ASIA";
   return "CLOSED";
}

bool InRollover()
{
   if(G_RollS < 0 || G_RollE < 0) return false;
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   int m = dt.hour * 60 + dt.min;
   if(G_RollS <= G_RollE) return (m >= G_RollS && m < G_RollE);
   return (m >= G_RollS || m < G_RollE);
}

bool SpreadOK()
{
   int sp = GetSpread();
   if(sp > p_Max_Spread) return false;
   if(p_MaxSpreadATR > 0 && G_Sig.atr > 0 && sp * _Point > p_MaxSpreadATR * G_Sig.atr) return false;
   return true;
}

bool NewsBlocked(string &ev)
{
   datetime now = TimeCurrent();
   ev = "";
   if(p_NewsSource != NEWS_MANUAL && !G_IsTester)
   {
      if(now - G_NewsCacheT >= 60)
      {
         G_NewsCacheT = now;
         G_NewsCacheName = "";
         G_NewsCacheBlock = CalendarBlock(now, G_NewsCacheName);
      }
      if(G_NewsCacheBlock) { ev = G_NewsCacheName; return true; }
   }
   if(p_NewsSource != NEWS_CALENDAR && ManualNewsBlock(now)) { ev = "Manual window"; return true; }
   return false;
}

bool CalendarBlock(datetime now, string &name)
{
   MqlCalendarValue vals[];
   datetime from = now - p_News_After * 60;
   datetime to   = now + p_News_Before * 60;
   int n = CalendarValueHistory(vals, from, to, NULL, p_NewsCurrency);
   for(int i = 0; i < n; i++)
   {
      MqlCalendarEvent e;
      if(!CalendarEventById(vals[i].event_id, e)) continue;
      if(e.importance != CALENDAR_IMPORTANCE_HIGH) continue;
      name = e.name;
      return true;
   }
   return false;
}

bool ManualNewsBlock(datetime now)
{
   if(StringLen(p_News_Times) == 0) return false;
   MqlDateTime dt; TimeToStruct(now, dt);
   string times[];
   int n = StringSplit(p_News_Times, ',', times);
   for(int i = 0; i < n; i++)
   {
      string t = times[i]; StringTrimLeft(t); StringTrimRight(t);
      int mm = ParseHHMM(t);
      if(mm < 0) continue;
      MqlDateTime nd = dt; nd.hour = mm / 60; nd.min = mm % 60; nd.sec = 0;
      long d = (long)(now - StructToTime(nd));
      if(d >= -(long)p_News_Before * 60 && d <= (long)p_News_After * 60) return true;
   }
   return false;
}

bool CooldownActive() { return G_Risk.cooldown_until > 0 && TimeCurrent() < G_Risk.cooldown_until; }

//══════════════════════════════════════════════════════════════════
// RISK STATE (every tick)
//══════════════════════════════════════════════════════════════════
void UpdateRisk()
{
   datetime today = GetDayStart();
   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);

   if(today != G_Risk.day_start)
   {
      G_Risk.day_start = today;
      G_Risk.day_start_bal = bal;
      G_Risk.daily_pnl = 0;
      G_Risk.trades_today = 0; G_Risk.wins_today = 0; G_Risk.losses_today = 0;
      if(G_Risk.limit_hit && !G_Risk.dd_kill) { G_Risk.limit_hit = false; G_Risk.limit_reason = ""; }
      GlobalVariableSet(GKey("dayt"), (double)today);
      GlobalVariableSet(GKey("daybal"), bal);
   }

   G_Risk.daily_pnl = eq - G_Risk.day_start_bal;

   if(eq > G_Risk.peak_equity)
   {
      G_Risk.peak_equity = eq;
      GlobalVariableSet(GKey("peak"), eq);
   }
   G_Risk.current_dd = (G_Risk.peak_equity > 0) ? (G_Risk.peak_equity - eq) / G_Risk.peak_equity * 100.0 : 0;
   if(G_Risk.current_dd > G_Risk.max_dd)
   {
      G_Risk.max_dd = G_Risk.current_dd;
      GlobalVariableSet(GKey("maxdd"), G_Risk.max_dd);
   }

   if(p_MaxDD_Pct > 0 && G_Risk.current_dd >= p_MaxDD_Pct && !G_Risk.dd_kill)
   {
      G_Risk.dd_kill = true; G_Risk.limit_hit = true; G_Risk.limit_reason = "MAX DD KILL";
      GlobalVariableSet(GKey("ddkill"), 1);
      Print("⛔ MAX DRAWDOWN KILL: ", DoubleToString(G_Risk.current_dd, 2), "% — หยุดเทรดถาวร (ตั้ง p_ResetDDKill=true เพื่อปลด)");
   }

   if(!p_UseDailyLim || G_Risk.limit_hit || G_Risk.day_start_bal <= 0) return;
   double pct = G_Risk.daily_pnl / G_Risk.day_start_bal * 100.0;
   if(pct <= -p_Daily_Loss)
   {
      G_Risk.limit_hit = true; G_Risk.limit_reason = "Daily loss limit";
      Print("🔴 DAILY LOSS LIMIT: ", DoubleToString(pct, 2), "%");
   }
   else if(p_Daily_Profit > 0 && pct >= p_Daily_Profit)
   {
      G_Risk.limit_hit = true; G_Risk.limit_reason = "Daily target hit";
      Print("💰 DAILY PROFIT TARGET: +", DoubleToString(pct, 2), "%");
   }
}

void OnTradeResult(bool win, double profit)
{
   G_Risk.trades_today++; G_Risk.total_trades++;
   if(win) { G_Risk.wins_today++; G_Risk.total_wins++; G_Risk.consec_loss = 0; G_Risk.total_profit += profit; }
   else    { G_Risk.losses_today++; G_Risk.total_losses++; G_Risk.consec_loss++; G_Risk.total_loss += profit; }

   if(p_Max_ConLoss > 0 && G_Risk.consec_loss >= p_Max_ConLoss)
   {
      G_Risk.cooldown_until = TimeCurrent() + p_Cooldown * 60;
      G_Risk.consec_loss = 0;
      GlobalVariableSet(GKey("cool"), (double)G_Risk.cooldown_until);
      Print("⚠️ Cooldown until: ", TimeToString(G_Risk.cooldown_until, TIME_MINUTES));
   }
}

//══════════════════════════════════════════════════════════════════
// 🤖 AI ADAPTIVE CORE
//══════════════════════════════════════════════════════════════════
int AIIdx(int k) { return (AI_Head - AI_Count + k + AI_Size * 2) % AI_Size; } // k: 0=oldest

void AIAdd(double pnl, double r, int regime)
{
   AI_Pnl[AI_Head] = pnl; AI_R[AI_Head] = r; AI_Reg[AI_Head] = regime;
   AI_Head = (AI_Head + 1) % AI_Size;
   if(AI_Count < AI_Size) AI_Count++;
}

bool RegimeGateFails(int regime, double &exp_r, int &n)
{
   exp_r = 0; n = 0;
   if(p_AI_GateMode == GATE_OFF || !p_UseAI) return false;
   double s = 0;
   for(int k = 0; k < AI_Count; k++)
   {
      int i = AIIdx(k);
      if(AI_Reg[i] != regime) continue;
      s += AI_R[i]; n++;
   }
   if(n > 0) exp_r = s / n;
   return (n >= p_AI_GateMinN && exp_r < p_AI_GateMinExp);
}

void ComputeAIStats()
{
   G_AI = G_EmptyAI;
   G_AI.n = AI_Count;
   G_AI.risk_mult = 1.0;
   if(AI_Count == 0) { G_AI.signal = "LEARNING"; return; }

   double gp = 0, gl = 0, wr_sum = 0, lr_sum = 0, r_sum = 0;
   int cw = 0, cl = 0;
   for(int k = 0; k < AI_Count; k++)
   {
      int i = AIIdx(k);
      r_sum += AI_R[i];
      if(AI_Pnl[i] >= 0)
      {
         G_AI.wins++; gp += AI_Pnl[i]; wr_sum += MathMax(AI_R[i], 0.0);
         cw++; cl = 0; if(cw > G_AI.max_w) G_AI.max_w = cw;
      }
      else
      {
         gl += -AI_Pnl[i]; lr_sum += MathAbs(AI_R[i]);
         cl++; cw = 0; if(cl > G_AI.max_l) G_AI.max_l = cl;
      }
   }
   int losses = AI_Count - G_AI.wins;
   G_AI.consec_w   = cw;
   G_AI.consec_l   = cl;
   G_AI.wr         = (double)G_AI.wins / AI_Count;
   G_AI.pf         = (gl > 0) ? gp / gl : (gp > 0 ? 99.0 : 0.0);
   G_AI.avg_win_r  = (G_AI.wins > 0) ? wr_sum / G_AI.wins : 0;
   G_AI.avg_loss_r = (losses > 0) ? lr_sum / losses : 0;
   G_AI.exp_r      = r_sum / AI_Count;

   if(AI_Count < 5)                                        { G_AI.signal = "LEARNING";  G_AI.confidence = AI_Count * 10; }
   else if(G_AI.wr >= p_AI_WinThresh && G_AI.pf >= 1.5)    { G_AI.signal = "SCALE UP";  G_AI.confidence = MathMin(G_AI.wr * 100, 95); }
   else if(G_AI.wr < p_AI_LossThresh || cl >= 3)           { G_AI.signal = "DEFENSIVE"; G_AI.confidence = MathMin((1 - G_AI.wr) * 100, 95); }
   else if(G_AI.wr >= 0.5 && G_AI.pf >= 1.2)               { G_AI.signal = "NORMAL";    G_AI.confidence = G_AI.wr * 100; }
   else                                                    { G_AI.signal = "OBSERVING"; G_AI.confidence = 50; }

   G_AI.risk_mult = RiskMultiplier();
}

double RiskMultiplier()
{
   double m = 1.0;
   if(!p_UseAI || G_AI.n < 5) return m;

   if(p_ScaleMode == SCM_WINSTREAK && G_AI.wr >= p_AI_WinThresh && G_AI.consec_w >= 2)
      m = MathPow(p_ScaleFactor, MathMin(G_AI.consec_w - 1, p_MaxScale));
   else if(p_ScaleMode == SCM_KELLY && G_AI.n >= p_AI_GateMinN && G_AI.avg_loss_r > 0)
   {
      double R = G_AI.avg_win_r / G_AI.avg_loss_r;
      double k = G_AI.wr - (1.0 - G_AI.wr) / MathMax(R, 0.01);
      m = (k <= 0) ? p_RiskFloorMult : (p_KellyFrac * k * 100.0) / p_Risk_Pct;
   }

   if(G_AI.n >= 10 && G_AI.wr < p_AI_LossThresh) m *= 0.5;

   if(p_AI_GateMode == GATE_REDUCE && G_Sig.valid)
   {
      double e; int n;
      if(RegimeGateFails(CurrentRegime(), e, n)) m = MathMin(m, p_RiskFloorMult);
   }
   return MathMax(p_RiskFloorMult, MathMin(p_RiskCapMult, m));
}

//══════════════════════════════════════════════════════════════════
// ENGINE — ATR + SUPERTREND
//══════════════════════════════════════════════════════════════════
bool BuildEngine()
{
   MqlRates r[]; ArraySetAsSeries(r, true);
   int got = CopyRates(_Symbol, PERIOD_CURRENT, 0, CALC_BARS, r);
   if(got < p_ATR_Len * 3 + 10) return false;

   ArrayResize(ST_Band, got); ArrayResize(ST_Dir, got); ArrayResize(ST_Atr, got); ArrayResize(ST_Time, got);
   ArrayInitialize(ST_Band, 0); ArrayInitialize(ST_Dir, 0); ArrayInitialize(ST_Atr, 0);
   for(int i = 0; i < got; i++) ST_Time[i] = r[i].time;
   ST_Got = got;
   int len = p_ATR_Len; double m = p_BaseMult;

   if(p_Engine == ENGINE_PINE)
   {
      // ta.atr = ta.rma(ta.tr(true), len)  — seed ด้วย SMA ของ len แท่งแรก
      double tr[]; ArrayResize(tr, got);
      for(int i = got - 1; i >= 0; i--)
      {
         double hl = r[i].high - r[i].low;
         if(i == got - 1) tr[i] = hl;
         else tr[i] = MathMax(hl, MathMax(MathAbs(r[i].high - r[i + 1].close), MathAbs(r[i].low - r[i + 1].close)));
      }
      int seed = got - len;
      double s = 0;
      for(int i = got - 1; i >= seed; i--) s += tr[i];
      ST_Atr[seed] = s / len;
      for(int i = seed - 1; i >= 0; i--) ST_Atr[i] = (ST_Atr[i + 1] * (len - 1) + tr[i]) / len;

      // ta.supertrend(factor, atrPeriod) — 2 แบนด์ + ratchet ด้วย close[1]
      double up = 0, lo = 0, pUp = 0, pLo = 0;
      bool stUpper = true;
      for(int i = seed; i >= 0; i--)
      {
         double hl2 = (r[i].high + r[i].low) * 0.5, a = ST_Atr[i];
         up = hl2 + m * a; lo = hl2 - m * a;
         int pdir;
         if(i == seed) pdir = 1;
         else
         {
            double pc = r[i + 1].close;
            lo = (lo > pLo || pc < pLo) ? lo : pLo;
            up = (up < pUp || pc > pUp) ? up : pUp;
            if(stUpper) pdir = (r[i].close > up) ? -1 : 1;
            else        pdir = (r[i].close < lo) ? 1 : -1;
         }
         stUpper    = (pdir == 1);
         ST_Band[i] = stUpper ? up : lo;
         ST_Dir[i]  = (pdir == -1) ? 1 : -1;   // EA convention: 1 = ขาขึ้น
         pUp = up; pLo = lo;
      }
   }
   else
   {
      // Legacy v4.0 — iATR (SMA) + single band
      double ab[]; ArraySetAsSeries(ab, true);
      if(CopyBuffer(hATR, 0, 0, got, ab) < got) return false;
      int dir = 1; double band = 0; bool first = true;
      for(int i = got - 1; i >= 0; i--)
      {
         double a = ab[i];
         if(a <= 0 || a == EMPTY_VALUE) continue;
         ST_Atr[i] = a;
         double hl2 = (r[i].high + r[i].low) * 0.5;
         double up_b = hl2 + m * a, dn_b = hl2 - m * a;
         if(first) { band = dn_b; dir = 1; first = false; }
         else
         {
            double pb = band;
            if(dir == 1) { band = MathMax(dn_b, pb); if(r[i].close < band) { dir = -1; band = up_b; } }
            else         { band = MathMin(up_b, pb); if(r[i].close > band) { dir = 1;  band = dn_b; } }
         }
         ST_Band[i] = band; ST_Dir[i] = dir;
      }
      if(first) return false;
   }
   return (ST_Atr[1] > 0 && ST_Dir[1] != 0 && ST_Dir[2] != 0);
}

//══════════════════════════════════════════════════════════════════
// SIGNAL ENGINE
//══════════════════════════════════════════════════════════════════
bool CalcSignals(SignalData &sig)
{
   sig = G_EmptySig;
   sig.block_reason = "Loading data...";
   sig.ch_st = sig.ch_reg = sig.ch_ema = sig.ch_rsi = sig.ch_body = sig.ch_mom = sig.ch_htf = -1;

   int bars = MathMax(MathMax(p_TSF_Look + 5, p_ScalpRange + 5), MathMax(p_Swing_Len + 5, 60));
   MqlRates rates[]; ArraySetAsSeries(rates, true);
   if(CopyRates(_Symbol, PERIOD_CURRENT, 0, bars, rates) < bars) return false;
   if(!BuildEngine()) return false;

   sig.atr = ST_Atr[1]; sig.st_dir = ST_Dir[1]; sig.st_dir_prev = ST_Dir[2]; sig.st_band = ST_Band[1];
   bool raw_buy  = (sig.st_dir == 1 && sig.st_dir_prev == -1);
   bool raw_sell = (sig.st_dir == -1 && sig.st_dir_prev == 1);
   sig.pass_st = raw_buy || raw_sell;

   // ADX + TSF
   double adx_buf[]; ArraySetAsSeries(adx_buf, true);
   if(CopyBuffer(hADX, 0, 0, p_TSF_Look + 10, adx_buf) < p_TSF_Look + 2) return false;
   sig.adx = adx_buf[1];
   double adx_sum = 0;
   for(int i = 1; i <= p_TSF_Look; i++) adx_sum += adx_buf[i];
   double adx_avg = adx_sum / p_TSF_Look;
   sig.tsf_ratio = (adx_avg > 0) ? sig.adx / adx_avg : 1.0;
   bool tsf_pass = !p_UseTSF || (sig.tsf_ratio >= p_TSF_Min);

   // BBW / EMA / RSI
   double bu[], bd[], bm[], eb[], rb[];
   ArraySetAsSeries(bu, true); ArraySetAsSeries(bd, true); ArraySetAsSeries(bm, true);
   ArraySetAsSeries(eb, true); ArraySetAsSeries(rb, true);
   if(CopyBuffer(hBB, 0, 0, 3, bm) < 3 || CopyBuffer(hBB, 1, 0, 3, bu) < 3 || CopyBuffer(hBB, 2, 0, 3, bd) < 3) return false;
   if(CopyBuffer(hEMA, 0, 0, 3, eb) < 3) return false;
   if(CopyBuffer(hRSI, 0, 0, 3, rb) < 3) return false;
   sig.bbw = (bm[1] > 0) ? (bu[1] - bd[1]) / bm[1] : 0;
   sig.ema = eb[1];
   sig.rsi = rb[1];

   double cl = rates[1].close;
   bool htf_buy = true, htf_sell = true;
   if(p_UseHTF)
   {
      double hb[]; ArraySetAsSeries(hb, true);
      if(CopyBuffer(hHTF, 0, 0, 3, hb) < 3) return false;
      sig.htf_ema = hb[1];
      htf_buy = cl > sig.htf_ema; htf_sell = cl < sig.htf_ema;
   }

   // Auto Sensitivity (Pine switch)
   int tf_mins = (int)(PeriodSeconds() / 60); if(tf_mins == 0) tf_mins = 1;
   if(p_AutoSens)
   {
      if(tf_mins <= 1)        { sig.adx_thresh = 13.0; sig.bbw_thresh = 0.002; }
      else if(tf_mins <= 3)   { sig.adx_thresh = 14.0; sig.bbw_thresh = 0.003; }
      else if(tf_mins <= 5)   { sig.adx_thresh = 15.0; sig.bbw_thresh = 0.004; }
      else if(tf_mins <= 15)  { sig.adx_thresh = 17.0; sig.bbw_thresh = 0.006; }
      else if(tf_mins <= 30)  { sig.adx_thresh = 19.0; sig.bbw_thresh = 0.007; }
      else if(tf_mins <= 60)  { sig.adx_thresh = 21.0; sig.bbw_thresh = 0.008; }
      else if(tf_mins <= 240) { sig.adx_thresh = 23.0; sig.bbw_thresh = 0.010; }
      else                    { sig.adx_thresh = 25.0; sig.bbw_thresh = 0.012; }
   }
   else { sig.adx_thresh = (double)p_ADX_Manual; sig.bbw_thresh = p_BBW_Manual; }

   // Regime
   bool adx_ok = sig.adx >= sig.adx_thresh, bbw_ok = sig.bbw >= sig.bbw_thresh;
   sig.strong_trend = adx_ok && bbw_ok && tsf_pass;
   sig.weak_trend   = (adx_ok || tsf_pass) && !sig.strong_trend;
   sig.sideways     = !adx_ok && !tsf_pass;

   // Scalp range
   sig.range_high = rates[1].high; sig.range_low = rates[1].low;
   for(int i = 1; i <= p_ScalpRange; i++)
   {
      if(rates[i].high > sig.range_high) sig.range_high = rates[i].high;
      if(rates[i].low  < sig.range_low)  sig.range_low  = rates[i].low;
   }
   sig.range_mid = (sig.range_high + sig.range_low) * 0.5;
   double range_sz = sig.range_high - sig.range_low;
   bool scalp_bz = cl < (sig.range_mid - range_sz * 0.15);
   bool scalp_sz = cl > (sig.range_mid + range_sz * 0.15);

   // Confirmations
   bool ema_buy_ok  = !p_UseEMA || (cl > sig.ema);
   bool ema_sell_ok = !p_UseEMA || (cl < sig.ema);
   bool rsi_buy_ok  = !p_UseRSI || (sig.rsi < p_RSI_OB);
   bool rsi_sell_ok = !p_UseRSI || (sig.rsi > p_RSI_OS);

   sig.body_ratio = (sig.atr > 0) ? MathAbs(cl - rates[1].open) / sig.atr : 0;
   sig.body_min   = (tf_mins <= 5) ? 0.05 : (tf_mins <= 15) ? 0.08 : 0.12;
   bool solid_body = !p_UseBody || sig.body_ratio >= sig.body_min;

   bool buy_mom, sell_mom;
   if(!p_UseMomentum) { buy_mom = true; sell_mom = true; }
   else if(tf_mins <= 5) { buy_mom = (cl > rates[2].close); sell_mom = (cl < rates[2].close); }
   else
   {
      buy_mom  = (cl > rates[2].close && rates[2].close > rates[3].close);
      sell_mom = (cl < rates[2].close && rates[2].close < rates[3].close);
   }

   // Final signals (Pine logic + optional HTF on trend only)
   sig.trend_buy  = raw_buy  && (sig.strong_trend || sig.weak_trend) && ema_buy_ok  && rsi_buy_ok  && solid_body && buy_mom  && htf_buy;
   sig.trend_sell = raw_sell && (sig.strong_trend || sig.weak_trend) && ema_sell_ok && rsi_sell_ok && solid_body && sell_mom && htf_sell;
   sig.scalp_buy  = p_UseScalp && sig.sideways && raw_buy  && scalp_bz;
   sig.scalp_sell = p_UseScalp && sig.sideways && raw_sell && scalp_sz;
   sig.buy  = sig.trend_buy  || sig.scalp_buy;
   sig.sell = sig.trend_sell || sig.scalp_sell;
   sig.is_scalp = (sig.scalp_buy || sig.scalp_sell) && !(sig.trend_buy || sig.trend_sell);

   // Confluence chips (ตามทิศ ST ปัจจุบัน)
   bool bull = (sig.st_dir == 1);
   sig.ch_st   = sig.pass_st ? 2 : 1;
   sig.ch_reg  = sig.strong_trend ? 2 : (sig.weak_trend ? 1 : (p_UseScalp ? 1 : 0));
   sig.ch_ema  = !p_UseEMA ? -1 : ((bull ? ema_buy_ok : ema_sell_ok) ? 2 : 0);
   sig.ch_rsi  = !p_UseRSI ? -1 : ((bull ? rsi_buy_ok : rsi_sell_ok) ? 2 : 0);
   sig.ch_body = !p_UseBody ? -1 : (solid_body ? 2 : 0);
   sig.ch_mom  = !p_UseMomentum ? -1 : ((bull ? buy_mom : sell_mom) ? 2 : 0);
   sig.ch_htf  = !p_UseHTF ? -1 : ((bull ? htf_buy : htf_sell) ? 2 : 0);

   // Block reason
   if(!sig.pass_st)
      sig.block_reason = StringFormat("No ST flip · trend %s", bull ? "▲" : "▼");
   else if(!sig.strong_trend && !sig.weak_trend && !(p_UseScalp && sig.sideways))
      sig.block_reason = StringFormat("Regime SIDEWAYS ADX %.1f/%.1f", sig.adx, sig.adx_thresh);
   else if(!(sig.buy || sig.sell) && sig.sideways && p_UseScalp)
      sig.block_reason = "Scalp: price not in zone";
   else if(!solid_body)
      sig.block_reason = StringFormat("Body weak %.2f<%.2f", sig.body_ratio, sig.body_min);
   else if(raw_buy && !ema_buy_ok)   sig.block_reason = "EMA: below EMA";
   else if(raw_sell && !ema_sell_ok) sig.block_reason = "EMA: above EMA";
   else if(raw_buy && !rsi_buy_ok)   sig.block_reason = StringFormat("RSI OB %.1f>%d", sig.rsi, p_RSI_OB);
   else if(raw_sell && !rsi_sell_ok) sig.block_reason = StringFormat("RSI OS %.1f<%d", sig.rsi, p_RSI_OS);
   else if(!(bull ? buy_mom : sell_mom)) sig.block_reason = "Momentum fail";
   else if(!(bull ? htf_buy : htf_sell)) sig.block_reason = "HTF bias against";
   else if(sig.buy)  sig.block_reason = "✓ BUY SIGNAL";
   else if(sig.sell) sig.block_reason = "✓ SELL SIGNAL";

   if(sig.buy || sig.sell)
   {
      CalcSLTP(sig, rates);
      double sl_atr = MathAbs(cl - sig.sl_price) / sig.atr;
      if(p_MaxSL_ATR > 0 && sl_atr > p_MaxSL_ATR)
      {
         sig.block_reason = StringFormat("SL too wide %.1f ATR", sl_atr);
         sig.buy = sig.sell = false;
      }
   }

   if(p_Debug && sig.pass_st && !(sig.buy || sig.sell)) Print("🔶 ST flip blocked: ", sig.block_reason);
   if(p_Debug && (sig.buy || sig.sell))
      Print("📊 ", sig.buy ? "BUY" : "SELL", " Scalp:", sig.is_scalp, " ADX:", DoubleToString(sig.adx, 1),
            " RSI:", DoubleToString(sig.rsi, 1), " ATR:", DoubleToString(sig.atr, _Digits));

   sig.valid = true;
   return true;
}

//══════════════════════════════════════════════════════════════════
// SL / TP
//══════════════════════════════════════════════════════════════════
void TPDistances(bool scalp, double atr, double sl_dist, double &d1, double &d2, double &d3)
{
   double m1 = scalp ? p_ScalpTP       : p_TP1_Mult;
   double m2 = scalp ? p_ScalpTP * 1.5 : p_TP2_Mult;
   double m3 = scalp ? p_ScalpTP * 2.0 : p_TP3_Mult;
   d1 = MathMax(m1 * atr, sl_dist * p_RR_Min);
   d2 = MathMax(m2 * atr, d1 * 1.5);   // บังคับ TP2 > TP1
   d3 = MathMax(m3 * atr, d2 * 1.3);   // บังคับ TP3 > TP2
}

void CalcSLTP(SignalData &sig, const MqlRates &rates[])
{
   double cl = rates[1].close, atr = sig.atr;
   int dir = sig.buy ? 1 : -1;

   if(sig.is_scalp && p_ScalpATRSL)
      sig.sl_price = cl - dir * p_ScalpSL * atr;
   else if(p_SL_Mode == SLM_SWING)
   {
      double sh = rates[1].high, sl_v = rates[1].low;
      for(int i = 1; i <= p_Swing_Len; i++)
      {
         if(rates[i].high > sh)  sh = rates[i].high;
         if(rates[i].low < sl_v) sl_v = rates[i].low;
      }
      sig.sl_price = sig.buy ? sl_v - p_SL_Buffer * atr : sh + p_SL_Buffer * atr;
   }
   else if(p_SL_Mode == SLM_ATR)
      sig.sl_price = cl - dir * (sig.is_scalp ? p_ScalpSL : p_SL_ATR_Mult) * atr;
   else
      sig.sl_price = cl - dir * p_SL_Pips * _Point;

   double d1, d2, d3;
   TPDistances(sig.is_scalp, atr, MathAbs(cl - sig.sl_price), d1, d2, d3);
   sig.tp1 = cl + dir * d1;
   sig.tp2 = cl + dir * d2;
   sig.tp3 = cl + dir * d3;
}

//══════════════════════════════════════════════════════════════════
// LOT SIZE
//══════════════════════════════════════════════════════════════════
double CalcLot(ENUM_ORDER_TYPE type, double entry, double sl, double &risk_money, double &risk_pct, bool verbose)
{
   risk_money = 0;
   double base = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
   risk_pct = p_Risk_Pct * RiskMultiplier();
   double target = base * risk_pct / 100.0;
   double dist = MathAbs(entry - sl), vpp = ValuePerPrice();
   if(dist <= 0 || vpp <= 0 || target <= 0) return 0;

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = MathMax(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), p_Min_Lot);
   double vmax = MathMin(SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX), p_Max_Lot);
   double raw  = target / (dist * vpp);
   double lot  = (step > 0) ? MathFloor(raw / step + 1e-9) * step : raw;

   if(lot < vmin)
   {
      double over = (vmin * dist * vpp) / target;
      if(over > p_MaxRiskOverMult)
      {
         if(verbose) Print("⛔ Min lot ", DoubleToString(vmin, 2), " = risk x", DoubleToString(over, 2), " ของเป้า → ข้ามไม้นี้");
         return 0;
      }
      lot = vmin;
   }
   lot = MathMin(lot, vmax);

   double margin = 0, fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(p_MaxMarginPct > 0 && OrderCalcMargin(type, _Symbol, lot, entry, margin) && margin > 0)
   {
      double allow = fm * p_MaxMarginPct / 100.0;
      if(margin > allow)
      {
         lot = (step > 0) ? MathFloor(lot * allow / margin / step) * step : lot * allow / margin;
         if(lot < vmin) { if(verbose) Print("⛔ Margin ไม่พอ (ใช้ได้ ", DoubleToString(p_MaxMarginPct, 0), "% ของ Free Margin)"); return 0; }
      }
   }
   lot = NormalizeDouble(lot, VolDigits());
   risk_money = lot * dist * vpp;
   if(verbose && p_Debug)
      Print("💰 Lot:", DoubleToString(lot, 2), " Risk%:", DoubleToString(risk_pct, 2), " Risk$:", DoubleToString(risk_money, 2));
   return lot;
}

void RefreshNextLot()
{
   if(G_Sig.atr <= 0) { G_NextLot = 0; return; }
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), rm, rp;
   G_NextLot = CalcLot(ORDER_TYPE_BUY, ask, ask - p_SL_ATR_Mult * G_Sig.atr, rm, rp, false);
}

//══════════════════════════════════════════════════════════════════
// OPEN TRADE
//══════════════════════════════════════════════════════════════════
void OpenTrade(ENUM_ORDER_TYPE type)
{
   bool is_buy = (type == ORDER_TYPE_BUY);
   int dir = is_buy ? 1 : -1;
   MqlTick tk; if(!SymbolInfoTick(_Symbol, tk)) return;
   double price = is_buy ? tk.ask : tk.bid;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double md = MinStopDist(5);
   double sl = G_Sig.sl_price;
   if(is_buy && sl > price - md)  sl = price - md;
   if(!is_buy && sl < price + md) sl = price + md;
   sl = NormalizeDouble(sl, dg);
   double sl_dist = MathAbs(price - sl);
   if(sl_dist <= 0) return;

   double risk_money = 0, risk_pct = 0;
   double lot = CalcLot(type, price, sl, risk_money, risk_pct, true);
   if(lot <= 0) return;

   double d1, d2, d3;
   TPDistances(G_Sig.is_scalp, G_Sig.atr, sl_dist, d1, d2, d3);
   double tp1 = NormalizeDouble(price + dir * d1, dg);
   double tp2 = NormalizeDouble(price + dir * d2, dg);
   double tp3 = NormalizeDouble(price + dir * d3, dg);
   double last_tp = (p_TP_Levels >= 3) ? tp3 : (p_TP_Levels == 2 ? tp2 : tp1);
   double srv_tp  = p_ServerTP ? last_tp : 0;

   string mode = G_Sig.is_scalp ? "SCALP" : (G_Sig.strong_trend ? "STRONG" : "WEAK");
   string cmt  = StringFormat("YY41|%s|%s|r%.2f", is_buy ? "B" : "S", mode, risk_money);

   bool ok = is_buy ? Trade.Buy(lot, _Symbol, price, sl, srv_tp, cmt)
                    : Trade.Sell(lot, _Symbol, price, sl, srv_tp, cmt);
   uint rc = Trade.ResultRetcode();
   if(!ok || (rc != TRADE_RETCODE_DONE && rc != TRADE_RETCODE_DONE_PARTIAL && rc != TRADE_RETCODE_PLACED))
   {
      Print("❌ Order fail: ", rc, " ", Trade.ResultRetcodeDescription());
      return;
   }

   double fill = Trade.ResultPrice(); if(fill <= 0) fill = price;
   double vol  = Trade.ResultVolume(); if(vol <= 0) vol = lot;

   G_Trade = G_EmptyTrade;
   ulong pos = Trade.ResultOrder();
   if(pos == 0 || !PositionSelectByTicket(pos)) pos = FindTick();
   G_Trade.ticket     = pos;
   G_Trade.dir        = dir;
   G_Trade.entry      = fill;
   G_Trade.sl_init    = sl;
   G_Trade.sl         = sl;
   G_Trade.tp1 = tp1; G_Trade.tp2 = tp2; G_Trade.tp3 = tp3;
   G_Trade.orig_vol   = vol;
   G_Trade.risk_money = MathAbs(fill - sl) * vol * ValuePerPrice();
   G_Trade.mfe_price  = fill;
   G_Trade.trail_ref  = sl;
   G_Trade.trail_active = p_UseTrail && p_TrailStart <= 0;
   G_Trade.is_scalp   = G_Sig.is_scalp;
   G_Trade.is_strong  = G_Sig.strong_trend;
   G_Trade.regime     = CurrentRegime();
   G_Trade.adx_entry  = G_Sig.adx;
   G_Trade.open_time  = TimeCurrent();

   if(pos == 0) { G_PendingOpen = true; G_PendingSince = TimeCurrent(); }
   else SaveState();

   if(G_IsVisual && p_ShowZones) UpdateZones();

   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
   Print("✅ ", is_buy ? "▲ BUY" : "▼ SELL", " [", mode, "] #", pos, " Lot:", DoubleToString(vol, 2),
         " Risk:", DoubleToString(risk_pct, 2), "% (", DoubleToString(G_Trade.risk_money, 2), ")");
   Print("   Entry:", DoubleToString(fill, dg), " SL:", DoubleToString(sl, dg),
         " TP1:", DoubleToString(tp1, dg), " TP2:", DoubleToString(tp2, dg), " TP3:", DoubleToString(tp3, dg));
   Print("   AI: ", G_AI.signal, " (", DoubleToString(G_AI.confidence, 0), "%) Regime:", RegimeName(G_Trade.regime));
   Print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

//══════════════════════════════════════════════════════════════════
// STATE PERSISTENCE
//══════════════════════════════════════════════════════════════════
void SaveState()
{
   if(G_Trade.ticket == 0) return;
   ulong t = G_Trade.ticket;
   int f = 0;
   if(G_Trade.tp1_hit)      f |= 1;
   if(G_Trade.tp2_hit)      f |= 2;
   if(G_Trade.tp3_hit)      f |= 4;
   if(G_Trade.be_done)      f |= 8;
   if(G_Trade.p1_done)      f |= 16;
   if(G_Trade.p2_done)      f |= 32;
   if(G_Trade.trail_active) f |= 64;
   if(G_Trade.lock_active)  f |= 128;
   if(G_Trade.is_scalp)     f |= 256;
   if(G_Trade.is_strong)    f |= 512;
   GlobalVariableSet(TKey(t, "f"),    f);
   GlobalVariableSet(TKey(t, "tp1"),  G_Trade.tp1);
   GlobalVariableSet(TKey(t, "tp2"),  G_Trade.tp2);
   GlobalVariableSet(TKey(t, "tp3"),  G_Trade.tp3);
   GlobalVariableSet(TKey(t, "sli"),  G_Trade.sl_init);
   GlobalVariableSet(TKey(t, "risk"), G_Trade.risk_money);
   GlobalVariableSet(TKey(t, "mfe"),  G_Trade.mfe_price);
   GlobalVariableSet(TKey(t, "tref"), G_Trade.trail_ref);
   GlobalVariableSet(TKey(t, "lock"), G_Trade.lock_level);
   GlobalVariableSet(TKey(t, "reg"),  G_Trade.regime);
   GlobalVariableSet(TKey(t, "ovol"), G_Trade.orig_vol);
}

bool LoadState(ulong t)
{
   if(!GlobalVariableCheck(TKey(t, "f"))) return false;
   int f = (int)GlobalVariableGet(TKey(t, "f"));
   G_Trade.tp1_hit      = (f & 1) != 0;
   G_Trade.tp2_hit      = (f & 2) != 0;
   G_Trade.tp3_hit      = (f & 4) != 0;
   G_Trade.be_done      = (f & 8) != 0;
   G_Trade.p1_done      = (f & 16) != 0;
   G_Trade.p2_done      = (f & 32) != 0;
   G_Trade.trail_active = (f & 64) != 0;
   G_Trade.lock_active  = (f & 128) != 0;
   G_Trade.is_scalp     = (f & 256) != 0;
   G_Trade.is_strong    = (f & 512) != 0;
   G_Trade.tp1        = GGet(TKey(t, "tp1"), 0);
   G_Trade.tp2        = GGet(TKey(t, "tp2"), 0);
   G_Trade.tp3        = GGet(TKey(t, "tp3"), 0);
   G_Trade.sl_init    = GGet(TKey(t, "sli"), G_Trade.sl);
   G_Trade.risk_money = GGet(TKey(t, "risk"), 0);
   G_Trade.mfe_price  = GGet(TKey(t, "mfe"), G_Trade.entry);
   G_Trade.trail_ref  = GGet(TKey(t, "tref"), G_Trade.sl);
   G_Trade.lock_level = (int)GGet(TKey(t, "lock"), 0);
   G_Trade.regime     = (int)GGet(TKey(t, "reg"), -9);
   G_Trade.orig_vol   = GGet(TKey(t, "ovol"), G_Trade.orig_vol);
   return (G_Trade.tp1 > 0);
}

void ClearState(ulong t) { GlobalVariablesDeleteAll(TKey(t, "")); }

void ScanExistingPositions()
{
   ulong t = FindTick();
   if(t == 0 || !PositionSelectByTicket(t)) return;
   G_Trade = G_EmptyTrade;
   G_Trade.ticket    = t;
   G_Trade.dir       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
   G_Trade.entry     = PositionGetDouble(POSITION_PRICE_OPEN);
   G_Trade.sl        = PositionGetDouble(POSITION_SL);
   G_Trade.orig_vol  = PositionGetDouble(POSITION_VOLUME);
   G_Trade.open_time = (datetime)PositionGetInteger(POSITION_TIME);
   G_Trade.mfe_price = G_Trade.entry;
   G_Trade.trail_ref = G_Trade.sl;

   if(LoadState(t))
   {
      Print("🔍 Restored state for #", t, " TP1hit:", G_Trade.tp1_hit, " BE:", G_Trade.be_done, " Lock Lv:", G_Trade.lock_level);
      return;
   }
   // ไม่มี state → ปิดการทำงาน TP/Partial/BE, ใช้ Trail เฉพาะเมื่อกำไรเกิน entry
   string c = PositionGetString(POSITION_COMMENT);
   G_Trade.nostate = true;
   G_Trade.tp1_hit = G_Trade.tp2_hit = G_Trade.tp3_hit = true;
   G_Trade.p1_done = G_Trade.p2_done = G_Trade.be_done = true;
   G_Trade.trail_active = p_UseTrail;
   G_Trade.sl_init = G_Trade.sl;
   G_Trade.regime = ParseRegime(c);
   G_Trade.risk_money = ParseRisk(c);
   if(G_Trade.risk_money <= 0 && G_Trade.sl > 0)
      G_Trade.risk_money = MathAbs(G_Trade.entry - G_Trade.sl) * G_Trade.orig_vol * ValuePerPrice();
   Print("⚠️ No saved state for #", t, " → TP/Partial disabled, trail only when in profit");
   SaveState();
}

//══════════════════════════════════════════════════════════════════
// MANAGE POSITION (every tick)
//══════════════════════════════════════════════════════════════════
void ManagePosition()
{
   if(G_Trade.ticket == 0) return;
   if(!PositionSelectByTicket(G_Trade.ticket)) { FinalizeTrade(); return; }

   MqlTick tk; if(!SymbolInfoTick(_Symbol, tk)) return;
   int dir = G_Trade.dir;
   double cp = (dir == 1) ? tk.bid : tk.ask;
   if(G_Trade.mfe_price <= 0) G_Trade.mfe_price = G_Trade.entry;
   if(dir == 1 && tk.bid > G_Trade.mfe_price)  G_Trade.mfe_price = tk.bid;
   if(dir == -1 && tk.ask < G_Trade.mfe_price) G_Trade.mfe_price = tk.ask;

   // ── TP level detection
   if(!G_Trade.tp1_hit && Reached(cp, G_Trade.tp1))
   {
      G_Trade.tp1_hit = true;
      if(p_UseTrail && p_TrailStart <= 1) G_Trade.trail_active = true;
      Print("🎯 TP1 @ ", DoubleToString(cp, _Digits));
      SaveState();
   }
   if(G_Trade.tp1_hit && !G_Trade.tp2_hit && p_TP_Levels >= 2 && Reached(cp, G_Trade.tp2))
   {
      G_Trade.tp2_hit = true;
      if(p_UseTrail && p_TrailStart <= 2) G_Trade.trail_active = true;
      Print("🎯🎯 TP2 @ ", DoubleToString(cp, _Digits));
      SaveState();
   }
   if(G_Trade.tp2_hit && !G_Trade.tp3_hit && p_TP_Levels >= 3 && Reached(cp, G_Trade.tp3))
   {
      G_Trade.tp3_hit = true;
      Print("🏆 TP3 @ ", DoubleToString(cp, _Digits));
      SaveState();
   }

   // ── Final TP → ปิดทั้งหมด (retry จนกว่าจะปิดได้)
   if(!G_Trade.nostate)
   {
      bool final_hit = (p_TP_Levels == 1 && G_Trade.tp1_hit) || (p_TP_Levels == 2 && G_Trade.tp2_hit) ||
                       (p_TP_Levels >= 3 && G_Trade.tp3_hit);
      if(final_hit) { ClosePos("Final TP"); return; }

      // ── Partials (retry ได้ ถ้า fail)
      if(G_Trade.tp1_hit && !G_Trade.p1_done && p_PC1_Pct > 0) DoPartial(1);
      if(G_Trade.tp2_hit && !G_Trade.p2_done && p_PC2_Pct > 0) DoPartial(2);
   }

   if(!PositionSelectByTicket(G_Trade.ticket)) return;
   if(p_UseBreakeven && G_Trade.tp1_hit && !G_Trade.be_done) MoveToBreakeven(tk);
   UpdateStops(tk);
}

double TrailMult()
{
   double m = p_TrailATR;
   if(p_AdaptTrail)
   {
      if(G_Trade.is_strong)     m *= 1.3;
      else if(G_Trade.is_scalp) m *= 0.7;
      if(p_UseAI && G_AI.n >= 5 && G_AI.wr >= p_AI_WinThresh) m *= 1.1;
   }
   return m;
}

// รวม Trail + Lock เป็นการ modify ครั้งเดียว (เลือก SL ที่ดีที่สุด)
void UpdateStops(const MqlTick &tk)
{
   double atr = G_Sig.atr;
   if(atr <= 0) return;
   if(!PositionSelectByTicket(G_Trade.ticket)) return;
   int dir = G_Trade.dir;
   double cp = (dir == 1) ? tk.bid : tk.ask;
   double cur = PositionGetDouble(POSITION_SL);
   double best = cur;
   bool use_trail = false, use_lock = false;
   double ideal = 0;
   int lock_lvl = G_Trade.lock_level;

   if(p_UseTrail && G_Trade.trail_active)
   {
      ideal = cp - dir * TrailMult() * atr;
      double step = p_TrailStep * atr;
      bool ok = (G_Trade.trail_ref <= 0) ||
                ((dir == 1) ? ideal >= G_Trade.trail_ref + step : ideal <= G_Trade.trail_ref - step);
      if(G_Trade.nostate && (ideal - G_Trade.entry) * dir <= 0) ok = false;
      if(ok && Better(ideal, best, dir)) { best = ideal; use_trail = true; }
   }

   if(p_UseLockProfit && p_LockStep > 0 && (!p_LockAfterTP1 || G_Trade.tp1_hit))
   {
      double mfe = (G_Trade.mfe_price - G_Trade.entry) * dir;
      if(mfe >= p_LockMinATR * atr)
      {
         int lvl = (int)MathFloor(mfe / (p_LockStep * atr));
         if(lvl > G_Trade.lock_level)
         {
            double lp = G_Trade.entry + dir * mfe * p_LockPct / 100.0;
            if(Better(lp, best, dir)) { best = lp; use_lock = true; lock_lvl = lvl; }
            else G_Trade.lock_level = lvl;  // SL ปัจจุบันดีกว่าอยู่แล้ว
         }
      }
   }

   if(!use_trail && !use_lock) return;
   if(ModifySL(best, tk))
   {
      if(use_trail) G_Trade.trail_ref = ideal;
      if(use_lock)
      {
         G_Trade.lock_level = lock_lvl; G_Trade.lock_active = true;
         Print("🔒 LOCK Lv", lock_lvl, " @ ", DoubleToString(best, _Digits), " (", DoubleToString(p_LockPct, 0), "% of MFE)");
      }
      SaveState();
   }
}

bool ModifySL(double new_sl, const MqlTick &tk)
{
   new_sl = NormalizeDouble(new_sl, _Digits);
   double md = MinStopDist(2);
   if(G_Trade.dir == 1 && new_sl >= tk.bid - md) return false;
   if(G_Trade.dir == -1 && new_sl <= tk.ask + md) return false;
   if(!Throttle()) return false;
   double tp = PositionGetDouble(POSITION_TP);
   if(Trade.PositionModify(G_Trade.ticket, new_sl, tp)) { G_Trade.sl = new_sl; return true; }
   if(p_Debug) Print("⚠️ Modify SL fail: ", Trade.ResultRetcode(), " ", Trade.ResultRetcodeDescription());
   return false;
}

void MoveToBreakeven(const MqlTick &tk)
{
   int dir = G_Trade.dir;
   double sp = tk.ask - tk.bid;
   double be = G_Trade.entry + dir * (sp * 1.5 + p_BE_ExtraPts * _Point);
   double cur = PositionGetDouble(POSITION_SL);
   if(!Better(be, cur, dir)) { G_Trade.be_done = true; SaveState(); return; }
   if(ModifySL(be, tk))
   {
      G_Trade.be_done = true;
      Print("🛡️ Breakeven @ ", DoubleToString(be, _Digits));
      SaveState();
   }
}

void DoPartial(int lv)
{
   if(!Throttle()) return;
   if(!PositionSelectByTicket(G_Trade.ticket)) return;
   double vol  = PositionGetDouble(POSITION_VOLUME);
   double pct  = (lv == 1) ? p_PC1_Pct : p_PC2_Pct;
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double cv = (step > 0) ? MathFloor(vol * pct / 100.0 / step + 1e-9) * step : vol * pct / 100.0;
   if(vol - cv < vmin) cv = vol - vmin;
   cv = NormalizeDouble(cv, VolDigits());
   if(cv < vmin)
   {
      if(lv == 1) G_Trade.p1_done = true; else G_Trade.p2_done = true;
      Print("ℹ️ Partial TP", lv, " skipped — volume ", DoubleToString(vol, 2), " เล็กเกินแบ่ง");
      SaveState();
      return;
   }
   if(Trade.PositionClosePartial(G_Trade.ticket, cv))
   {
      if(lv == 1) G_Trade.p1_done = true; else G_Trade.p2_done = true;
      Print("✂️ Partial TP", lv, ": ", DoubleToString(cv, 2), " lots");
      SaveState();
   }
   else if(++G_Trade.pc_fail >= 5)
   {
      if(lv == 1) G_Trade.p1_done = true; else G_Trade.p2_done = true;
      Print("⚠️ Partial TP", lv, " failed 5x: ", Trade.ResultRetcodeDescription());
      SaveState();
   }
}

bool ClosePos(string reason)
{
   if(!Throttle()) return false;
   if(Trade.PositionClose(G_Trade.ticket))
   {
      Print("🏁 Close #", G_Trade.ticket, " — ", reason);
      return true;
   }
   if(p_Debug) Print("⚠️ Close fail: ", Trade.ResultRetcodeDescription());
   return false;
}

void CheckTimeStop()
{
   if(!p_UseTimeStop || G_Trade.ticket == 0 || G_Trade.tp1_hit || G_Trade.nostate || G_Sig.atr <= 0) return;
   int bars = iBarShift(_Symbol, PERIOD_CURRENT, G_Trade.open_time, false);
   if(bars < p_TimeStopBars) return;
   double mfe = (G_Trade.mfe_price - G_Trade.entry) * G_Trade.dir;
   if(mfe < p_TimeStopMinATR * G_Sig.atr)
      ClosePos(StringFormat("TIME STOP %d bars, MFE %.2f ATR", bars, mfe / G_Sig.atr));
}

//══════════════════════════════════════════════════════════════════
// FINALIZE (single source of truth)
//══════════════════════════════════════════════════════════════════
bool PositionHistory(ulong pid, double &pnl, datetime &ct, double &cprice)
{
   pnl = 0; ct = 0; cprice = 0;
   if(!HistorySelectByPosition((long)pid)) return false;
   double vin = 0, vout = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      pnl += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
             HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      if(e == DEAL_ENTRY_IN) vin += v;
      else if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY)
      {
         vout += v;
         ct = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
         cprice = HistoryDealGetDouble(d, DEAL_PRICE);
      }
   }
   return (vin > 0 && vout >= vin - 1e-8);
}

void FinalizeTrade()
{
   if(G_Trade.ticket == 0) return;
   ulong pid = G_Trade.ticket;
   double pnl; datetime ct; double cprice;
   bool closed = PositionHistory(pid, pnl, ct, cprice);
   if(!closed && ++G_Trade.fin_tries < 20) return;   // รอ history sync

   double r = (G_Trade.risk_money > 0) ? pnl / G_Trade.risk_money : 0;
   bool win = (pnl >= 0);
   AIAdd(pnl, r, G_Trade.regime);
   OnTradeResult(win, pnl);
   ComputeAIStats();

   if(G_IsVisual)
   {
      ObjectsDeleteAll(0, OBJ + "Z_");
      if(p_ShowZones && ct > 0) DrawResultMark(pid, pnl, r, ct, cprice);
   }
   Print(win ? "✅ WIN" : "❌ LOSS", " #", pid, " P&L:", DoubleToString(pnl, 2), " (", DoubleToString(r, 2), "R)",
         " | AI:", G_AI.signal, " WR:", DoubleToString(G_AI.wr * 100, 1), "%");
   ClearState(pid);
   G_Trade = G_EmptyTrade;
}

void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &req, const MqlTradeResult &res)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(G_Trade.ticket == 0 || trans.position != G_Trade.ticket) return;
   if(!PositionSelectByTicket(G_Trade.ticket)) FinalizeTrade();
}

//══════════════════════════════════════════════════════════════════
// HISTORY → AI MEMORY
//══════════════════════════════════════════════════════════════════
int FindId(const ulong &ids[], int cnt, ulong id)
{
   for(int j = 0; j < cnt; j++) if(ids[j] == id) return j;
   return -1;
}

void LoadTradeHistory()
{
   datetime now = TimeCurrent();
   if(!HistorySelect(now - 90 * 86400, now + 86400)) return;
   int n = HistoryDealsTotal();
   ulong ids[]; double pnl[], risk[], vin[], vout[]; datetime last[]; int reg[];
   int cnt = 0;

   // Pass 1: position IDs ที่เปิดโดย EA นี้
   for(int i = 0; i < n; i++)
   {
      ulong d = HistoryDealGetTicket(i); if(d == 0) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != p_Magic) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      if(FindId(ids, cnt, pid) >= 0) continue;
      cnt++;
      ArrayResize(ids, cnt); ArrayResize(pnl, cnt); ArrayResize(risk, cnt);
      ArrayResize(vin, cnt); ArrayResize(vout, cnt); ArrayResize(last, cnt); ArrayResize(reg, cnt);
      string c = HistoryDealGetString(d, DEAL_COMMENT);
      ids[cnt - 1] = pid; pnl[cnt - 1] = 0; vin[cnt - 1] = 0; vout[cnt - 1] = 0; last[cnt - 1] = 0;
      reg[cnt - 1] = ParseRegime(c); risk[cnt - 1] = ParseRisk(c);
   }
   if(cnt == 0) return;

   // Pass 2: รวมทุก deal ของ position (รวม SL/TP deal ที่ magic อาจไม่ตรง)
   for(int i = 0; i < n; i++)
   {
      ulong d = HistoryDealGetTicket(i); if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      long typ = HistoryDealGetInteger(d, DEAL_TYPE);
      if(typ != DEAL_TYPE_BUY && typ != DEAL_TYPE_SELL) continue;
      int k = FindId(ids, cnt, (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID));
      if(k < 0) continue;
      pnl[k] += HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_SWAP) +
                HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_FEE);
      long e = HistoryDealGetInteger(d, DEAL_ENTRY);
      double v = HistoryDealGetDouble(d, DEAL_VOLUME);
      if(e == DEAL_ENTRY_IN) vin[k] += v;
      else if(e == DEAL_ENTRY_OUT || e == DEAL_ENTRY_OUT_BY)
      {
         vout[k] += v;
         last[k] = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      }
   }

   // เรียงตามเวลาปิด (เก่า → ใหม่)
   int ord[]; ArrayResize(ord, cnt);
   int m = 0;
   for(int k = 0; k < cnt; k++) if(last[k] > 0 && vout[k] >= vin[k] - 1e-8) ord[m++] = k;
   for(int a = 1; a < m; a++)
   {
      int key = ord[a], b = a - 1;
      while(b >= 0 && last[ord[b]] > last[key]) { ord[b + 1] = ord[b]; b--; }
      ord[b + 1] = key;
   }

   double est = AccountInfoDouble(ACCOUNT_BALANCE) * p_Risk_Pct / 100.0;
   for(int j = 0; j < m; j++)
   {
      int k = ord[j];
      double rm = (risk[k] > 0) ? risk[k] : est;
      double r  = (rm > 0) ? pnl[k] / rm : 0;
      AIAdd(pnl[k], r, reg[k]);
      G_Risk.total_trades++;
      if(pnl[k] >= 0) { G_Risk.total_wins++; G_Risk.total_profit += pnl[k]; }
      else            { G_Risk.total_losses++; G_Risk.total_loss += pnl[k]; }
      if(last[k] >= G_Risk.day_start)
      {
         G_Risk.trades_today++;
         if(pnl[k] >= 0) G_Risk.wins_today++; else G_Risk.losses_today++;
      }
   }
   Print("📚 History: ", m, " closed trades (90d) → AI memory ", MathMin(m, AI_Size), "/", AI_Size);
}

//══════════════════════════════════════════════════════════════════
// PARITY DUMP (เทียบกับ CSV จาก TradingView)
//══════════════════════════════════════════════════════════════════
void DumpParity()
{
   FileWrite(G_ParityFH,
             TimeToString(iTime(_Symbol, PERIOD_CURRENT, 1), TIME_DATE | TIME_MINUTES),
             G_Sig.st_dir,
             DoubleToString(G_Sig.st_band, _Digits),
             DoubleToString(G_Sig.atr, _Digits + 2),
             DoubleToString(G_Sig.adx, 4),
             DoubleToString(G_Sig.bbw, 6),
             DoubleToString(G_Sig.ema, _Digits),
             DoubleToString(G_Sig.rsi, 4));
   FileFlush(G_ParityFH);
}

//══════════════════════════════════════════════════════════════════
// OPTIMIZATION CRITERION
//══════════════════════════════════════════════════════════════════
double OnTester()
{
   double pf = TesterStatistics(STAT_PROFIT_FACTOR);
   double tr = TesterStatistics(STAT_TRADES);
   double dd = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double np = TesterStatistics(STAT_PROFIT);
   if(tr < 30 || np <= 0) return 0;
   return MathMin(pf, 5.0) * MathSqrt(tr) * (1.0 - dd / 100.0);
}

//══════════════════════════════════════════════════════════════════
// 🎨 CHART VISUALS
//══════════════════════════════════════════════════════════════════
void ConfStates(int &s[])
{
   s[0] = G_Sig.ch_st; s[1] = G_Sig.ch_reg; s[2] = G_Sig.ch_ema; s[3] = G_Sig.ch_rsi;
   s[4] = G_Sig.ch_body; s[5] = G_Sig.ch_mom; s[6] = G_Sig.ch_htf;
   if(!G_Sig.valid) for(int i = 0; i < 7; i++) s[i] = -1;
   s[7] = !p_UseSession ? -1 : (SessionOK() ? 2 : 0);
   s[8] = !p_UseSpread  ? -1 : (SpreadOK() ? 2 : 0);
   string ev;
   s[9] = !p_UseNews ? -1 : (NewsBlocked(ev) ? 0 : 2);
}

void ConfScore(const int &s[], int &pass, int &total)
{
   pass = 0; total = 0;
   for(int i = 0; i < 10; i++)
   {
      if(s[i] < 0) continue;
      total++;
      if(s[i] == 2) pass++;
   }
}

void DrawSTLine()
{
   if(!p_ShowSTLine || ST_Got < 3) return;
   int N = MathMin(p_STLineBars, ST_Got - 2);
   for(int i = 1; i <= N; i++)
   {
      string n = OBJ + "STL" + IntegerToString(i);
      datetime ta = ST_Time[i + 1], tb = ST_Time[i];
      double pa = ST_Band[i + 1], pb = ST_Band[i];
      bool show = (ST_Dir[i] == ST_Dir[i + 1]) && pa > 0 && pb > 0;
      if(ObjectFind(0, n) < 0)
      {
         ObjectCreate(0, n, OBJ_TREND, 0, ta, pa, tb, pb);
         ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
         ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
         ObjectSetInteger(0, n, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, n, OBJPROP_BACK, true);
      }
      else
      {
         ObjectMove(0, n, 0, ta, pa);
         ObjectMove(0, n, 1, tb, pb);
      }
      ObjectSetInteger(0, n, OBJPROP_COLOR, ST_Dir[i] == 1 ? P.good : P.bad);
      ObjectSetInteger(0, n, OBJPROP_TIMEFRAMES, show ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   }
}

void DrawSignalMarks()
{
   if(!p_ShowSignals || !G_Sig.valid) return;
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 1);
   double hi = iHigh(_Symbol, PERIOD_CURRENT, 1), lo = iLow(_Symbol, PERIOD_CURRENT, 1), atr = G_Sig.atr;
   string ts = IntegerToString((long)t);

   if(G_Sig.buy || G_Sig.sell)
   {
      bool b = G_Sig.buy;
      int s[10]; ConfStates(s);
      int pass, total; ConfScore(s, pass, total);
      string mode = G_Sig.is_scalp ? "SCALP" : (G_Sig.strong_trend ? "STRONG" : "WEAK");
      color c = b ? P.good : P.bad;

      string n = OBJ + "SIG_" + ts;
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_ARROW, 0, t, b ? lo - 0.3 * atr : hi + 0.3 * atr);
      ObjectSetInteger(0, n, OBJPROP_ARROWCODE, b ? 233 : 234);
      ObjectSetInteger(0, n, OBJPROP_COLOR, c);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 3);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, b ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, StringFormat("%s %s\nADX %.1f · RSI %.1f · TSF %.2fx\nSL %s · TP1 %s\nConfluence %d/%d",
                      b ? "BUY" : "SELL", mode, G_Sig.adx, G_Sig.rsi, G_Sig.tsf_ratio,
                      DoubleToString(G_Sig.sl_price, _Digits), DoubleToString(G_Sig.tp1, _Digits), pass, total));

      string nt = OBJ + "SIGT_" + ts;
      if(ObjectFind(0, nt) < 0) ObjectCreate(0, nt, OBJ_TEXT, 0, t, b ? lo - 1.1 * atr : hi + 1.1 * atr);
      ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat("%s · %s %d/%d", b ? "BUY" : "SELL", mode, pass, total));
      ObjectSetString(0, nt, OBJPROP_FONT, FONT_B);
      ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(0, nt, OBJPROP_COLOR, c);
      ObjectSetInteger(0, nt, OBJPROP_ANCHOR, b ? ANCHOR_UPPER : ANCHOR_LOWER);
      ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
   }
   else if(G_Sig.pass_st)
   {
      bool up = (G_Sig.st_dir == 1);
      string n = OBJ + "BLK_" + ts;
      if(ObjectFind(0, n) < 0) ObjectCreate(0, n, OBJ_ARROW, 0, t, up ? lo - 0.3 * atr : hi + 0.3 * atr);
      ObjectSetInteger(0, n, OBJPROP_ARROWCODE, 251);
      ObjectSetInteger(0, n, OBJPROP_COLOR, P.off);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, up ? ANCHOR_TOP : ANCHOR_BOTTOM);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_TOOLTIP, "Blocked " + (up ? "BUY" : "SELL") + " flip: " + G_Sig.block_reason);
   }
}

void ZoneRect(string n, datetime t1, double p1, datetime t2, double p2, color c)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, n, OBJPROP_FILL, true);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   else { ObjectMove(0, n, 0, t1, p1); ObjectMove(0, n, 1, t2, p2); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void ZoneLine(string n, datetime t1, datetime t2, double p, color c, ENUM_LINE_STYLE st)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_TREND, 0, t1, p, t2, p);
      ObjectSetInteger(0, n, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   else { ObjectMove(0, n, 0, t1, p); ObjectMove(0, n, 1, t2, p); }
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_STYLE, st);
}

void ZoneText(string n, datetime t, double p, string txt, color c)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_TEXT, 0, t, p);
      ObjectSetInteger(0, n, OBJPROP_ANCHOR, ANCHOR_LEFT);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetString(0, n, OBJPROP_FONT, FONT_M);
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 8);
   }
   else ObjectMove(0, n, 0, t, p);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void UpdateZones()
{
   if(!p_ShowZones || (G_Trade.ticket == 0 && !G_PendingOpen)) return;
   datetime t1 = G_Trade.open_time, t2 = TimeCurrent() + PeriodSeconds() * 8;
   datetime tl = t2 + PeriodSeconds();
   double e = G_Trade.entry;
   int dg = _Digits;

   if(G_Trade.sl_init > 0) ZoneRect(OBJ + "Z_RISK", t1, e, t2, G_Trade.sl_init, P.zr);
   if(!G_Trade.nostate && G_Trade.tp1 > 0)
   {
      ZoneRect(OBJ + "Z_R1", t1, e, t2, G_Trade.tp1, P.z1);
      ZoneLine(OBJ + "Z_L1", t1, t2, G_Trade.tp1, P.good, STYLE_DOT);
      ZoneText(OBJ + "Z_T1", tl, G_Trade.tp1, (G_Trade.tp1_hit ? "TP1 ✓ " : "TP1 ") + DoubleToString(G_Trade.tp1, dg), P.good);
      if(p_TP_Levels >= 2)
      {
         ZoneRect(OBJ + "Z_R2", t1, G_Trade.tp1, t2, G_Trade.tp2, P.z2);
         ZoneLine(OBJ + "Z_L2", t1, t2, G_Trade.tp2, P.good, STYLE_DOT);
         ZoneText(OBJ + "Z_T2", tl, G_Trade.tp2, (G_Trade.tp2_hit ? "TP2 ✓ " : "TP2 ") + DoubleToString(G_Trade.tp2, dg), P.good);
      }
      if(p_TP_Levels >= 3)
      {
         ZoneRect(OBJ + "Z_R3", t1, G_Trade.tp2, t2, G_Trade.tp3, P.z3);
         ZoneLine(OBJ + "Z_L3", t1, t2, G_Trade.tp3, P.good, STYLE_DOT);
         ZoneText(OBJ + "Z_T3", tl, G_Trade.tp3, "TP3 " + DoubleToString(G_Trade.tp3, dg), P.good);
      }
   }
   ZoneLine(OBJ + "Z_LE", t1, t2, e, P.text, STYLE_SOLID);
   ZoneText(OBJ + "Z_TE", tl, e, "ENTRY " + DoubleToString(e, dg), P.text);

   double sl = G_Trade.sl;
   if(G_Trade.ticket > 0 && PositionSelectByTicket(G_Trade.ticket)) sl = PositionGetDouble(POSITION_SL);
   if(sl > 0)
   {
      string tag = G_Trade.lock_active ? " LOCK" : (G_Trade.trail_active && Better(sl, G_Trade.sl_init, G_Trade.dir) ? " TRAIL" : (G_Trade.be_done ? " BE" : ""));
      ZoneLine(OBJ + "Z_LS", t1, t2, sl, P.bad, STYLE_DASH);
      ZoneText(OBJ + "Z_TS", tl, sl, "SL " + DoubleToString(sl, dg) + tag, P.bad);
   }
}

void DrawResultMark(ulong pid, double pnl, double r, datetime ct, double cprice)
{
   string id = IntegerToString((long)pid);
   color c = (pnl >= 0) ? P.good : P.bad;
   string nl = OBJ + "RESL_" + id;
   if(ObjectFind(0, nl) < 0) ObjectCreate(0, nl, OBJ_TREND, 0, G_Trade.open_time, G_Trade.entry, ct, cprice);
   ObjectSetInteger(0, nl, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, nl, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, nl, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nl, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nl, OBJPROP_HIDDEN, true);

   string nt = OBJ + "REST_" + id;
   if(ObjectFind(0, nt) < 0) ObjectCreate(0, nt, OBJ_TEXT, 0, ct, cprice);
   ObjectSetString(0, nt, OBJPROP_TEXT, StringFormat(" %+.2fR  %s", r, Money(pnl, true)));
   ObjectSetString(0, nt, OBJPROP_FONT, FONT_B);
   ObjectSetInteger(0, nt, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nt, OBJPROP_COLOR, c);
   ObjectSetInteger(0, nt, OBJPROP_ANCHOR, ANCHOR_LEFT);
   ObjectSetInteger(0, nt, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nt, OBJPROP_HIDDEN, true);
}

//══════════════════════════════════════════════════════════════════
// 🖥️ GLASS HUD — primitives
//══════════════════════════════════════════════════════════════════
void HRect(string n, int x, int y, int w, int h, color bg, color br)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(1, w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE, MathMax(1, h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, br);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, br);
}

void HText(string n, string t, int x, int y, color c, int sz, string font, ENUM_ANCHOR_POINT anc = ANCHOR_LEFT_UPPER)
{
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anc);
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetString(0, n, OBJPROP_FONT, font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, sz);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void SetT(string n, string t, color c)
{
   ObjectSetString(0, n, OBJPROP_TEXT, t);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
}

void SetBox(string n, color bg, color br)
{
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, br);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, br);
}

void SetX(string n, int x)  { ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); }
void SetW(string n, int w)  { ObjectSetInteger(0, n, OBJPROP_XSIZE, MathMax(1, w)); }

void ChipStyle(string box, string txt, int s)
{
   color bg = P.track, br = P.border, tc = P.off;
   if(s == 2)      { bg = P.goodDim; br = P.good; tc = P.good; }
   else if(s == 1) { bg = P.warnDim; br = P.warn; tc = P.warn; }
   else if(s == 0) { bg = P.badDim;  br = P.bad;  tc = P.bad; }
   SetBox(box, bg, br);
   ObjectSetInteger(0, txt, OBJPROP_COLOR, tc);
}

color FracColor(double f) { return f < 0.5 ? P.good : (f < 0.8 ? P.warn : P.bad); }

//══════════════════════════════════════════════════════════════════
// 🖥️ GLASS HUD — build
//══════════════════════════════════════════════════════════════════
void BuildHeader(int X, int Y, int W)
{
   HRect(OBJ + "H_HD", X, Y, W, 30, P.panel, P.border);
   HRect(OBJ + "H_HDA", X, Y, 3, 30, P.accent, P.accent);
   HText(OBJ + "H_HDT", "◆ YOUNGYUU v4.1", X + 12, Y + 6, P.gold, 10, FONT_B);
   HText(OBJ + "H_HDS", _Symbol + " · " + TFName(), X + 140, Y + 10, P.muted, 7, FONT_UI);
   HText(OBJ + "H_TOG", G_HudMin ? "▸" : "▾", X + W - 104, Y + 7, P.muted, 9, FONT_B, ANCHOR_RIGHT_UPPER);
   HRect(OBJ + "H_PILL", X + W - 96, Y + 6, 88, 18, P.card, P.good);
   HText(OBJ + "H_PILLT", "● RUNNING", X + W - 52, Y + 15, P.good, 7, FONT_B, ANCHOR_CENTER);
}

void BuildHUD()
{
   ObjectsDeleteAll(0, OBJ + "H_");
   int X = p_Dash_X, Y = p_Dash_Y, W = DW;

   if(G_HudMin)
   {
      HRect(OBJ + "H_BG", X, Y, W, 52, P.bg, P.border);
      BuildHeader(X, Y, W);
      HText(OBJ + "H_MINI", "", X + 12, Y + 35, P.text, 8, FONT_M);
      G_HudBuilt = true;
      UpdateHUD();
      return;
   }

   int cy = Y;
   HRect(OBJ + "H_BG", X, Y, W, 10, P.bg, P.border);
   BuildHeader(X, Y, W);
   cy += 34;

   // ── KPI cards
   int cw = (W - 16) / 3;
   for(int i = 0; i < 3; i++)
   {
      int cx = X + 4 + i * (cw + 4);
      string k = IntegerToString(i);
      HRect(OBJ + "H_K" + k, cx, cy, cw, 50, P.card, P.border);
      HText(OBJ + "H_KL" + k, "", cx + 8, cy + 5, P.muted, 7, FONT_UI);
      HText(OBJ + "H_KV" + k, "", cx + 8, cy + 17, P.text, 11, FONT_B);
      HText(OBJ + "H_KS" + k, "", cx + 8, cy + 35, P.muted, 7, FONT_UI);
   }
   cy += 56;

   // ── Risk meters
   HRect(OBJ + "H_RM", X + 4, cy, W - 8, 40, P.card, P.border);
   G_MeterX = X + 92; G_MeterW = W - 182;
   for(int i = 0; i < 2; i++)
   {
      int ry = cy + 8 + i * 16;
      string k = IntegerToString(i);
      HText(OBJ + "H_RML" + k, i == 0 ? "DAILY LOSS" : "DRAWDOWN", X + 12, ry - 2, P.muted, 7, FONT_UI);
      HRect(OBJ + "H_RMT" + k, G_MeterX, ry + 2, G_MeterW, 6, P.track, P.track);
      HRect(OBJ + "H_RMF" + k, G_MeterX, ry + 2, 1, 6, P.good, P.good);
      HText(OBJ + "H_RMV" + k, "", X + W - 12, ry - 2, P.text, 7, FONT_M, ANCHOR_RIGHT_UPPER);
   }
   cy += 46;

   // ── Regime gauge
   HRect(OBJ + "H_RG", X + 4, cy, W - 8, 52, P.card, P.border);
   HText(OBJ + "H_RGH", "MARKET REGIME", X + 12, cy + 5, P.muted, 7, FONT_B);
   HText(OBJ + "H_RGS", "", X + W - 12, cy + 5, P.muted, 7, FONT_UI, ANCHOR_RIGHT_UPPER);
   string rn[3] = {"SIDEWAYS", "WEAK TREND", "STRONG"};
   int sw = (W - 24 - 8) / 3;
   for(int i = 0; i < 3; i++)
   {
      int sx = X + 12 + i * (sw + 4);
      string k = IntegerToString(i);
      HRect(OBJ + "H_RGB" + k, sx, cy + 19, sw, 15, P.track, P.border);
      HText(OBJ + "H_RGT" + k, rn[i], sx + sw / 2, cy + 26, P.muted, 7, FONT_B, ANCHOR_CENTER);
   }
   HText(OBJ + "H_RGI", "", X + 12, cy + 37, P.text, 7, FONT_M);
   cy += 58;

   // ── Signal confluence
   HRect(OBJ + "H_CF", X + 4, cy, W - 8, 76, P.card, P.border);
   HText(OBJ + "H_CFH", "SIGNAL CONFLUENCE", X + 12, cy + 5, P.muted, 7, FONT_B);
   HText(OBJ + "H_CFS", "", X + W - 12, cy + 4, P.text, 8, FONT_B, ANCHOR_RIGHT_UPPER);
   string cn[10] = {"ST", "REGIME", "EMA", "RSI", "BODY", "MOM", "HTF", "SESSION", "SPREAD", "NEWS"};
   int chw = (W - 24 - 16) / 5;
   for(int i = 0; i < 10; i++)
   {
      int r = i / 5, c = i % 5;
      int chx = X + 12 + c * (chw + 4), chy = cy + 20 + r * 19;
      string k = IntegerToString(i);
      HRect(OBJ + "H_CH" + k, chx, chy, chw, 16, P.track, P.border);
      HText(OBJ + "H_CHT" + k, cn[i], chx + chw / 2, chy + 8, P.off, 7, FONT_B, ANCHOR_CENTER);
   }
   HText(OBJ + "H_CFR", "", X + 12, cy + 60, P.text, 7, FONT_UI);
   cy += 82;

   // ── AI core
   HRect(OBJ + "H_AI", X + 4, cy, W - 8, 96, P.card, P.border);
   HText(OBJ + "H_AIH", "AI ADAPTIVE CORE", X + 12, cy + 5, P.muted, 7, FONT_B);
   HText(OBJ + "H_AIS", "", X + W - 12, cy + 4, P.accent, 8, FONT_B, ANCHOR_RIGHT_UPPER);
   HText(OBJ + "H_AIL", "WIN RATE", X + 12, cy + 21, P.muted, 7, FONT_UI);
   G_AIBarX = X + 92; G_AIBarW = W - 182;
   HRect(OBJ + "H_AIT", G_AIBarX, cy + 25, G_AIBarW, 6, P.track, P.track);
   HRect(OBJ + "H_AIF", G_AIBarX, cy + 25, 1, 6, P.good, P.good);
   HText(OBJ + "H_AIV", "", X + W - 12, cy + 21, P.text, 7, FONT_M, ANCHOR_RIGHT_UPPER);
   HText(OBJ + "H_AI1", "", X + 12, cy + 35, P.text, 7, FONT_M);
   HText(OBJ + "H_AI2", "", X + 12, cy + 48, P.text, 7, FONT_M);
   G_SparkX = X + 12; G_SparkY = cy + 62; G_SparkH = 28;
   int spw = W - 24;
   HRect(OBJ + "H_SPB", G_SparkX, G_SparkY, spw, G_SparkH, P.panel, P.border);
   HRect(OBJ + "H_SPM", G_SparkX, G_SparkY + G_SparkH / 2, spw, 1, P.border, P.border);
   G_SparkBW = (spw - 4) / SPARK_N;
   for(int i = 0; i < SPARK_N; i++)
      HRect(OBJ + "H_SP" + IntegerToString(i), G_SparkX + 2 + i * G_SparkBW, G_SparkY + G_SparkH / 2, G_SparkBW - 2, 1, P.off, P.off);
   cy += 102;

   // ── Position
   HRect(OBJ + "H_PS", X + 4, cy, W - 8, 92, P.card, P.border);
   HText(OBJ + "H_PSH", "POSITION", X + 12, cy + 5, P.muted, 7, FONT_B);
   HText(OBJ + "H_PSR", "", X + W - 12, cy + 5, P.muted, 7, FONT_M, ANCHOR_RIGHT_UPPER);
   HText(OBJ + "H_PSD", "", X + 12, cy + 18, P.text, 9, FONT_B);
   HText(OBJ + "H_PSP", "", X + W - 12, cy + 18, P.text, 9, FONT_B, ANCHOR_RIGHT_UPPER);
   G_TrkX = X + 16; G_TrkW = W - 32; G_TrkY = cy + 46;
   HRect(OBJ + "H_TRK", G_TrkX, G_TrkY, G_TrkW, 4, P.track, P.track);
   HRect(OBJ + "H_TRF", G_TrkX, G_TrkY, 1, 4, P.track, P.track);
   string mk[5] = {"SL", "E", "1", "2", "3"};
   for(int i = 0; i < 5; i++)
   {
      string k = IntegerToString(i);
      HRect(OBJ + "H_MK" + k, G_TrkX, G_TrkY - 4, 2, 12, P.card, P.card);
      HText(OBJ + "H_MKT" + k, mk[i], G_TrkX, G_TrkY + 10, P.card, 6, FONT_M, ANCHOR_UPPER);
   }
   HRect(OBJ + "H_MKC", G_TrkX, G_TrkY - 6, 2, 16, P.card, P.card);
   HRect(OBJ + "H_DOT", G_TrkX, G_TrkY - 3, 10, 10, P.card, P.card);
   string sn[4] = {"BE", "TRAIL", "LOCK", "TIME"};
   int sw2 = (W - 24 - 12) / 4;
   for(int i = 0; i < 4; i++)
   {
      int sx = X + 12 + i * (sw2 + 4);
      string k = IntegerToString(i);
      HRect(OBJ + "H_ST" + k, sx, cy + 70, sw2, 15, P.track, P.border);
      HText(OBJ + "H_STT" + k, sn[i], sx + sw2 / 2, cy + 77, P.off, 7, FONT_B, ANCHOR_CENTER);
   }
   cy += 98;

   // ── Footer
   HText(OBJ + "H_FT", "", X + 12, cy, P.muted, 7, FONT_M);
   cy += 16;
   ObjectSetInteger(0, OBJ + "H_BG", OBJPROP_YSIZE, cy - Y);

   G_HudBuilt = true;
   UpdateHUD();
}

//══════════════════════════════════════════════════════════════════
// 🖥️ GLASS HUD — update
//══════════════════════════════════════════════════════════════════
int TrackX(double price)
{
   double a = G_Trade.sl_init, b = LastTP();
   if(a <= 0 || b <= 0 || MathAbs(b - a) < _Point) return G_TrkX;
   double f = (price - a) / (b - a);
   f = MathMax(0.0, MathMin(1.0, f));
   return G_TrkX + (int)MathRound(f * G_TrkW);
}

void SetMeter(string fill, string val, int x0, int w0, double frac, string txt)
{
   double f = MathMax(0.0, MathMin(1.0, frac));
   int w = (int)MathRound(w0 * f);
   color c = FracColor(f);
   SetW(fill, w);
   SetBox(fill, w < 1 ? P.track : c, w < 1 ? P.track : c);
   SetT(val, txt, f >= 0.8 ? P.bad : P.text);
}

void UpdateHUD()
{
   if(!G_HudBuilt || !p_ShowDash) return;

   double bal = AccountInfoDouble(ACCOUNT_BALANCE), eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double dpct = (G_Risk.day_start_bal > 0) ? G_Risk.daily_pnl / G_Risk.day_start_bal * 100.0 : 0;
   string why = "";
   bool run = AllowTrading(why);
   bool pos_on = (G_Trade.ticket > 0 && PositionSelectByTicket(G_Trade.ticket));

   // ── Status pill
   string ps; color pc;
   if(G_Risk.dd_kill)          { ps = "■ DD KILL";  pc = P.bad; }
   else if(G_Risk.limit_hit)   { ps = "■ STOPPED";  pc = P.bad; }
   else if(CooldownActive())   { ps = "◔ COOLDOWN"; pc = P.warn; }
   else if(pos_on)             { ps = "◉ IN TRADE"; pc = P.accent; }
   else if(run)                { ps = "● RUNNING";  pc = P.good; }
   else                        { ps = "◌ PAUSED";   pc = P.warn; }
   SetT(OBJ + "H_PILLT", ps, pc);
   SetBox(OBJ + "H_PILL", P.card, pc);
   ObjectSetString(0, OBJ + "H_PILL", OBJPROP_TOOLTIP, why);

   if(G_HudMin)
   {
      string pstr = "FLAT";
      if(pos_on)
      {
         double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         pstr = (G_Trade.dir == 1 ? "LONG " : "SHORT ") + Money(pnl, true);
      }
      SetT(OBJ + "H_MINI", StringFormat("EQ %s  D %+.2f%%  %s", Money(eq), dpct, pstr), dpct >= 0 ? P.text : P.bad);
      UpdateZones();
      ChartRedraw(0);
      return;
   }

   // ── KPI
   SetT(OBJ + "H_KL0", "EQUITY", P.muted);
   SetT(OBJ + "H_KV0", Money(eq), P.text);
   SetT(OBJ + "H_KS0", "Bal " + Money(bal), P.muted);
   SetT(OBJ + "H_KL1", "TODAY", P.muted);
   SetT(OBJ + "H_KV1", StringFormat("%+.2f%%", dpct), dpct >= 0 ? P.good : P.bad);
   SetT(OBJ + "H_KS1", StringFormat("%s · %dT %dW", Money(G_Risk.daily_pnl, true), G_Risk.trades_today, G_Risk.wins_today), P.muted);
   double ddf = (p_MaxDD_Pct > 0) ? G_Risk.current_dd / p_MaxDD_Pct : 0;
   SetT(OBJ + "H_KL2", "DRAWDOWN", P.muted);
   SetT(OBJ + "H_KV2", StringFormat("%.2f%%", G_Risk.current_dd), FracColor(ddf));
   SetT(OBJ + "H_KS2", StringFormat("Max %.2f%%", G_Risk.max_dd), P.muted);

   // ── Risk meters
   double dl_used = (dpct < 0) ? -dpct : 0;
   SetMeter(OBJ + "H_RMF0", OBJ + "H_RMV0", G_MeterX, G_MeterW, p_Daily_Loss > 0 ? dl_used / p_Daily_Loss : 0,
            StringFormat("%.2f / %.1f%%", dl_used, p_Daily_Loss));
   SetMeter(OBJ + "H_RMF1", OBJ + "H_RMV1", G_MeterX, G_MeterW, ddf,
            StringFormat("%.2f / %.1f%%", G_Risk.current_dd, p_MaxDD_Pct));

   // ── Regime
   int act = !G_Sig.valid ? -1 : (G_Sig.strong_trend ? 2 : (G_Sig.weak_trend ? 1 : 0));
   color rc[3]; rc[0] = P.bad; rc[1] = P.warn; rc[2] = P.good;
   for(int i = 0; i < 3; i++)
   {
      string k = IntegerToString(i);
      if(i == act) { SetBox(OBJ + "H_RGB" + k, rc[i], rc[i]); ObjectSetInteger(0, OBJ + "H_RGT" + k, OBJPROP_COLOR, P.bg); }
      else         { SetBox(OBJ + "H_RGB" + k, P.track, P.border); ObjectSetInteger(0, OBJ + "H_RGT" + k, OBJPROP_COLOR, P.off); }
   }
   SetT(OBJ + "H_RGS", GetSessionStr(), SessionOK() ? P.good : P.muted);
   SetT(OBJ + "H_RGI", StringFormat("ADX %.1f/%.0f  TSF %.2fx  BBW %.2f%%", G_Sig.adx, G_Sig.adx_thresh,
                                    G_Sig.tsf_ratio, G_Sig.bbw * 100), P.text);

   // ── Confluence chips
   int s[10]; ConfStates(s);
   int pass, total; ConfScore(s, pass, total);
   for(int i = 0; i < 10; i++) ChipStyle(OBJ + "H_CH" + IntegerToString(i), OBJ + "H_CHT" + IntegerToString(i), s[i]);
   bool bull = (G_Sig.st_dir == 1);
   double sf = (total > 0) ? (double)pass / total : 0;
   SetT(OBJ + "H_CFS", StringFormat("%s %d/%d", bull ? "▲ BULL" : "▼ BEAR", pass, total),
        sf >= 0.8 ? (bull ? P.good : P.bad) : (sf >= 0.5 ? P.warn : P.muted));
   string reason = run ? G_Sig.block_reason : ("⏸ " + why + " · " + G_Sig.block_reason);
   if(StringLen(reason) > 58) reason = StringSubstr(reason, 0, 57) + "…";
   color rcol = (G_Sig.buy || G_Sig.sell) ? (G_Sig.buy ? P.good : P.bad) : (run ? P.text : P.warn);
   SetT(OBJ + "H_CFR", reason, rcol);

   // ── AI
   color aic = (G_AI.signal == "SCALE UP") ? P.good : (G_AI.signal == "DEFENSIVE" ? P.bad : P.accent);
   SetT(OBJ + "H_AIS", StringFormat("%s %.0f%%", G_AI.signal, G_AI.confidence), aic);
   double wrf = G_AI.wr;
   int ww = (int)MathRound(G_AIBarW * wrf);
   color wc = (wrf >= p_AI_WinThresh) ? P.good : (wrf >= p_AI_LossThresh ? P.warn : P.bad);
   SetW(OBJ + "H_AIF", ww);
   SetBox(OBJ + "H_AIF", ww < 1 ? P.track : wc, ww < 1 ? P.track : wc);
   SetT(OBJ + "H_AIV", StringFormat("%.0f%% %dW/%dL", wrf * 100, G_AI.wins, G_AI.n - G_AI.wins), P.text);
   SetT(OBJ + "H_AI1", StringFormat("PF %.2f   Exp %+.2fR   n=%d   W%d/L%d", G_AI.pf, G_AI.exp_r, G_AI.n, G_AI.consec_w, G_AI.consec_l),
        G_AI.exp_r >= 0 ? P.text : P.bad);
   double ge; int gn;
   bool gfail = G_Sig.valid && RegimeGateFails(CurrentRegime(), ge, gn);
   double rm = RiskMultiplier();
   SetT(OBJ + "H_AI2", StringFormat("Risk x%.2f (%.2f%%)  Gate %s %+.2fR/%d%s", rm, p_Risk_Pct * rm,
                                    RegimeName(CurrentRegime()), ge, gn, gfail ? " ✕" : ""),
        gfail ? P.warn : P.muted);

   // sparkline (ล่าสุดอยู่ขวา)
   int shown = MathMin(SPARK_N, AI_Count);
   double maxr = 1.0;
   for(int k = AI_Count - shown; k < AI_Count; k++) maxr = MathMax(maxr, MathAbs(AI_R[AIIdx(k)]));
   int half = G_SparkH / 2 - 2, mid = G_SparkY + G_SparkH / 2;
   for(int i = 0; i < SPARK_N; i++)
   {
      string n = OBJ + "H_SP" + IntegerToString(i);
      int slot = i - (SPARK_N - shown);
      if(slot < 0)
      {
         ObjectSetInteger(0, n, OBJPROP_YDISTANCE, mid);
         ObjectSetInteger(0, n, OBJPROP_YSIZE, 1);
         SetBox(n, P.off, P.off);
         continue;
      }
      double r = AI_R[AIIdx(AI_Count - shown + slot)];
      int h = MathMax(2, (int)MathRound(MathMin(1.0, MathAbs(r) / maxr) * half));
      bool pos = (AI_Pnl[AIIdx(AI_Count - shown + slot)] >= 0);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, pos ? mid - h : mid + 1);
      ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
      SetBox(n, pos ? P.good : P.bad, pos ? P.good : P.bad);
   }

   // ── Position
   if(pos_on)
   {
      MqlTick tk; SymbolInfoTick(_Symbol, tk);
      int dir = G_Trade.dir;
      double cp = (dir == 1) ? tk.bid : tk.ask;
      double pnl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double rdist = MathAbs(G_Trade.entry - G_Trade.sl_init);
      double rlive = (rdist > 0) ? (cp - G_Trade.entry) * dir / rdist : 0;
      string mode = G_Trade.nostate ? "RESTORED" : (G_Trade.is_scalp ? "SCALP" : (G_Trade.is_strong ? "STRONG" : "WEAK"));
      color dc = (dir == 1) ? P.good : P.bad;
      SetT(OBJ + "H_PSD", StringFormat("%s · %s · %.2f", dir == 1 ? "▲ LONG" : "▼ SHORT", mode, PositionGetDouble(POSITION_VOLUME)), dc);
      SetT(OBJ + "H_PSP", Money(pnl, true), pnl >= 0 ? P.good : P.bad);
      SetT(OBJ + "H_PSR", StringFormat("%+.2fR · MFE %.2fR", rlive,
                                       rdist > 0 ? (G_Trade.mfe_price - G_Trade.entry) * dir / rdist : 0), P.muted);

      bool track_ok = (G_Trade.sl_init > 0 && LastTP() > 0 && !G_Trade.nostate);
      SetBox(OBJ + "H_TRK", track_ok ? P.track : P.card, track_ok ? P.track : P.card);
      double mp[5]; mp[0] = G_Trade.sl_init; mp[1] = G_Trade.entry; mp[2] = G_Trade.tp1; mp[3] = G_Trade.tp2; mp[4] = G_Trade.tp3;
      bool hit[5]; hit[0] = false; hit[1] = false; hit[2] = G_Trade.tp1_hit; hit[3] = G_Trade.tp2_hit; hit[4] = G_Trade.tp3_hit;
      for(int i = 0; i < 5; i++)
      {
         string k = IntegerToString(i);
         bool vis = track_ok && (i < 3 || (i == 3 && p_TP_Levels >= 2) || (i == 4 && p_TP_Levels >= 3));
         color mc = !vis ? P.card : (i == 0 ? P.bad : (i == 1 ? P.text : (hit[i] ? P.good : P.muted)));
         int x = TrackX(mp[i]);
         SetX(OBJ + "H_MK" + k, x - 1);  SetBox(OBJ + "H_MK" + k, mc, mc);
         SetX(OBJ + "H_MKT" + k, x);     ObjectSetInteger(0, OBJ + "H_MKT" + k, OBJPROP_COLOR, mc);
      }
      if(track_ok)
      {
         int xe = TrackX(G_Trade.entry), xp = TrackX(cp);
         color fc = ((cp - G_Trade.entry) * dir >= 0) ? P.good : P.bad;
         SetX(OBJ + "H_TRF", MathMin(xe, xp)); SetW(OBJ + "H_TRF", MathAbs(xp - xe)); SetBox(OBJ + "H_TRF", fc, fc);
         SetX(OBJ + "H_DOT", xp - 5); SetBox(OBJ + "H_DOT", fc, P.bg);
         double csl = PositionGetDouble(POSITION_SL);
         if(csl > 0) { SetX(OBJ + "H_MKC", TrackX(csl) - 1); SetBox(OBJ + "H_MKC", P.warn, P.warn); }
         else SetBox(OBJ + "H_MKC", P.card, P.card);
      }
      else
      {
         SetBox(OBJ + "H_TRF", P.card, P.card); SetBox(OBJ + "H_DOT", P.card, P.card); SetBox(OBJ + "H_MKC", P.card, P.card);
      }

      int bars = iBarShift(_Symbol, PERIOD_CURRENT, G_Trade.open_time, false);
      int st[4];
      st[0] = G_Trade.be_done ? 2 : (p_UseBreakeven ? 1 : -1);
      st[1] = G_Trade.trail_active ? 2 : (p_UseTrail ? 1 : -1);
      st[2] = G_Trade.lock_active ? 2 : (p_UseLockProfit ? 1 : -1);
      st[3] = (!p_UseTimeStop || G_Trade.tp1_hit || G_Trade.nostate) ? -1 : (bars >= (int)(p_TimeStopBars * 0.7) ? 0 : 1);
      for(int i = 0; i < 4; i++) ChipStyle(OBJ + "H_ST" + IntegerToString(i), OBJ + "H_STT" + IntegerToString(i), st[i]);
      ObjectSetString(0, OBJ + "H_STT2", OBJPROP_TEXT, G_Trade.lock_active ? "LOCK L" + IntegerToString(G_Trade.lock_level) : "LOCK");
      ObjectSetString(0, OBJ + "H_STT3", OBJPROP_TEXT, st[3] >= 0 ? StringFormat("T %d/%d", bars, p_TimeStopBars) : "TIME");
   }
   else
   {
      SetT(OBJ + "H_PSD", G_PendingOpen ? "◌ SYNCING ORDER..." : "◌ NO POSITION", P.muted);
      SetT(OBJ + "H_PSP", "", P.muted);
      SetT(OBJ + "H_PSR", G_NextLot > 0 ? StringFormat("next ≈ %.2f lot", G_NextLot) : "", P.muted);
      SetBox(OBJ + "H_TRK", P.track, P.track);
      SetBox(OBJ + "H_TRF", P.card, P.card); SetBox(OBJ + "H_DOT", P.card, P.card); SetBox(OBJ + "H_MKC", P.card, P.card);
      for(int i = 0; i < 5; i++)
      {
         SetBox(OBJ + "H_MK" + IntegerToString(i), P.card, P.card);
         ObjectSetInteger(0, OBJ + "H_MKT" + IntegerToString(i), OBJPROP_COLOR, P.card);
      }
      for(int i = 0; i < 4; i++) ChipStyle(OBJ + "H_ST" + IntegerToString(i), OBJ + "H_STT" + IntegerToString(i), -1);
      ObjectSetString(0, OBJ + "H_STT2", OBJPROP_TEXT, "LOCK");
      ObjectSetString(0, OBJ + "H_STT3", OBJPROP_TEXT, "TIME");
   }

   // ── Footer
   SetT(OBJ + "H_FT", StringFormat("SPR %d · ATR %s · %s · %s", GetSpread(), DoubleToString(G_Sig.atr, _Digits),
                                   p_Engine == ENGINE_PINE ? "PINE" : "LEGACY",
                                   TimeToString(TimeCurrent(), TIME_SECONDS)), P.muted);

   UpdateZones();
   ChartRedraw(0);
}
//+------------------------------------------------------------------+
//| END — YOUNGYUU Master v4.1 Gold Edition                           |
//+------------------------------------------------------------------+
