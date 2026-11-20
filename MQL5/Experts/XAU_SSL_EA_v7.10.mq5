//+------------------------------------------------------------------+
//|  XAU_SSL_EA v7.10 — SSL channel (SSL Hybrid core) any TF + D1 trend |
//|  Attach to the chart TF you want; run several charts with different |
//|  InpMagic to build the portfolio. Presets (latest year, real ticks): |
//|   H1  InpHMALen=60  InpUseD1=false: 331 tr, +0.30R, beats rnd 99.9%  |
//|   M15 InpHMALen=320 InpUseD1=true : 253 tr, +0.55R (opt round 2)     |
//|   M15 InpHMALen=240 InpUseD1=true : 306 tr, +0.29R, beats rnd 96.9%  |
//|   M5  InpHMALen=960 InpUseD1=true : 452 tr, +0.40R (Jul-Nov +0.17R)  |
//|   M5  InpHMALen=720 InpUseD1=true : 552 tr, +0.24R, beats rnd 97.7%  |
//|  HMA length ~ 60 hours of bars is the key; HMA 60 on M1-M30 loses.  |
//|  Portfolio M15+H1 Cent USD 300 risk 1%: -> ~1,437, DD 30%, ~51/month |
//|  Portfolio M5+M15+H1 risk 0.5%: -> ~1,076, DD 33%, ~96/month          |
//|  Win rate 16-33%, losing streaks up to 25 trades: Cent account only  |
//|  (Standard USD 300: 0.01 lot forces 2.4-9% risk -> DD halt).         |
//|  D1 filter: new entries only in the direction of D1 close vs EMA20;  |
//|  an opposite SSL flip still closes the position.                     |
//+------------------------------------------------------------------+
#property copyright "XAU SSL EA"
#property version   "7.10"
#property strict
#include <Trade\Trade.mqh>

input int    InpHMALen     = 60;    // HMA length (SSL1)
input int    InpATRLen     = 14;    // ATR period (Wilder)
input double InpSLATR      = 1.5;   // SL = k x ATR
input bool   InpUseD1      = false; // D1 trend filter (true for M5/M15 presets)
input int    InpD1EMA      = 20;    // D1 EMA period
input double InpRiskPct    = 1.0;   // risk per trade (% equity)
input double InpMinLotCap  = 5.5;   // if min lot needed: trade only if real risk <= this (%)
input double InpDDHalt     = 45.0;  // stop EA at this DD from peak (%)
input double InpMaxSpreadUSD = 1.5;
input long   InpMagic      = 887000;

CTrade trade;
datetime gLastBar = 0;
int gState = 0;
double gPeak = 0;
bool gHalted = false;

double WMA(const double &x[], int end, int n)          // x oldest->newest, WMA ending at index end
{
   double s = 0, w = 0;
   for(int k = 0; k < n; k++) { double wk = n - k; s += x[end - k] * wk; w += wk; }
   return s / w;
}
double HMAat(const double &x[], int end, int n)
{
   int h = n / 2, q = (int)MathFloor(MathSqrt(n));
   double tmp[]; ArrayResize(tmp, q);
   for(int k = 0; k < q; k++) tmp[k] = 2 * WMA(x, end - (q - 1 - k), h) - WMA(x, end - (q - 1 - k), n);
   return WMA(tmp, q - 1, q);
}
double gATR = 0;
bool Calc(int &state, double &atr, bool full)
{
   int need = InpHMALen + (int)MathSqrt(InpHMALen) + 5, cnt = full ? MathMax(need + 1500, 2500) : need + 3;
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_CURRENT, 1, cnt, r);   // r[n-1] = last closed bar
   if(n < need + 2) return false;
   double hi[], lo[]; ArrayResize(hi, n); ArrayResize(lo, n);
   for(int i = 0; i < n; i++) { hi[i] = r[i].high; lo[i] = r[i].low; }
   int st = full ? 0 : gState;
   for(int i = full ? need : n - 1; i < n; i++)
   {
      double eh = HMAat(hi, i, InpHMALen), el = HMAat(lo, i, InpHMALen);
      if(r[i].close > eh) st = 1; else if(r[i].close < el) st = -1;
   }
   if(full)
   {
      double a = r[0].high - r[0].low, al = 1.0 / InpATRLen;
      for(int i = 1; i < n; i++)
      {
         double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
         a += al * (tr - a);
      }
      gATR = a;
   }
   else
   {
      double pc = r[n - 2].close, tr = MathMax(r[n - 1].high - r[n - 1].low, MathMax(MathAbs(r[n - 1].high - pc), MathAbs(r[n - 1].low - pc)));
      gATR += (tr - gATR) / InpATRLen;
   }
   state = st; atr = gATR; return true;
}
int D1Trend()
{
   int h = iMA(_Symbol, PERIOD_D1, InpD1EMA, 0, MODE_EMA, PRICE_CLOSE);
   double e[]; int t = 0;
   if(h != INVALID_HANDLE && CopyBuffer(h, 0, 1, 1, e) == 1) t = iClose(_Symbol, PERIOD_D1, 1) > e[0] ? 1 : -1;
   if(h != INVALID_HANDLE) IndicatorRelease(h);
   return t;
}
ulong OpenTicket()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong t = PositionGetTicket(i);
      if(t > 0 && PositionGetString(POSITION_SYMBOL) == _Symbol && PositionGetInteger(POSITION_MAGIC) == InpMagic) return t;
   }
   return 0;
}
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic); trade.SetTypeFillingBySymbol(_Symbol); trade.SetDeviationInPoints(50);
   gPeak = AccountInfoDouble(ACCOUNT_EQUITY);
   double a; Calc(gState, a, true);                                // start from the current state: no trade until the next flip
   return INIT_SUCCEEDED;
}
void OnTick()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY); gPeak = MathMax(gPeak, eq);
   double dd = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   if(!gHalted && dd >= InpDDHalt) { gHalted = true; ulong t = OpenTicket(); if(t > 0) trade.PositionClose(t); Print("XAU SSL: DD halt"); }
   datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar == gLastBar) return;
   gLastBar = bar;
   int st; double atr;
   if(!Calc(st, atr, false) || st == 0 || st == gState) { Comment(StringFormat("XAU SSL v7.10 | state %d | DD %.1f%%", gState, dd)); return; }
   gState = st;
   ulong tk = OpenTicket();
   if(tk > 0) trade.PositionClose(tk);
   if(gHalted) return;
   if(InpUseD1 && D1Trend() != st) return;                   // flip against D1 trend: flat, no new entry
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpreadUSD) return;
   double entry = st > 0 ? ask : bid, sl = NormalizeDouble(entry - st * InpSLATR * atr, _Digits), dist = InpSLATR * atr;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP), vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double perLot = dist / ts * tv;
   double lots = MathFloor(eq * InpRiskPct / 100.0 / perLot / step) * step;
   if(lots < vmin) { if(vmin * perLot / eq * 100.0 <= InpMinLotCap) lots = vmin; else { Print("XAU SSL: skip, min lot risk ", DoubleToString(vmin * perLot / eq * 100.0, 1), "%"); return; } }
   lots = NormalizeDouble(MathMin(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX)), 2);
   if(st > 0) trade.Buy(lots, _Symbol, 0, sl, 0, "SSL"); else trade.Sell(lots, _Symbol, 0, sl, 0, "SSL");
}
