//+------------------------------------------------------------------+
//| YOUNGYUU Lorentzian ML EA v1.0  (MetaTrader 5 · XAUUSD)          |
//|------------------------------------------------------------------|
//| Port of "Machine Learning: Lorentzian Classification" © jdehorty |
//| (TradingView Pine Script, Mozilla Public License 2.0) to MQL5.   |
//| This file is subject to the terms of the Mozilla Public License  |
//| 2.0 at https://mozilla.org/MPL/2.0/  · credit: jdehorty          |
//|                                                                  |
//| ค่าเริ่มต้น = แบบ Original:                                        |
//|   • เข้าไม้เมื่อเกิดสัญญาณ BUY/SELL (เปิดที่ราคาเปิดแท่งถัดไป)       |
//|   • ออกเมื่อครบ 4 แท่ง หรือสัญญาณพลิกก่อนครบ (early flip)          |
//|   • ไม่มี SL / TP  (ปรับได้ในกลุ่ม "SL / TP")                       |
//| คำนวณเฉพาะแท่งที่ปิดแล้ว → ไม่ repaint                               |
//+------------------------------------------------------------------+
#property copyright "YOUNGYUU · ML core by jdehorty (MPL-2.0)"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.00"
#property description "YOUNGYUU Lorentzian ML EA — Lorentzian KNN classification (jdehorty, MPL-2.0) for MT5"

#include <Trade\Trade.mqh>

//--- enums
enum ENUM_YY_FEAT  { F_RSI = 0, F_WT = 1, F_CCI = 2, F_ADX = 3 };
enum ENUM_YY_EXIT  { EXIT_ORIGINAL = 0,   // Original: ออกเมื่อครบ 4 แท่ง / สัญญาณพลิก
                     EXIT_SLTP_ONLY = 1 }; // ออกด้วย SL / TP เท่านั้น
enum ENUM_YY_SL    { SL_NONE = 0,   // ไม่มี (Original)
                     SL_FIXED = 1,  // คงที่ (จุด)
                     SL_ATR = 2,    // ATR
                     SL_SWING = 3 };// Swing (ใต้/เหนือ swing)
enum ENUM_YY_TP    { TP_NONE = 0,   // ไม่มี (Original)
                     TP_R = 1,      // เท่าของ SL (R)
                     TP_FIXED = 2 };// คงที่ (จุด)
enum ENUM_YY_LOT   { LOT_FIXED = 0, // Lot คงที่
                     LOT_RISK = 1 };// Risk % (ต้องมี SL)

//--- inputs: ML (ตั้งให้ตรงกับ TradingView)
input group "=== 🧠 ML (ค่าเดียวกับ TradingView) ==="
input int     InpNeighbors    = 8;      // Neighbors Count
input int     InpMaxBarsBack  = 2000;   // Max Bars Back
input int     InpFeatureCount = 5;      // Feature Count (2-5)
input int     InpHistoryBars  = 5000;   // จำนวนแท่งข้อมูล (ให้ใกล้กับที่ TradingView โหลด)
input bool    InpFullHistory  = false;  // Include Full History
input ENUM_YY_FEAT InpF1 = F_RSI; input int InpF1A = 14; input int InpF1B = 1;
input ENUM_YY_FEAT InpF2 = F_WT;  input int InpF2A = 10; input int InpF2B = 11;
input ENUM_YY_FEAT InpF3 = F_CCI; input int InpF3A = 20; input int InpF3B = 1;
input ENUM_YY_FEAT InpF4 = F_ADX; input int InpF4A = 20; input int InpF4B = 2;
input ENUM_YY_FEAT InpF5 = F_RSI; input int InpF5A = 9;  input int InpF5B = 1;

input group "=== 🔎 ตัวกรอง ==="
input bool    InpUseVol       = true;   // Use Volatility Filter
input bool    InpUseRegime    = true;   // Use Regime Filter
input double  InpRegimeThr    = -0.1;   // Regime Threshold
input bool    InpUseAdx       = false;  // Use ADX Filter
input int     InpAdxThr       = 20;     // ADX Threshold
input bool    InpUseEma       = false;  // Use EMA Filter
input int     InpEmaPeriod    = 200;    // EMA Period
input bool    InpUseSma       = false;  // Use SMA Filter
input int     InpSmaPeriod    = 200;    // SMA Period

input group "=== 〰️ Kernel ==="
input bool    InpUseKernel    = true;   // Trade with Kernel
input bool    InpKernelSmooth = false;  // Enhance Kernel Smoothing
input int     InpH            = 8;      // Lookback Window
input double  InpR            = 8.0;    // Relative Weighting
input int     InpX            = 25;     // Regression Level
input int     InpLag          = 2;      // Lag

