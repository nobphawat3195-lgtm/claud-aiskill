//+------------------------------------------------------------------+
//| YY_Signal_LiqSweep.mqh — Liquidity Sweep + MSS                   |
//| Port จาก TradingView/YOUNGYUU_Liquidity_Sweep.pine v1.1           |
//|                                                                  |
//| Bias : โครงสร้าง HTF (H4 / H4+D / ไม่กรอง) ของแท่ง HTF ที่ปิดแล้ว     |
//| Sweep: ไส้กวาด swing low / PDL แล้วปิดกลับเหนือระดับ (BUY)          |
//| MSS  : ภายใน N แท่ง ปิดทะลุ swing high ย่อยล่าสุด → สัญญาณ BUY      |
//| SELL กลับด้านทั้งหมด                                              |
//| คำนวณเฉพาะแท่งที่ปิดแล้ว (shift >= 1) → ไม่ repaint                  |
//|                                                                  |
//| ต่างจาก Pine: pivot ใช้ ซ้าย > และขวา >=, HTF dir ย้อน 300 แท่ง       |
//+------------------------------------------------------------------+
#ifndef YY_SIGNAL_LIQSWEEP_MQH
#define YY_SIGNAL_LIQSWEEP_MQH

enum ENUM_YY_BIAS_MODE
{
   YY_BIAS_HTF_A  = 0,   // TF โครงสร้าง 1 อย่างเดียว (H4)
   YY_BIAS_HTF_AB = 1,   // TF 1 + TF 2 ตรงกัน (H4 + D1)
   YY_BIAS_NONE   = 2    // ไม่กรอง
};

class CYYLiqSweep
{
public:
   // ตัวนับ debug (ดูว่าสัญญาณหายไปขั้นไหน)
   int    cntSweep, cntBias, cntMss, cntExpire;
   int    lastBias;
   double lastSweepX;

private:
   string            m_sym;
   ENUM_TIMEFRAMES   m_tf;
   ENUM_TIMEFRAMES   m_htfA, m_htfB;
   ENUM_YY_BIAS_MODE m_biasMode;
   int               m_swLen, m_mssLen, m_wait;
   bool              m_usePD;

   // liquidity / swing ย่อย
   bool   m_hasLiqH, m_hasLiqL, m_hasMinH, m_hasMinL;
   double m_liqH, m_liqL, m_minH, m_minL;

   // state machine
   int    m_state;       // 1 = กวาดล่าง รอ MSS ขึ้น · -1 = กวาดบน รอ MSS ลง
   double m_swX;         // ไส้สุดของการกวาด
   long   m_swBar;
   double m_mssLv;
   long   m_barCount;

   // cache HTF dir
   datetime m_cacheKeyA, m_cacheKeyB;
   int      m_cacheDirA, m_cacheDirB;

   //--- pivot high/low ของ TF กราฟ ยืนยันที่แท่ง s (กลาง = s+len)
   bool PivotHigh(const int s, const int len, double &val)
   {
      int c = s + len;
      if(c + len >= Bars(m_sym, m_tf)) return false;
      double h = iHigh(m_sym, m_tf, c);
      for(int i = 1; i <= len; i++)
      {
         if(!(h >  iHigh(m_sym, m_tf, c + i))) return false;   // ซ้าย (เก่ากว่า)
         if(!(h >= iHigh(m_sym, m_tf, c - i))) return false;   // ขวา (ใหม่กว่า)
      }
      val = h;
      return true;
   }

   bool PivotLow(const int s, const int len, double &val)
   {
      int c = s + len;
      if(c + len >= Bars(m_sym, m_tf)) return false;
      double l = iLow(m_sym, m_tf, c);
      for(int i = 1; i <= len; i++)
      {
         if(!(l <  iLow(m_sym, m_tf, c + i))) return false;
         if(!(l <= iLow(m_sym, m_tf, c - i))) return false;
      }
      val = l;
      return true;
   }

   //--- ทิศโครงสร้าง HTF (lStruct(3)) ณ แท่ง HTF ที่ปิดก่อนแท่ง HTF ที่ครอบ barTime
   int HtfDirAt(const ENUM_TIMEFRAMES tf, const datetime barTime, datetime &cacheKey, int &cacheDir)
   {
      int hs = iBarShift(m_sym, tf, barTime, false);
      if(hs < 0) return 0;
      datetime key = iTime(m_sym, tf, hs);
      if(key == cacheKey && key != 0) return cacheDir;

      MqlRates r[];
      int n = CopyRates(m_sym, tf, hs + 1, 300, r);   // r[0] = เก่าสุด
      if(n < 10) return 0;                             // ข้อมูลยังไม่พร้อม: ไม่ cache

      const int len = 3;
      bool hasH = false, hasL = false;
      double lastH = 0.0, lastL = 0.0;
      int dir = 0;
      for(int i = 0; i < n; i++)
      {
         int c = i - len;
         if(c - len >= 0)
         {
            bool ph = true, pl = true;
            for(int j = 1; j <= len; j++)
            {
               if(!(r[c].high >  r[c - j].high) || !(r[c].high >= r[c + j].high)) ph = false;
               if(!(r[c].low  <  r[c - j].low)  || !(r[c].low  <= r[c + j].low))  pl = false;
            }
            if(ph) { lastH = r[c].high; hasH = true; }
            if(pl) { lastL = r[c].low;  hasL = true; }
         }
         if(hasH && r[i].close > lastH)      dir = 1;
         else if(hasL && r[i].close < lastL) dir = -1;
      }
      cacheKey = key;
      cacheDir = dir;
      return dir;
   }

