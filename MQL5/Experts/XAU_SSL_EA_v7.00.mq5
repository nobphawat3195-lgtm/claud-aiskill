//+------------------------------------------------------------------+
//|  XAU_SSL_EA v7.00 — SSL channel (SSL Hybrid core, Mihkel00) H1    |
//|  Logic (= ind10.py backtest):                                     |
//|   HMA(60) of High and HMA(60) of Low on closed H1 bars             |
//|   state = +1 when close > HMA(high), -1 when close < HMA(low)      |
//|   state flip -> close opposite position, open new one              |
//|   SL = 1.5 x ATR(14, Wilder) from entry, no TP, exit on next flip  |
//|  Backtest real tick Dukascopy Nov 2025 - Nov 2026, H1:             |
//|   341 trades, win 33%, avg +0.27R, +92.9R (Nov-Jun +0.29R,         |
//|   Jul-Nov +0.24R), longs +48R / shorts +45R, beats 99.9% of random |
//|   PBO 0.095 over 29 indicator x TF configs, DSR 0.67 (< 0.95)      |
//|   Cent 30,000 USC risk 2%: -> ~143,800 USC, DD 24%                 |
//|  SL median ~27 USD: on Standard USD 300 the 0.01 lot risks ~9%,    |
//|  so use a Cent account (or Standard >= USD 1,000).                 |
//+------------------------------------------------------------------+
#property copyright "XAU SSL EA"
#property version   "7.00"
#property strict
#include <Trade\Trade.mqh>

input int    InpHMALen     = 60;    // HMA length (SSL1)
input int    InpATRLen     = 14;    // ATR period (Wilder)
input double InpSLATR      = 1.5;   // SL = k x ATR
input double InpRiskPct    = 2.0;   // risk per trade (% equity)
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
bool Calc(int &state, double &atr)
{
   MqlRates r[];
   int n = CopyRates(_Symbol, PERIOD_H1, 1, 600, r);        // r[n-1] = last closed bar
   if(n < 300) return false;
   double hi[], lo[]; ArrayResize(hi, n); ArrayResize(lo, n);
   for(int i = 0; i < n; i++) { hi[i] = r[i].high; lo[i] = r[i].low; }
   int st = 0, need = InpHMALen + (int)MathSqrt(InpHMALen) + 2;
   for(int i = need; i < n; i++)
   {
      double eh = HMAat(hi, i, InpHMALen), el = HMAat(lo, i, InpHMALen);
      if(r[i].close > eh) st = 1; else if(r[i].close < el) st = -1;
   }
   double a = r[0].high - r[0].low, al = 1.0 / InpATRLen;
   for(int i = 1; i < n; i++)
   {
      double pc = r[i - 1].close, tr = MathMax(r[i].high - r[i].low, MathMax(MathAbs(r[i].high - pc), MathAbs(r[i].low - pc)));
      a += al * (tr - a);
   }
   state = st; atr = a; return true;
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
   double a; Calc(gState, a);                                // start from the current state: no trade until the next flip
   return INIT_SUCCEEDED;
}
void OnTick()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY); gPeak = MathMax(gPeak, eq);
   double dd = gPeak > 0 ? (gPeak - eq) / gPeak * 100 : 0;
   if(!gHalted && dd >= InpDDHalt) { gHalted = true; ulong t = OpenTicket(); if(t > 0) trade.PositionClose(t); Print("XAU SSL: DD halt"); }
   datetime bar = iTime(_Symbol, PERIOD_H1, 0);
   if(bar == gLastBar) return;
   gLastBar = bar;
   int st; double atr;
   if(!Calc(st, atr) || st == 0 || st == gState) { Comment(StringFormat("XAU SSL v7.00 | state %d | DD %.1f%%", gState, dd)); return; }
   gState = st;
   ulong tk = OpenTicket();
   if(tk > 0) trade.PositionClose(tk);
   if(gHalted) return;
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
