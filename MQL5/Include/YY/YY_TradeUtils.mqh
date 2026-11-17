//+------------------------------------------------------------------+
//| YY_TradeUtils.mqh — ตัวช่วยส่งคำสั่ง / normalize lot / มูลค่าต่อราคา |
//| ใช้ร่วมกันได้ทุก EA ตระกูล YY                                      |
//+------------------------------------------------------------------+
#ifndef YY_TRADE_UTILS_MQH
#define YY_TRADE_UTILS_MQH

#include <Trade/Trade.mqh>

//--- ปัด lot ลงตาม step ของโบรก และบังคับอยู่ในช่วง min..max
double YY_NormalizeLot(const string sym, double lots)
{
   double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   double vmin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < vmin) lots = vmin;
   if(lots > vmax) lots = vmax;
   int digits = (int)MathMax(0.0, MathCeil(-MathLog10(step) - 1e-9));
   return NormalizeDouble(lots, digits);
}

//--- มูลค่าเงิน (สกุลบัญชี) เมื่อราคาเปลี่ยน 1.0 ต่อ 1 lot
//    XAUUSD contract 100 oz → ประมาณ 100 USD ต่อราคา 1.0 ต่อ lot
double YY_ValuePerPricePerLot(const string sym)
{
   double tv = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double ts = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   if(ts <= 0.0) return 0.0;
   return tv / ts;
}

bool YY_IsDone(const uint rc)
{
   return (rc == TRADE_RETCODE_DONE || rc == TRADE_RETCODE_DONE_PARTIAL || rc == TRADE_RETCODE_PLACED);
}

bool YY_IsRetryable(const uint rc)
{
   return (rc == TRADE_RETCODE_REQUOTE || rc == TRADE_RETCODE_PRICE_CHANGED ||
           rc == TRADE_RETCODE_PRICE_OFF || rc == TRADE_RETCODE_TIMEOUT ||
           rc == TRADE_RETCODE_CONNECTION);
}

//+------------------------------------------------------------------+
//| CTrade wrapper: ตรวจ retcode ทุกครั้ง + retry เมื่อราคาเปลี่ยน      |
//+------------------------------------------------------------------+
class CYYTrade
{
private:
   CTrade m_trade;
   string m_sym;
   ulong  m_magic;

public:
   void Init(const string sym, const ulong magic, const uint deviationPts)
   {
      m_sym   = sym;
      m_magic = magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(deviationPts);
      m_trade.SetTypeFillingBySymbol(sym);
      m_trade.SetMarginMode();
      m_trade.LogLevel(LOG_LEVEL_ERRORS);
   }

   bool Open(const ENUM_ORDER_TYPE type, const double lots, const string comment)
   {
      for(int attempt = 1; attempt <= 3; attempt++)
      {
         double price = (type == ORDER_TYPE_BUY) ? SymbolInfoDouble(m_sym, SYMBOL_ASK)
                                                 : SymbolInfoDouble(m_sym, SYMBOL_BID);
         m_trade.PositionOpen(m_sym, type, lots, price, 0.0, 0.0, comment);
         uint rc = m_trade.ResultRetcode();
         if(YY_IsDone(rc)) return true;
         PrintFormat("[YY] เปิดไม้ไม่สำเร็จ %s %.2f lot rc=%u (%s) ครั้งที่ %d",
                     (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lots, rc,
                     m_trade.ResultRetcodeDescription(), attempt);
         if(!YY_IsRetryable(rc)) return false;
         Sleep(200);
      }
      return false;
   }

   //--- ปิดทุก position ของ symbol+magic นี้ คืนค่าจำนวนที่ปิดไม่สำเร็จ
   int CloseAll()
   {
      int failed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_sym) continue;
         if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;

         bool ok = false;
         for(int attempt = 1; attempt <= 3 && !ok; attempt++)
         {
            m_trade.PositionClose(ticket);
            uint rc = m_trade.ResultRetcode();
            ok = YY_IsDone(rc);
            if(!ok)
            {
               PrintFormat("[YY] ปิดไม้ #%I64u ไม่สำเร็จ rc=%u (%s) ครั้งที่ %d",
                           ticket, rc, m_trade.ResultRetcodeDescription(), attempt);
               if(!YY_IsRetryable(rc)) break;
               Sleep(200);
            }
         }
         if(!ok) failed++;
      }
      return failed;
   }
};

#endif
