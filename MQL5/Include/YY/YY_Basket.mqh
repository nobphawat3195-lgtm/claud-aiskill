//+------------------------------------------------------------------+
//| YY_Basket.mqh — อ่านสถานะชุด grid จาก position ที่เปิดอยู่          |
//|                                                                  |
//| เก็บพารามิเตอร์ชุดไว้ใน comment ของไม้ชั้น 1 เพื่อให้ restart แล้วกู้คืนได้ |
//| รูปแบบ: GH|L1|S450|N5|M120|T200                                   |
//|   L = ชั้น, S = ระยะห่าง (points), N = ชั้นสูงสุด,                    |
//|   M = ตัวคูณ ×100, T = เป้ากำไรชุด (cent)                          |
//+------------------------------------------------------------------+
#ifndef YY_BASKET_MQH
#define YY_BASKET_MQH

#include "YY_TradeUtils.mqh"

class CYYBasket
{
private:
   string m_sym;
   ulong  m_magic;

   static int TagInt(const string &parts[], const string prefix, const int def)
   {
      for(int i = 0; i < ArraySize(parts); i++)
         if(StringFind(parts[i], prefix) == 0)
            return (int)StringToInteger(StringSubstr(parts[i], StringLen(prefix)));
      return def;
   }

public:
   // สถานะปัจจุบัน (อัปเดตทุกครั้งที่เรียก Scan)
   int    dir;          // 1 = BUY, -1 = SELL, 0 = ไม่มีชุด
   int    count;        // จำนวนไม้ที่เปิดอยู่
   int    topLayer;     // เลขชั้นสูงสุดที่เปิดแล้ว
   double totalLots;
   double profit;       // profit + swap (ยังไม่หัก commission)
   double lastPrice;    // ราคาเปิดของชั้นล่าสุด (ไม้ที่เปิดหลังสุด)
   bool   mixedDir;     // มีไม้สองทิศปนกัน (ไม่ควรเกิด)

   // พารามิเตอร์ชุด (จาก comment ของชั้น 1)
   bool   paramsOk;
   int    spacingPts;
   int    layers;
   double mult;
   double target;       // เงิน
   double baseLot;

   void Init(const string sym, const ulong magic) { m_sym = sym; m_magic = magic; }

   static string MakeComment(const int layer, const int spacingPts, const int layers,
                             const double mult, const double target)
   {
      return StringFormat("GH|L%d|S%d|N%d|M%d|T%d", layer, spacingPts, layers,
                          (int)MathRound(mult * 100.0), (int)MathRound(target * 100.0));
   }

   void Scan()
   {
      dir = 0; count = 0; topLayer = 0; totalLots = 0.0; profit = 0.0;
      lastPrice = 0.0; mixedDir = false; paramsOk = false;
      long  lastMsc    = 0;
      ulong lastTicket = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;

         int d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         if(dir == 0) dir = d; else if(d != dir) mixedDir = true;

         count++;
         totalLots += PositionGetDouble(POSITION_VOLUME);
         profit    += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

         long tmsc = PositionGetInteger(POSITION_TIME_MSC);
         if(lastTicket == 0 || tmsc > lastMsc || (tmsc == lastMsc && ticket > lastTicket))
         {
            lastMsc    = tmsc;
            lastTicket = ticket;
            lastPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
         }

         string parts[];
         StringSplit(PositionGetString(POSITION_COMMENT), '|', parts);
         int layer = TagInt(parts, "L", 0);
         if(layer > topLayer) topLayer = layer;
         if(layer == 1 && ArraySize(parts) >= 6 && parts[0] == "GH")
         {
            spacingPts = TagInt(parts, "S", 0);
            layers     = TagInt(parts, "N", 0);
            mult       = TagInt(parts, "M", 100) / 100.0;
            target     = TagInt(parts, "T", 0) / 100.0;
            baseLot    = PositionGetDouble(POSITION_VOLUME);
            paramsOk   = (spacingPts > 0 && layers > 0 && target > 0.0);
         }
      }
      if(topLayer < count) topLayer = count;   // comment ถูกโบรกแก้: นับตามจำนวนไม้
   }

   //--- lot ของชั้น k (1-based) ตามสูตรเดียวกับ CYYRiskBudget
   double LotForLayer(const int k)
   {
      double lot = YY_NormalizeLot(m_sym, baseLot * MathPow(mult, k - 1));
      return (lot < baseLot) ? baseLot : lot;
   }
};

#endif