input group "=== 🎯 ออกไม้ / SL / TP ==="
input ENUM_YY_EXIT InpExitMode = EXIT_ORIGINAL; // วิธีออกไม้
input int     InpHoldBars     = 4;      // Original: ถือกี่แท่ง
input bool    InpExitOnFlip   = true;   // Original: ออกเมื่อสัญญาณพลิกก่อนครบ
input bool    InpReverse      = true;   // มีสัญญาณฝั่งตรงข้าม → ปิดแล้วกลับฝั่ง
input ENUM_YY_SL InpSLMode    = SL_NONE;// รูปแบบ SL
input ENUM_YY_TP InpTPMode    = TP_NONE;// รูปแบบ TP
input double  InpPointSize    = 0.01;   // 1 จุด = ราคาเท่าไร (ทอง 0.01 → 500 จุด = $5)
input int     InpSLPoints     = 500;    // SL คงที่ (จุด)
input double  InpSLAtrMult    = 1.5;    // SL × ATR(14)
input int     InpSwingLen     = 10;     // Swing ย้อนหลัง (แท่ง)
input double  InpSwingBufAtr  = 0.2;    // Swing: เผื่อเลย swing (× ATR)
input int     InpMinSLPoints  = 500;    // SL ขั้นต่ำ (จุด) — ใช้เมื่อมี SL
input double  InpTP_R         = 1.0;    // TP เป็น R
input int     InpTPPoints     = 500;    // TP คงที่ (จุด)
input double  InpEmergencyAtr = 0.0;    // SL ฉุกเฉิน × ATR (0 = ปิด · ใช้ตอนไม่มี SL)

input group "=== 💰 เงิน / คำสั่ง ==="
input ENUM_YY_LOT InpLotMode  = LOT_FIXED; // ขนาดไม้
input double  InpLot          = 0.01;   // Lot คงที่
input double  InpRiskPct      = 1.0;    // Risk % ต่อไม้ (ต้องมี SL)
input double  InpMaxSpread    = 0.60;   // Spread สูงสุด (ราคา $) · เกินนี้ไม่เข้า
input long    InpMagic        = 31950;  // Magic Number
input string  InpComment      = "YY Lorentzian";

input group "=== 📊 แผง / ป้าย ==="
input bool    InpShowPanel    = true;   // แสดงแผง
input bool    InpShowSignals  = true;   // แสดงป้าย BUY / SELL บนกราฟ
input int     InpSignalsBack  = 300;    // ป้ายย้อนหลังกี่แท่ง
input int     InpPanelX       = 12;     // ตำแหน่งแผง X
input int     InpPanelY       = 28;     // ตำแหน่งแผง Y

//+------------------------------------------------------------------+
//| helpers                                                          |
//+------------------------------------------------------------------+
double gNaN;
bool   OK(double x) { return MathIsValidNumber(x); }

class CEma
  {
public:
   double a, v; bool init;
   void Set(int n) { a = 2.0 / (n + 1.0); v = 0; init = false; }
   double Upd(double x)
     {
      if(!OK(x)) { init = false; return gNaN; }
      if(!init) { v = x; init = true; } else v = a * x + (1.0 - a) * v;
      return v;
     }
  };

class CSma
  {
public:
   int n, pos, valid; double buf[];
   void Set(int len) { n = MathMax(1, len); ArrayResize(buf, n); ArrayInitialize(buf, 0); pos = 0; valid = 0; }
   double Upd(double x)
     {
      if(!OK(x)) { valid = 0; return gNaN; }
      buf[pos] = x; pos = (pos + 1) % n;
      if(valid < n) valid++;
      if(valid < n) return gNaN;
      double s = 0; for(int i = 0; i < n; i++) s += buf[i];
      return s / n;
     }
   double MeanDev(double m) { double s = 0; for(int i = 0; i < n; i++) s += MathAbs(buf[i] - m); return s / n; }
  };

class CRma
  {
public:
   double a, v; bool init; CSma sma;
   void Set(int n) { a = 1.0 / MathMax(1, n); v = 0; init = false; sma.Set(n); }
   double Upd(double x)
     {
      double s = sma.Upd(x);
      if(!OK(x)) { init = false; return gNaN; }
      if(!init) { if(!OK(s)) return gNaN; v = s; init = true; return v; }
      v = a * x + (1.0 - a) * v;
      return v;
     }
  };

class CNorm
  {
public:
   double mn, mx;
   void Reset() { mn = 10e10; mx = -10e10; }
   double Upd(double x)
     {
      if(!OK(x)) return gNaN;
      mn = MathMin(x, mn); mx = MathMax(x, mx);
      return (x - mn) / MathMax(mx - mn, 10e-10);
     }
  };

class CRsi
  {
public:
   double prev; bool has; CRma up, dn;
   void Set(int n) { has = false; up.Set(n); dn.Set(n); }
   double Upd(double x)
     {
      if(!has) { prev = x; has = true; up.Upd(gNaN); dn.Upd(gNaN); return gNaN; }
      double ch = x - prev; prev = x;
      double u = up.Upd(MathMax(ch, 0.0)), d = dn.Upd(-MathMin(ch, 0.0));
      if(!OK(u) || !OK(d)) return gNaN;
      if(d == 0) return 100.0;
      if(u == 0) return 0.0;
      return 100.0 - 100.0 / (1.0 + u / d);
     }
  };