   int BiasAt(const datetime barTime)
   {
      if(m_biasMode == YY_BIAS_NONE) return 2;
      int a = HtfDirAt(m_htfA, barTime, m_cacheKeyA, m_cacheDirA);
      if(m_biasMode == YY_BIAS_HTF_A) return a;
      int b = HtfDirAt(m_htfB, barTime, m_cacheKeyB, m_cacheDirB);
      return (a != 0 && a == b) ? a : 0;
   }

   //--- ประมวลผลแท่งที่ปิดแล้ว shift s คืนค่า 1 = BUY, -1 = SELL, 0 = ไม่มี
   int ProcessBar(const int s)
   {
      m_barCount++;
      double v;
      if(PivotHigh(s, m_swLen,  v)) { m_liqH = v; m_hasLiqH = true; }
      if(PivotLow (s, m_swLen,  v)) { m_liqL = v; m_hasLiqL = true; }
      if(PivotHigh(s, m_mssLen, v)) { m_minH = v; m_hasMinH = true; }
      if(PivotLow (s, m_mssLen, v)) { m_minL = v; m_hasMinL = true; }

      double hi = iHigh (m_sym, m_tf, s);
      double lo = iLow  (m_sym, m_tf, s);
      double cl = iClose(m_sym, m_tf, s);
      datetime t = iTime(m_sym, m_tf, s);

      // PDH / PDL ของวันก่อนหน้าแท่งนี้
      double pdh = 0.0, pdl = 0.0;
      if(m_usePD)
      {
         int ds = iBarShift(m_sym, PERIOD_D1, t, false);
         if(ds >= 0)
         {
            pdh = iHigh(m_sym, PERIOD_D1, ds + 1);
            pdl = iLow (m_sym, PERIOD_D1, ds + 1);
         }
      }

      bool swBull = (m_hasLiqL && lo < m_liqL && cl > m_liqL) ||
                    (m_usePD && pdl > 0.0 && lo < pdl && cl > pdl);
      bool swBear = (m_hasLiqH && hi > m_liqH && cl < m_liqH) ||
                    (m_usePD && pdh > 0.0 && hi > pdh && cl < pdh);

      int bias = BiasAt(t);
      lastBias = bias;

      // highest/lowest 5 แท่ง (รวมแท่งนี้)
      int ih = iHighest(m_sym, m_tf, MODE_HIGH, 5, s);
      int il = iLowest (m_sym, m_tf, MODE_LOW,  5, s);
      double hi5 = (ih >= 0) ? iHigh(m_sym, m_tf, ih) : hi;
      double lo5 = (il >= 0) ? iLow (m_sym, m_tf, il) : lo;

      int sig = 0;
      if(swBull || swBear) cntSweep++;

      if(swBull && (bias == 1 || bias == 2))
      {
         cntBias++;
         m_state = 1;  m_swX = lo;  m_swBar = m_barCount;
         m_mssLv = (m_hasMinH && m_minH > cl) ? m_minH : hi5;
      }
      else if(swBear && (bias == -1 || bias == 2))
      {
         cntBias++;
         m_state = -1; m_swX = hi;  m_swBar = m_barCount;
         m_mssLv = (m_hasMinL && m_minL < cl) ? m_minL : lo5;
      }
      else if(m_state != 0)
      {
         m_swX = (m_state == 1) ? MathMin(m_swX, lo) : MathMax(m_swX, hi);
         bool mss = (m_state == 1) ? (cl > m_mssLv) : (cl < m_mssLv);
         if(mss)
         {
            cntMss++;
            sig = m_state;
            lastSweepX = m_swX;
            m_state = 0;
         }
         else if(m_barCount - m_swBar > m_wait || (m_state == 1 ? bias == -1 : bias == 1))
         {
            cntExpire++;
            m_state = 0;
         }
      }
      return sig;
   }

public:
   void Init(const string sym, const ENUM_TIMEFRAMES tf, const ENUM_YY_BIAS_MODE biasMode,
             const ENUM_TIMEFRAMES htfA, const ENUM_TIMEFRAMES htfB,
             const int swLen, const int mssLen, const int wait, const bool usePD)
   {
      m_sym = sym; m_tf = tf; m_biasMode = biasMode; m_htfA = htfA; m_htfB = htfB;
      m_swLen = MathMax(2, swLen); m_mssLen = MathMax(1, mssLen); m_wait = MathMax(1, wait);
      m_usePD = usePD;
      Reset();
   }

   void Reset()
   {
      m_hasLiqH = m_hasLiqL = m_hasMinH = m_hasMinL = false;
      m_liqH = m_liqL = m_minH = m_minL = 0.0;
      m_state = 0; m_swX = 0.0; m_swBar = 0; m_mssLv = 0.0; m_barCount = 0;
      m_cacheKeyA = m_cacheKeyB = 0; m_cacheDirA = m_cacheDirB = 0;
      cntSweep = cntBias = cntMss = cntExpire = 0;
      lastBias = 0; lastSweepX = 0.0;
   }

   //--- สร้าง state จากประวัติ (ไม่ส่งสัญญาณ) แล้วรีเซ็ตตัวนับ
   void Warmup(const int bars)
   {
      int avail = Bars(m_sym, m_tf) - 2 * m_swLen - 2;
      int from  = MathMin(bars, avail);
      for(int s = from; s >= 1; s--) ProcessBar(s);
      cntSweep = cntBias = cntMss = cntExpire = 0;
   }

   //--- เรียกเมื่อขึ้นแท่งใหม่ ประมวลผลแท่งที่เพิ่งปิด (shift 1)
   int OnNewBar() { return ProcessBar(1); }

   int State() const { return m_state; }
};

#endif
