//+------------------------------------------------------------------+
//| YY_RiskBudget.mqh — คำนวณตาราง grid ให้พอดีกับงบ DD               |
//|                                                                  |
//| ก่อนเปิดชุดใหม่ หา "จำนวนชั้น × ตัวคูณ lot" ที่ดีที่สุด ซึ่ง         |
//|  1) ขาดทุนแย่สุด (ราคาสวนครบทุกชั้น + extra) ไม่เกินงบ              |
//|  2) margin level ณ จุดแย่สุด ไม่ต่ำกว่าที่กำหนด                     |
//| ลำดับความสำคัญ: จำนวนชั้นมาก่อน (รอดได้ไกลกว่า) แล้วค่อยตัวคูณสูงสุด  |
//+------------------------------------------------------------------+
#ifndef YY_RISK_BUDGET_MQH
#define YY_RISK_BUDGET_MQH

#include "YY_TradeUtils.mqh"

#define YY_MAX_LAYERS 20

struct SYYGridPlan
{
   bool   ok;
   int    layers;
   double mult;
   double baseLot;
   double spacing;      // ระยะห่างแต่ละชั้น (ราคา)
   double worstLoss;    // ขาดทุนแย่สุดของทั้งชุด (เงิน)
   double room;         // งบที่ใช้ได้ตอนวางแผน (เงิน)
   double marginNeed;   // margin รวมเมื่อเปิดครบทุกชั้น
   double totalLots;
   double lots[YY_MAX_LAYERS];
};

class CYYRiskBudget
{
public:
   double ddCap;            // 0.70 = เพดาน DD 70% จาก peak equity
   double budgetUse;        // ใช้งบจริงกี่ส่วนของห้องที่เหลือ (กันไว้สำหรับ slippage)
   int    maxLayers;
   int    minLayers;
   double maxMult;
   double multStep;
   double equityPerBase;    // ทุกๆ $X ของ equity = base lot เพิ่ม 1 หน่วย lot ขั้นต่ำ
   double extraSpacings;    // ทดสอบแย่สุดเลยชั้นสุดท้ายไปอีกกี่ช่วง
   double minMarginLevel;   // % ขั้นต่ำ ณ จุดแย่สุด

   CYYRiskBudget()
   {
      ddCap = 0.70; budgetUse = 0.90; maxLayers = 6; minLayers = 2;
      maxMult = 1.5; multStep = 0.1; equityPerBase = 200.0;
      extraSpacings = 1.0; minMarginLevel = 150.0;
   }

   //--- ขาดทุนแย่สุดของตาราง lot ที่กำหนด เมื่อราคาสวนไปถึง (n-1+extra) ช่วง
   double WorstLoss(const double &lots[], const int n, const double spacing,
                    const double spreadPrice, const double vpp)
   {
      double dist = (n - 1 + extraSpacings) * spacing;
      double loss = 0.0;
      for(int k = 0; k < n; k++)
         loss += lots[k] * (dist - k * spacing + spreadPrice) * vpp;
      return loss;
   }

   bool Build(const string sym, const ENUM_ORDER_TYPE type, const double spacing,
              const double peakEquity, SYYGridPlan &plan, string &reason)
   {
      plan.ok = false;
      reason  = "";
      if(spacing <= 0.0) { reason = "ATR ยังไม่พร้อม"; return false; }

      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double stopLevel = peakEquity * (1.0 - ddCap);
      double room      = (equity - stopLevel) * budgetUse;
      if(room <= 0.0) { reason = "equity ใกล้เพดาน DD แล้ว"; return false; }

      double vpp = YY_ValuePerPricePerLot(sym);
      if(vpp <= 0.0) { reason = "อ่าน tick value ไม่ได้"; return false; }

      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double spreadPrice = ask - bid;
      double price = (type == ORDER_TYPE_BUY) ? ask : bid;

      double vmin  = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double units = MathMax(1.0, MathFloor(equity / MathMax(equityPerBase, 1.0)));
      double base  = YY_NormalizeLot(sym, vmin * units);

      int nMax = MathMin(maxLayers, YY_MAX_LAYERS);
      int nMin = MathMax(1, minLayers);
      int mSteps = (multStep > 0.0) ? (int)MathRound((maxMult - 1.0) / multStep) : 0;
      if(mSteps < 0) mSteps = 0;

      double lots[YY_MAX_LAYERS];
      for(int n = nMax; n >= nMin; n--)
      {
         for(int s = mSteps; s >= 0; s--)
         {
            double m = 1.0 + s * multStep;
            double total = 0.0;
            for(int k = 0; k < n; k++)
            {
               double lot = YY_NormalizeLot(sym, base * MathPow(m, k));
               if(lot < base) lot = base;
               lots[k] = lot;
               total  += lot;
            }
            double loss = WorstLoss(lots, n, spacing, spreadPrice, vpp);
            if(loss > room) continue;

            double margin = 0.0;
            if(!OrderCalcMargin(type, sym, total, price, margin)) continue;
            if(margin > 0.0 && (equity - loss) / margin * 100.0 < minMarginLevel) continue;

            plan.ok         = true;
            plan.layers     = n;
            plan.mult       = m;
            plan.baseLot    = base;
            plan.spacing    = spacing;
            plan.worstLoss  = loss;
            plan.room       = room;
            plan.marginNeed = margin;
            plan.totalLots  = total;
            for(int k = 0; k < YY_MAX_LAYERS; k++) plan.lots[k] = (k < n) ? lots[k] : 0.0;
            return true;
         }
      }
      reason = StringFormat("งบไม่พอ: ห้อง $%.2f แต่ grid เล็กสุด (%d ชั้น) ต้องใช้มากกว่านั้น", room, nMin);
      return false;
   }
};

#endif