// ADX แบบ MLExtensions (n_adx / filter_adx)
class CAdx
  {
public:
   int len; double trS, pS, nS, ph, pl, pc; bool has; CRma rma;
   void Set(int l) { len = MathMax(1, l); trS = pS = nS = 0; has = false; rma.Set(len); }
   double Upd(double h, double l, double c)
     {
      double h1 = has ? ph : 0, l1 = has ? pl : 0, c1 = has ? pc : 0;
      double tr  = MathMax(MathMax(h - l, MathAbs(h - c1)), MathAbs(l - c1));
      double dmp = (h - h1) > (l1 - l) ? MathMax(h - h1, 0.0) : 0.0;
      double dmn = (l1 - l) > (h - h1) ? MathMax(l1 - l, 0.0) : 0.0;
      trS = trS - trS / len + tr; pS = pS - pS / len + dmp; nS = nS - nS / len + dmn;
      ph = h; pl = l; pc = c; has = true;
      double dx = gNaN;
      if(trS != 0)
        {
         double dip = pS / trS * 100.0, din = nS / trS * 100.0;
         if(dip + din != 0) dx = MathAbs(dip - din) / (dip + din) * 100.0;
        }
      return rma.Upd(dx);
     }
  };

class CFeat
  {
public:
   int type, pa, pb; CRsi rsi; CEma e1, e2, e3; CSma s4, cci; CNorm nrm; CAdx adx;
   void Set(int t, int a, int b)
     {
      type = t; pa = a; pb = b; nrm.Reset();
      rsi.Set(a); e1.Set(t == F_WT ? a : b); e2.Set(a); e3.Set(b); s4.Set(4); cci.Set(a); adx.Set(a);
     }
   double Upd(double h, double l, double c)
     {
      if(type == F_RSI)
        { double r = rsi.Upd(c); double e = e1.Upd(r); return OK(e) ? e / 100.0 : gNaN; }
      if(type == F_WT)
        {
         double src = (h + l + c) / 3.0;
         double m1 = e1.Upd(src);
         double m2 = e2.Upd(OK(m1) ? MathAbs(src - m1) : gNaN);
         double ci = (OK(m1) && OK(m2) && m2 != 0) ? (src - m1) / (0.015 * m2) : gNaN;
         double w1 = e3.Upd(ci);
         double w2 = s4.Upd(w1);
         return nrm.Upd((OK(w1) && OK(w2)) ? w1 - w2 : gNaN);
        }
      if(type == F_CCI)
        {
         double m = cci.Upd(c), cc = gNaN;
         if(OK(m)) { double dv = cci.MeanDev(m); if(dv != 0) cc = (c - m) / (0.015 * dv); }
         return nrm.Upd(e1.Upd(cc));
        }
      if(type == F_ADX)
        { double ad = adx.Upd(h, l, c); return OK(ad) ? ad / 100.0 : gNaN; }
      return gNaN;
     }
  };

//+------------------------------------------------------------------+
//| state                                                            |
//+------------------------------------------------------------------+
CTrade   trade;
CFeat    gFeat[5];
CRma     gAtr1, gAtr10, gAtr14;
CEma     gRegEma, gEmaT;
CSma     gSmaT;
CAdx     gAdxF;

double   gO[], gH[], gL[], gC[], gF[], gAtrS[], gPredS[];
datetime gT[];
int      gY[], gSig[];
bool     gStartL[], gStartS[], gEndL[], gEndS[], gEmaUp[], gEmaDn[], gSmaUp[], gSmaDn[], gKUp[];
int      gN = 0;

double   gPredArr[], gDistArr[];
double   gPrediction = 0;
int      gSignal = 0, gBarsHeld = 0;
double   rV1 = 0, rV2 = 0, rPrevSrc = 0, rPrevK = 0; bool rHas = false, rKValid = false;

datetime gLastT = 0;
bool     gReady = false;
datetime gPanelT = 0;

//+------------------------------------------------------------------+
void ResetState()
  {
   gN = 0; gPrediction = 0; gSignal = 0; gBarsHeld = 0;
   ArrayResize(gPredArr, 0); ArrayResize(gDistArr, 0);
   rV1 = rV2 = rPrevSrc = rPrevK = 0; rHas = rKValid = false;
   int ft[5] = {0, 0, 0, 0, 0}; int fa[5]; int fb[5];
   ft[0] = InpF1; fa[0] = InpF1A; fb[0] = InpF1B;
   ft[1] = InpF2; fa[1] = InpF2A; fb[1] = InpF2B;
   ft[2] = InpF3; fa[2] = InpF3A; fb[2] = InpF3B;
   ft[3] = InpF4; fa[3] = InpF4A; fb[3] = InpF4B;
   ft[4] = InpF5; fa[4] = InpF5A; fb[4] = InpF5B;
   for(int k = 0; k < 5; k++) gFeat[k].Set(ft[k], fa[k], fb[k]);
   gAtr1.Set(1); gAtr10.Set(10); gAtr14.Set(14);
   gRegEma.Set(200); gEmaT.Set(InpEmaPeriod); gSmaT.Set(InpSmaPeriod); gAdxF.Set(14);
  }

void Grow(int n)
  {
   int r = 1000;
   ArrayResize(gO, n, r); ArrayResize(gH, n, r); ArrayResize(gL, n, r); ArrayResize(gC, n, r); ArrayResize(gT, n, r);
   ArrayResize(gF, n * 5, r * 5); ArrayResize(gAtrS, n, r); ArrayResize(gPredS, n, r);
   ArrayResize(gY, n, r); ArrayResize(gSig, n, r);
   ArrayResize(gStartL, n, r); ArrayResize(gStartS, n, r); ArrayResize(gEndL, n, r); ArrayResize(gEndS, n, r);
   ArrayResize(gEmaUp, n, r); ArrayResize(gEmaDn, n, r); ArrayResize(gSmaUp, n, r); ArrayResize(gSmaDn, n, r); ArrayResize(gKUp, n, r);
  }

void AppendBar(const MqlRates &b)
  {
   Grow(gN + 1);
   gO[gN] = b.open; gH[gN] = b.high; gL[gN] = b.low; gC[gN] = b.close; gT[gN] = b.time;
   gN++;
  }

double Dist(int t, int i)
  {
   double s = 0;
   int fc = MathMax(2, MathMin(5, InpFeatureCount));
   for(int k = 0; k < fc; k++)
     {
      double a = gF[t * 5 + k], b = gF[i * 5 + k];
      if(!OK(a) || !OK(b)) return gNaN;
      s += MathLog(1.0 + MathAbs(a - b));
     }
   return s;
  }

double KernelRQ(int t)
  {
   if(t < InpX + 1) return gNaN;
   double cw = 0, sw = 0;
   for(int i = 0; i <= InpX + 1; i++)
     {
      double w = MathPow(1.0 + (i * i) / (MathPow(InpH, 2) * 2.0 * InpR), -InpR);
      cw += gC[t - i] * w; sw += w;
     }
   return cw / sw;
  }

double KernelG(int t)
  {
   int hh = MathMax(1, InpH - InpLag);
   if(t < InpX + 1) return gNaN;
   double cw = 0, sw = 0;
   for(int i = 0; i <= InpX + 1; i++)
     {
      double w = MathExp(-(i * i) / (2.0 * hh * hh));
      cw += gC[t - i] * w; sw += w;
     }
   return cw / sw;
  }

//+------------------------------------------------------------------+
//| คำนวณแท่ง t (เหมือน Pine ทีละแท่ง) · lastIdx = แท่งสุดท้ายของข้อมูล  |
//+------------------------------------------------------------------+
void ProcessBar(int t, int lastIdx)
  {
   double o = gO[t], h = gH[t], l = gL[t], c = gC[t];
   for(int k = 0; k < 5; k++) gF[t * 5 + k] = gFeat[k].Upd(h, l, c);
   gY[t] = (t >= 4 && gC[t - 4] < c) ? -1 : (t >= 4 && gC[t - 4] > c) ? 1 : 0;

   // ATR / volatility filter
   double tr = (t == 0) ? h - l : MathMax(h - l, MathMax(MathAbs(h - gC[t - 1]), MathAbs(l - gC[t - 1])));
   double a1 = gAtr1.Upd(tr), a10 = gAtr10.Upd(tr);
   gAtrS[t] = gAtr14.Upd(tr);
   bool fVol = !InpUseVol || (OK(a1) && OK(a10) && a1 > a10);

   // regime filter (MLExtensions.regime_filter · src = ohlc4)
   double src4 = (o + h + l + c) / 4.0;
   double v1 = rHas ? 0.2 * (src4 - rPrevSrc) + 0.8 * rV1 : gNaN;
   double v2 = 0.1 * (h - l) + 0.8 * rV2;
   double kl = gNaN;
   if(OK(v1) && v2 != 0)
     {
      double om = MathAbs(v1 / v2);
      double al = (-MathPow(om, 2) + MathSqrt(MathPow(om, 4) + 16.0 * MathPow(om, 2))) / 8.0;
      kl = al * src4 + (1.0 - al) * (rKValid ? rPrevK : 0.0);
     }
   double slope = (OK(kl) && rKValid) ? MathAbs(kl - rPrevK) : gNaN;
   double em = gRegEma.Upd(slope);
   bool fReg = !InpUseRegime || (OK(slope) && OK(em) && em != 0 && (slope - em) / em >= InpRegimeThr);
   rV1 = OK(v1) ? v1 : 0.0; rV2 = v2; rPrevSrc = src4; rHas = true;
   if(OK(kl)) { rPrevK = kl; rKValid = true; } else rKValid = false;

   double adxv = gAdxF.Upd(h, l, c);
   bool fAdx = !InpUseAdx || (OK(adxv) && adxv > InpAdxThr);

   // ── Approximate Nearest Neighbors · Lorentzian distance
   int mbb = lastIdx >= InpMaxBarsBack ? lastIdx - InpMaxBarsBack : 0;
   if(t >= mbb)
     {
      double lastD = -1.0;
      int sizeLoop = MathMin(InpMaxBarsBack - 1, t);
      int start = InpFullHistory ? 0 : mbb;
      int step = start <= sizeLoop ? 1 : -1;
      int kk = MathMax(1, InpNeighbors);
      for(int i = start; ; i += step)
        {
         double d = Dist(t, i);
         if(OK(d) && d >= lastD && i % 4 != 0)
           {
            lastD = d;
            int n = ArraySize(gDistArr);
            ArrayResize(gDistArr, n + 1); gDistArr[n] = d;
            ArrayResize(gPredArr, n + 1); gPredArr[n] = (double)gY[i];
            if(n + 1 > kk)
              {
               lastD = gDistArr[(int)MathRound(kk * 3.0 / 4.0)];
               ArrayRemove(gDistArr, 0, 1);
               ArrayRemove(gPredArr, 0, 1);
              }
           }
         if(i == sizeLoop) break;
        }
      double s = 0; for(int j = 0; j < ArraySize(gPredArr); j++) s += gPredArr[j];
      gPrediction = s;
     }
   gPredS[t] = gPrediction;

   // ── signal
   bool filterAll = fVol && fReg && fAdx;
   if(gPrediction > 0 && filterAll) gSignal = 1;
   else if(gPrediction < 0 && filterAll) gSignal = -1;
   gSig[t] = gSignal;
   bool changed = t > 0 && gSig[t] != gSig[t - 1];
   gBarsHeld = changed ? 0 : gBarsHeld + 1;

   double e = gEmaT.Upd(c), sm = gSmaT.Upd(c);
   gEmaUp[t] = !InpUseEma || (OK(e) && c > e);
   gEmaDn[t] = !InpUseEma || (OK(e) && c < e);
   gSmaUp[t] = !InpUseSma || (OK(sm) && c > sm);
   gSmaDn[t] = !InpUseSma || (OK(sm) && c < sm);

   bool isBuy  = gSignal == 1 && gEmaUp[t] && gSmaUp[t];
   bool isSell = gSignal == -1 && gEmaDn[t] && gSmaDn[t];
   bool lastBuy  = t >= 4 && gSig[t - 4] == 1 && gEmaUp[t - 4] && gSmaUp[t - 4];
   bool lastSell = t >= 4 && gSig[t - 4] == -1 && gEmaDn[t - 4] && gSmaDn[t - 4];
   bool newBuy  = isBuy && changed;
   bool newSell = isSell && changed;

   // ── kernel regression
   double y1 = KernelRQ(t), y1p = t >= 1 ? KernelRQ(t - 1) : gNaN, y1pp = t >= 2 ? KernelRQ(t - 2) : gNaN;
   double y2 = KernelG(t);
   bool ok3 = OK(y1) && OK(y1p);
   bool isBullRate = ok3 && y1p < y1;
   bool isBearRate = ok3 && y1p > y1;
   bool isBullSmooth = OK(y2) && OK(y1) && y2 >= y1;
   bool isBearSmooth = OK(y2) && OK(y1) && y2 <= y1;
   bool isBullish = !InpUseKernel || (InpKernelSmooth ? isBullSmooth : isBullRate);
   bool isBearish = !InpUseKernel || (InpKernelSmooth ? isBearSmooth : isBearRate);
   gKUp[t] = isBullRate;

   gStartL[t] = newBuy && isBullish && gEmaUp[t] && gSmaUp[t];
   gStartS[t] = newSell && isBearish && gEmaDn[t] && gSmaDn[t];
   bool heldFour = gBarsHeld == 4, heldLess = gBarsHeld > 0 && gBarsHeld < 4;
   gEndL[t] = ((heldFour && lastBuy) || (heldLess && newSell && lastBuy)) && t >= 4 && gStartL[t - 4];
   gEndS[t] = ((heldFour && lastSell) || (heldLess && newBuy && lastSell)) && t >= 4 && gStartS[t - 4];
  }

//+------------------------------------------------------------------+
bool Build()
  {
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int n = CopyRates(_Symbol, _Period, 1, InpHistoryBars, r);
   if(n < 300) return false;
   ResetState();
   for(int t = 0; t < n; t++) AppendBar(r[t]);
   for(int t = 0; t < n; t++) ProcessBar(t, n - 1);
   gLastT = r[n - 1].time;
   if(InpShowSignals)
      for(int t = MathMax(0, n - InpSignalsBack); t < n; t++) DrawSignal(t);
   PrintFormat("YY Lorentzian: โหลด %d แท่ง · สัญญาณล่าสุด %s · prediction %.0f", n, gSignal == 1 ? "BUY" : gSignal == -1 ? "SELL" : "—", gPrediction);
   return true;
  }

//+------------------------------------------------------------------+
//| ป้าย BUY / SELL                                                    |
//+------------------------------------------------------------------+
void DrawSignal(int t)
  {
   if(!InpShowSignals || (!gStartL[t] && !gStartS[t])) return;
   string nm = "YYL_s_" + IntegerToString((long)gT[t]);
   double off = OK(gAtrS[t]) ? gAtrS[t] * 0.4 : 0;
   bool up = gStartL[t];
   ObjectCreate(0, nm, OBJ_TEXT, 0, gT[t], up ? gL[t] - off : gH[t] + off);
   ObjectSetString(0, nm, OBJPROP_TEXT, up ? "▲ BUY" : "▼ SELL");
   ObjectSetString(0, nm, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, up ? C'15,160,110' : C'210,60,60');
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, up ? ANCHOR_UPPER : ANCHOR_LOWER);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetString(0, nm, OBJPROP_TOOLTIP, StringFormat("%s · ML %.0f", up ? "BUY" : "SELL", gPredS[t]));
  }

//+------------------------------------------------------------------+
//| position helpers                                                 |
//+------------------------------------------------------------------+
ulong MyPosition(int &dir, double &price, double &vol, datetime &openT, double &profit, double &sl, double &tp)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      dir   = PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1;
      price = PositionGetDouble(POSITION_PRICE_OPEN);
      vol   = PositionGetDouble(POSITION_VOLUME);
      openT = (datetime)PositionGetInteger(POSITION_TIME);
      profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      sl = PositionGetDouble(POSITION_SL); tp = PositionGetDouble(POSITION_TP);
      return tk;
     }
   return 0;
  }

int IndexOfTime(datetime bt)
  {
   for(int i = gN - 1; i >= 0 && i >= gN - 5000; i--) if(gT[i] <= bt) return i;
   return -1;
  }

double NormLot(double lot)
  {
   double st = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN), mx = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-9) * st;
   return MathMax(mn, MathMin(mx, lot));
  }

double SLDistance(int dir, double entry, int t)
  {
   double atr = OK(gAtrS[t]) ? gAtrS[t] : 0;
   double d = 0;
   if(InpSLMode == SL_FIXED) d = InpSLPoints * InpPointSize;
   else if(InpSLMode == SL_ATR) d = InpSLAtrMult * atr;
   else if(InpSLMode == SL_SWING)
     {
      double ext = dir == 1 ? DBL_MAX : -DBL_MAX;
      for(int k = 0; k < InpSwingLen && t - k >= 0; k++)
         ext = dir == 1 ? MathMin(ext, gL[t - k]) : MathMax(ext, gH[t - k]);
      d = dir == 1 ? entry - (ext - InpSwingBufAtr * atr) : (ext + InpSwingBufAtr * atr) - entry;
     }
   if(InpSLMode != SL_NONE) d = MathMax(d, InpMinSLPoints * InpPointSize);
   else if(InpEmergencyAtr > 0) d = InpEmergencyAtr * atr;
   return MathMax(d, 0);
  }

void OpenTrade(int dir, int t)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask - bid > InpMaxSpread) { PrintFormat("YY: spread %.2f > %.2f ข้ามสัญญาณ", ask - bid, InpMaxSpread); return; }
   double entry = dir == 1 ? ask : bid;
   double sd = SLDistance(dir, entry, t);
   double td = 0;
   if(InpTPMode == TP_R && sd > 0) td = sd * InpTP_R;
   else if(InpTPMode == TP_FIXED) td = InpTPPoints * InpPointSize;
   double stops = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   if(sd > 0) sd = MathMax(sd, stops + _Point);
   if(td > 0) td = MathMax(td, stops + _Point);
   double sl = sd > 0 ? NormalizeDouble(entry - dir * sd, _Digits) : 0;
   double tp = td > 0 ? NormalizeDouble(entry + dir * td, _Digits) : 0;

   double lot = InpLot;
   if(InpLotMode == LOT_RISK && sd > 0)
     {
      double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tv > 0 && ts > 0) lot = AccountInfoDouble(ACCOUNT_EQUITY) * InpRiskPct / 100.0 / (sd / ts * tv);
     }
   lot = NormLot(lot);
   bool ok = dir == 1 ? trade.Buy(lot, _Symbol, 0, sl, tp, InpComment) : trade.Sell(lot, _Symbol, 0, sl, tp, InpComment);
   if(!ok) PrintFormat("YY: เปิดไม้ไม่สำเร็จ %d · %s", trade.ResultRetcode(), trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| ทำงานเมื่อแท่ง t ปิด                                                |
//+------------------------------------------------------------------+
void OnNewBar(int t)
  {
   DrawSignal(t);
   int dir = 0; double price = 0, vol = 0, profit = 0, sl = 0, tp = 0; datetime ot = 0;
   ulong tk = MyPosition(dir, price, vol, ot, profit, sl, tp);

   if(tk != 0)
     {
      bool closeIt = false;
      if(InpExitMode == EXIT_ORIGINAL)
        {
         int eIdx = IndexOfTime(ot);              // แท่งที่เปิดไม้
         int held = eIdx >= 0 ? t - (eIdx - 1) : 0; // นับจากแท่งสัญญาณ
         if((dir == 1 && gEndL[t]) || (dir == -1 && gEndS[t])) closeIt = true;
         if(held >= InpHoldBars) closeIt = true;
         if(InpExitOnFlip && gSig[t] != dir) closeIt = true;
        }
      if(InpReverse && ((dir == 1 && gStartS[t]) || (dir == -1 && gStartL[t]))) closeIt = true;
      if(closeIt)
        {
         if(!trade.PositionClose(tk)) PrintFormat("YY: ปิดไม้ไม่สำเร็จ %d", trade.ResultRetcode());
         else tk = 0;
        }
     }
   if(tk == 0)
     {
      if(gStartL[t]) OpenTrade(1, t);
      else if(gStartS[t]) OpenTrade(-1, t);
     }
  }

//+------------------------------------------------------------------+
//| สถิติจากประวัติ (เฉพาะ Magic นี้)                                   |
//+------------------------------------------------------------------+
void CalcStats(int &n, int &wins, double &gw, double &gl, double &net, double &today, int &todayN,
               double &month, int &monthN, double &ddPct)
  {
   n = wins = todayN = monthN = 0; gw = gl = net = today = month = ddPct = 0;
   if(!HistorySelect(0, TimeCurrent())) return;
   ulong pid[]; double pnl[]; datetime ct[]; bool closed[];
   int total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
     {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0) continue;
      if(HistoryDealGetString(d, DEAL_SYMBOL) != _Symbol) continue;
      if(HistoryDealGetInteger(d, DEAL_MAGIC) != InpMagic) continue;
      ulong p = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      double v = HistoryDealGetDouble(d, DEAL_PROFIT) + HistoryDealGetDouble(d, DEAL_COMMISSION) + HistoryDealGetDouble(d, DEAL_SWAP);
      int k = -1;
      for(int j = ArraySize(pid) - 1; j >= 0; j--) if(pid[j] == p) { k = j; break; }
      if(k < 0) { k = ArraySize(pid); ArrayResize(pid, k + 1); ArrayResize(pnl, k + 1); ArrayResize(ct, k + 1); ArrayResize(closed, k + 1); pid[k] = p; pnl[k] = 0; ct[k] = 0; closed[k] = false; }
      pnl[k] += v;
      long en = HistoryDealGetInteger(d, DEAL_ENTRY);
      if(en == DEAL_ENTRY_OUT || en == DEAL_ENTRY_OUT_BY) { closed[k] = true; ct[k] = (datetime)HistoryDealGetInteger(d, DEAL_TIME); }
     }
   MqlDateTime now; TimeToStruct(TimeCurrent(), now);
   double base = AccountInfoDouble(ACCOUNT_BALANCE);
   for(int k = 0; k < ArraySize(pid); k++) if(closed[k]) base -= pnl[k];
   double eq = base, peak = base;
   for(int k = 0; k < ArraySize(pid); k++)
     {
      if(!closed[k]) continue;
      n++; net += pnl[k];
      if(pnl[k] > 0) { wins++; gw += pnl[k]; } else gl -= pnl[k];
      eq += pnl[k]; peak = MathMax(peak, eq);
      if(peak > 0) ddPct = MathMax(ddPct, (peak - eq) / peak * 100.0);
      MqlDateTime c; TimeToStruct(ct[k], c);
      if(c.year == now.year && c.mon == now.mon) { month += pnl[k]; monthN++; if(c.day == now.day) { today += pnl[k]; todayN++; } }
     }
  }

//+------------------------------------------------------------------+
//| แผงภาษาไทยสไตล์ YY                                                 |
//+------------------------------------------------------------------+
void Lbl(string nm, int x, int y, string tx, color cl, int sz, ENUM_ANCHOR_POINT an)
  {
   if(ObjectFind(0, nm) < 0) ObjectCreate(0, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, nm, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, nm, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, nm, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, nm, OBJPROP_ANCHOR, an);
   ObjectSetString(0, nm, OBJPROP_TEXT, tx);
   ObjectSetString(0, nm, OBJPROP_FONT, "Tahoma");
   ObjectSetInteger(0, nm, OBJPROP_FONTSIZE, sz);
   ObjectSetInteger(0, nm, OBJPROP_COLOR, cl);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_HIDDEN, true);
  }

string Money(double v) { return (v >= 0 ? "+$" : "-$") + DoubleToString(MathAbs(v), 2); }
color  PnlCol(double v) { return v > 0 ? C'111,240,181' : v < 0 ? C'255,143,163' : C'230,233,242'; }

void DrawPanel()
  {
   if(!InpShowPanel) return;
   int x = InpPanelX, y = InpPanelY, w = 340, rh = 19, rows = 12;
   string bg = "YYL_bg";
   if(ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, bg, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, bg, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, bg, OBJPROP_XSIZE, w); ObjectSetInteger(0, bg, OBJPROP_YSIZE, rows * rh + 12);
   ObjectSetInteger(0, bg, OBJPROP_BGCOLOR, C'17,23,38'); ObjectSetInteger(0, bg, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, bg, OBJPROP_COLOR, C'31,40,64'); ObjectSetInteger(0, bg, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, bg, OBJPROP_HIDDEN, true);

   int dir = 0; double price = 0, vol = 0, profit = 0, sl = 0, tp = 0; datetime ot = 0;
   ulong tk = MyPosition(dir, price, vol, ot, profit, sl, tp);
   int n, wins, todayN, monthN; double gw, gl, net, today, month, dd;
   CalcStats(n, wins, gw, gl, net, today, todayN, month, monthN, dd);
   double pf = gl > 0 ? gw / gl : (gw > 0 ? 99 : 0);
   int t = gN - 1;

   color mut = C'140,150,179', txt = C'230,233,242', ac = C'245,184,65';
   string sigTx = gSignal == 1 ? "BUY ▲" : gSignal == -1 ? "SELL ▼" : "—";
   string held = "—";
   if(tk != 0) { int eIdx = IndexOfTime(ot); held = IntegerToString(eIdx >= 0 ? t - (eIdx - 1) : 0) + "/" + IntegerToString(InpHoldBars); }
   string slTx = InpSLMode == SL_NONE ? (InpEmergencyAtr > 0 ? "ฉุกเฉิน " + DoubleToString(InpEmergencyAtr, 1) + "×ATR" : "ไม่มี") :
                 InpSLMode == SL_FIXED ? IntegerToString(InpSLPoints) + " จุด" : InpSLMode == SL_ATR ? DoubleToString(InpSLAtrMult, 1) + "×ATR" : "Swing " + IntegerToString(InpSwingLen);
   string tpTx = InpTPMode == TP_NONE ? "ไม่มี" : InpTPMode == TP_R ? DoubleToString(InpTP_R, 1) + "R" : IntegerToString(InpTPPoints) + " จุด";

   string k[12], v[12]; color c[12];
   k[0] = "◆ YOUNGYUU Lorentzian EA";        v[0] = _Symbol + " · " + StringSubstr(EnumToString(_Period), 7); c[0] = ac;
   k[1] = "สัญญาณ · ML";                     v[1] = sigTx + " · " + (gPrediction >= 0 ? "+" : "") + DoubleToString(gPrediction, 0); c[1] = gSignal == 1 ? C'111,240,181' : gSignal == -1 ? C'255,143,163' : mut;
   k[2] = "Kernel";                          v[2] = t >= 0 && gKUp[t] ? "ขึ้น ▲" : "ลง ▼"; c[2] = t >= 0 && gKUp[t] ? C'111,240,181' : C'255,143,163';
   k[3] = "ไม้ปัจจุบัน";                       v[3] = tk != 0 ? (dir == 1 ? "BUY " : "SELL ") + DoubleToString(vol, 2) + " @ " + DoubleToString(price, _Digits) : "⏳ รอสัญญาณ"; c[3] = tk != 0 ? (dir == 1 ? C'111,240,181' : C'255,143,163') : mut;
   k[4] = "ลอย · แท่ง";                       v[4] = tk != 0 ? Money(profit) + " · " + held : "—"; c[4] = tk != 0 ? PnlCol(profit) : mut;
   k[5] = "SL / TP ไม้นี้";                    v[5] = tk != 0 ? (sl > 0 ? DoubleToString(sl, _Digits) : "—") + " / " + (tp > 0 ? DoubleToString(tp, _Digits) : "—") : "—"; c[5] = txt;
   k[6] = "วันนี้";                            v[6] = Money(today) + " · " + IntegerToString(todayN) + " ไม้"; c[6] = PnlCol(today);
   k[7] = "เดือนนี้";                          v[7] = Money(month) + " · " + IntegerToString(monthN) + " ไม้"; c[7] = PnlCol(month);
   k[8] = "ทั้งหมด · ชนะ";                     v[8] = IntegerToString(n) + " ไม้ · " + (n > 0 ? DoubleToString(100.0 * wins / n, 1) : "0") + "%"; c[8] = ac;
   k[9] = "กำไร · PF · DD";                   v[9] = Money(net) + " · " + DoubleToString(pf, 2) + " · -" + DoubleToString(dd, 1) + "%"; c[9] = PnlCol(net);
   k[10] = "ออกไม้";                          v[10] = InpExitMode == EXIT_ORIGINAL ? "Original " + IntegerToString(InpHoldBars) + " แท่ง" : "SL / TP"; c[10] = txt;
   k[11] = "SL · TP";                        v[11] = slTx + " · " + tpTx; c[11] = txt;

   for(int i = 0; i < 12; i++)
     {
      Lbl("YYL_k" + IntegerToString(i), x + 10, y + 6 + i * rh, k[i], i == 0 ? ac : mut, i == 0 ? 10 : 9, ANCHOR_LEFT_UPPER);
      Lbl("YYL_v" + IntegerToString(i), x + w - 10, y + 6 + i * rh, v[i], c[i], i == 0 ? 10 : 9, ANCHOR_RIGHT_UPPER);
     }
   Lbl("YYL_ft", x + 10, y + 8 + rows * rh, "ML core: jdehorty · MPL-2.0", C'90,98,122', 7, ANCHOR_LEFT_UPPER);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   gNaN = MathSqrt(-1.0);
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetDeviationInPoints(50);
   if(InpFeatureCount < 2 || InpFeatureCount > 5) { Print("Feature Count ต้องอยู่ระหว่าง 2-5"); return INIT_PARAMETERS_INCORRECT; }
   if(InpLotMode == LOT_RISK && InpSLMode == SL_NONE && InpEmergencyAtr <= 0)
      Print("YY: Risk % ต้องมี SL → จะใช้ Lot คงที่แทน");
   gReady = false;
   EventSetTimer(1);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ObjectsDeleteAll(0, "YYL_");
  }

void OnTimer()
  {
   if(!gReady) { gReady = Build(); if(gReady) DrawPanel(); return; }
   DrawPanel();
  }

void OnTick()
  {
   if(!gReady) { gReady = Build(); if(!gReady) return; }
   datetime t1 = iTime(_Symbol, _Period, 1);
   if(t1 == 0 || t1 == gLastT) return;
   int shift = iBarShift(_Symbol, _Period, gLastT, true);
   if(shift < 1) { gReady = Build(); return; }          // ข้อมูลขาดช่วง → คำนวณใหม่ทั้งหมด
   int cnt = shift - 1;                                 // แท่งที่ปิดใหม่ตั้งแต่รอบก่อน
   if(cnt <= 0) { gLastT = t1; return; }
   MqlRates r[];
   ArraySetAsSeries(r, false);
   int got = CopyRates(_Symbol, _Period, 1, cnt, r);
   if(got != cnt) return;
   for(int i = 0; i < got; i++)
     {
      AppendBar(r[i]);
      ProcessBar(gN - 1, gN - 1);
      if(i < got - 1) DrawSignal(gN - 1);
     }
   gLastT = t1;
   OnNewBar(gN - 1);
   DrawPanel();
  }
//+------------------------------------------------------------------+
