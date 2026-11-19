//+------------------------------------------------------------------+
//|  XAU_SessionStats.mq5 — สถิติรายเซสชันของ XAUUSD จากข้อมูล M5       |
//|  ใช้ตั้งค่าเริ่มต้นของ EA หลายเซสชัน (Asia / London / NY / NY-PM)    |
//|                                                                  |
//|  วัด 4 อย่าง (เวลาทั้งหมดเป็น UTC, หน้าต่าง London/NY เลื่อนตาม DST):|
//|   1) range เฉลี่ยรายชั่วโมง เป็นสัดส่วนของ ADR                      |
//|   2) ความกว้างกรอบเอเชีย (00:00-06:00) ต่อ ADR                     |
//|   3) London: M5 ปิดนอกกรอบเอเชีย แล้ว "ไปต่อ 1R" หรือ "กลับถึงกลาง  |
//|      กรอบ" ก่อน และ wick sweep ที่กลับถึงกลางกรอบ                  |
//|   4) หลัง 16:00: วัน trend ไปต่อหรือไม่, วัน range หลุดกรอบวันไหม   |
//|                                                                  |
//|  ผลลัพธ์: แท็บ Experts + ไฟล์ CSV ใน MQL5/Files                     |
//+------------------------------------------------------------------+
#property script_show_inputs
#property strict

enum ENUM_DST_MODE { DST_NONE, DST_US, DST_EU };

input int           InpDays            = 250;      // จำนวนวันย้อนหลัง
input int           InpServerGMTWinter = 2;        // GMT offset ของเซิร์ฟเวอร์ช่วงฤดูหนาว
input ENUM_DST_MODE InpServerDST       = DST_US;   // กฎ DST ของเซิร์ฟเวอร์
input int           InpADRPeriod       = 14;       // จำนวนวันเฉลี่ย ADR
input string        InpOutFile         = "xau_session_stats.csv";

//--- แท่ง M5 ของวันที่กำลังประมวลผล (นาทีของวันแบบ UTC)
int    gMin[];
double gO[], gH[], gL[], gC[];
int    gN = 0;

//--- ตัวนับรวม
double gDayRanges[];             // range รายวันย้อนหลัง ใช้คำนวณ ADR
int    gDays = 0;
double gHourSum[24];  int gHourCnt[24];
double gAsiaSum = 0;
// bucket ความกว้างกรอบเอเชีย: 0 = <0.15 ADR, 1 = 0.15-0.45, 2 = >0.45
int    gBoxDays[3], gBO[3], gBOCont[3], gBOFail[3];
int    gSweep[3], gSweepWin[3];
int    gTrendDays = 0, gTrendCont = 0, gTrendNewExt = 0;
double gTrendMove = 0;
int    gRangeDays = 0, gRangeBreak = 0;
double gRangePM = 0;

//+------------------------------------------------------------------+
datetime NthSunday(int year, int mon, int n)   // n>0 = อาทิตย์ที่ n, n=0 = อาทิตย์สุดท้าย
{
   MqlDateTime d;
   if(n > 0)
   {
      datetime first = StringToTime(StringFormat("%04d.%02d.01", year, mon));
      TimeToStruct(first, d);
      return first + ((7 - d.day_of_week) % 7 + 7 * (n - 1)) * 86400;
   }
   int ny = year, nm = mon + 1;
   if(nm > 12) { nm = 1; ny++; }
   datetime last = StringToTime(StringFormat("%04d.%02d.01", ny, nm)) - 86400;
   TimeToStruct(last, d);
   return last - d.day_of_week * 86400;
}
bool IsUSDST(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   return t >= NthSunday(d.year, 3, 2) && t < NthSunday(d.year, 11, 1);
}
bool IsEUDST(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   return t >= NthSunday(d.year, 3, 0) && t < NthSunday(d.year, 10, 0);
}
datetime ServerToUTC(datetime t)
{
   int off = InpServerGMTWinter;
   if(InpServerDST == DST_US && IsUSDST(t)) off++;
   if(InpServerDST == DST_EU && IsEUDST(t)) off++;
   return t - off * 3600;
}

//+------------------------------------------------------------------+
void ProcessDay(datetime utcDay)
{
   if(gN < 200) return;                        // วันหยุด / ข้อมูลไม่ครบ

   double dHi = gH[0], dLo = gL[0];
   for(int i = 1; i < gN; i++) { dHi = MathMax(dHi, gH[i]); dLo = MathMin(dLo, gL[i]); }

   //--- ADR จากวันก่อนหน้า (ไม่รวมวันนี้ กัน look-ahead)
   int nR = ArraySize(gDayRanges);
   double adr = 0;
   if(nR >= InpADRPeriod)
   {
      for(int i = nR - InpADRPeriod; i < nR; i++) adr += gDayRanges[i];
      adr /= InpADRPeriod;
   }
   ArrayResize(gDayRanges, nR + 1);
   gDayRanges[nR] = dHi - dLo;
   if(adr <= 0) return;
   gDays++;

   //--- 1) range รายชั่วโมง
   double hHi[24], hLo[24]; bool hHas[24];
   ArrayInitialize(hHas, false);
   for(int i = 0; i < gN; i++)
   {
      int h = gMin[i] / 60;
      if(!hHas[h]) { hHi[h] = gH[i]; hLo[h] = gL[i]; hHas[h] = true; }
      else         { hHi[h] = MathMax(hHi[h], gH[i]); hLo[h] = MathMin(hLo[h], gL[i]); }
   }
   for(int h = 0; h < 24; h++)
      if(hHas[h]) { gHourSum[h] += (hHi[h] - hLo[h]) / adr; gHourCnt[h]++; }

   //--- 2) กรอบเอเชีย 00:00-06:00 UTC
   double aHi = 0, aLo = 0; bool aHas = false;
   for(int i = 0; i < gN && gMin[i] < 360; i++)
   {
      if(!aHas) { aHi = gH[i]; aLo = gL[i]; aHas = true; }
      else      { aHi = MathMax(aHi, gH[i]); aLo = MathMin(aLo, gL[i]); }
   }
   if(aHas && aHi > aLo)
   {
      double ratio = (aHi - aLo) / adr;
      gAsiaSum += ratio;
      int b = (ratio < 0.15) ? 0 : (ratio <= 0.45 ? 1 : 2);
      gBoxDays[b]++;

      //--- 3) London: หน้าต่างเข้า 3.5 ชม. ติดตามผลต่ออีก 2 ชม.
      int lonStart = 420 - (IsEUDST(utcDay) ? 60 : 0);
      int lonEnd   = lonStart + 210;
      int outEnd   = lonEnd + 120;
      double mid   = (aHi + aLo) / 2.0;

      // 3a) breakout: M5 แรกที่ปิดนอกกรอบ → ถึง +1R (R = ระยะถึงกลางกรอบ) หรือกลับถึงกลางกรอบก่อน
      int dir = 0; double target = 0;
      for(int i = 0; i < gN; i++)
      {
         if(gMin[i] < lonStart) continue;
         if(gMin[i] >= outEnd) break;
         if(dir == 0)
         {
            if(gMin[i] >= lonEnd) break;
            if(gC[i] > aHi)      { dir =  1; target = gC[i] + (gC[i] - mid); gBO[b]++; }
            else if(gC[i] < aLo) { dir = -1; target = gC[i] - (mid - gC[i]); gBO[b]++; }
            continue;
         }
         // เช็กฝั่งแพ้ก่อน (conservative เมื่อแท่งเดียวแตะทั้งสองฝั่ง)
         if(dir ==  1) { if(gL[i] <= mid) { gBOFail[b]++; break; } if(gH[i] >= target) { gBOCont[b]++; break; } }
         if(dir == -1) { if(gH[i] >= mid) { gBOFail[b]++; break; } if(gL[i] <= target) { gBOCont[b]++; break; } }
      }

      // 3b) sweep: wick ทะลุกรอบแต่ปิดกลับใน → ถึงกลางกรอบก่อนจะมี M5 ปิดนอกกรอบฝั่งนั้น
      int sdir = 0;
      for(int i = 0; i < gN; i++)
      {
         if(gMin[i] < lonStart) continue;
         if(gMin[i] >= outEnd) break;
         if(sdir == 0)
         {
            if(gMin[i] >= lonEnd) break;
            if(gC[i] > aHi || gC[i] < aLo) break;          // ปิดนอกกรอบก่อน = เป็น breakout ไม่ใช่ sweep
            if(gH[i] > aHi)      { sdir =  1; gSweep[b]++; }
            else if(gL[i] < aLo) { sdir = -1; gSweep[b]++; }
            continue;
         }
         if(sdir ==  1) { if(gC[i] > aHi) break; if(gL[i] <= mid) { gSweepWin[b]++; break; } }
         if(sdir == -1) { if(gC[i] < aLo) break; if(gH[i] >= mid) { gSweepWin[b]++; break; } }
      }
   }

   //--- 4) NY-PM: 16:00-20:00 UTC (ฤดูหนาว) เลื่อนตาม DST สหรัฐ
   int pmStart = 960 - (IsUSDST(utcDay) ? 60 : 0);
   int pmEnd   = pmStart + 240;
   double hi = 0, lo = 0, p16 = 0, pmHi = 0, pmLo = 0, pmClose = 0;
   bool pre = false, pm = false;
   for(int i = 0; i < gN; i++)
   {
      if(gMin[i] < pmStart)
      {
         if(!pre) { hi = gH[i]; lo = gL[i]; pre = true; }
         else     { hi = MathMax(hi, gH[i]); lo = MathMin(lo, gL[i]); }
         p16 = gC[i];
      }
      else if(gMin[i] < pmEnd)
      {
         if(!pm) { pmHi = gH[i]; pmLo = gL[i]; pm = true; }
         else    { pmHi = MathMax(pmHi, gH[i]); pmLo = MathMin(pmLo, gL[i]); }
         pmClose = gC[i];
      }
   }
   if(pre && pm && hi > lo)
   {
      double rng = (hi - lo) / adr;
      double pos = (p16 - lo) / (hi - lo);
      int tdir = 0;
      if(rng >= 1.0 && pos >= 0.75) tdir =  1;
      if(rng >= 1.0 && pos <= 0.25) tdir = -1;
      if(tdir != 0)
      {
         gTrendDays++;
         double mv = (pmClose - p16) * tdir;
         gTrendMove += mv / adr;
         if(mv > 0) gTrendCont++;
         if((tdir == 1 && pmHi > hi) || (tdir == -1 && pmLo < lo)) gTrendNewExt++;
      }
      else if(rng < 0.7)
      {
         gRangeDays++;
         gRangePM += (pmHi - pmLo) / adr;
         if(pmHi > hi || pmLo < lo) gRangeBreak++;
      }
   }
}

double Pct(int a, int b) { return b > 0 ? 100.0 * a / b : 0; }

//+------------------------------------------------------------------+
void OnStart()
{
   ArrayInitialize(gHourSum, 0); ArrayInitialize(gHourCnt, 0);
   ArrayInitialize(gBoxDays, 0); ArrayInitialize(gBO, 0);
   ArrayInitialize(gBOCont, 0);  ArrayInitialize(gBOFail, 0);
   ArrayInitialize(gSweep, 0);   ArrayInitialize(gSweepWin, 0);
   ArrayResize(gMin, 400); ArrayResize(gO, 400); ArrayResize(gH, 400);
   ArrayResize(gL, 400);   ArrayResize(gC, 400);

   MqlRates r[];
   int want = (InpDays + InpADRPeriod + 5) * 288;
   int got  = CopyRates(_Symbol, PERIOD_M5, 0, want, r);    // index 0 = แท่งเก่าสุด
   if(got <= 0) { Print("CopyRates ล้มเหลว err=", GetLastError()); return; }
   if(got < want) PrintFormat("ได้ข้อมูล M5 แค่ %d จาก %d แท่ง — โหลด history เพิ่มถ้าต้องการช่วงยาวขึ้น", got, want);

   long curDay = -1;
   for(int i = 0; i < got; i++)
   {
      datetime utc = ServerToUTC(r[i].time);
      long day = (long)utc / 86400;
      if(day != curDay)
      {
         if(curDay >= 0) ProcessDay((datetime)(curDay * 86400));
         curDay = day; gN = 0;
      }
      if(gN >= 400) continue;
      gMin[gN] = (int)(((long)utc % 86400) / 60);
      gO[gN] = r[i].open; gH[gN] = r[i].high; gL[gN] = r[i].low; gC[gN] = r[i].close;
      gN++;
   }
   // วันสุดท้ายยังไม่จบ จึงไม่นำมาคิด

   if(gDays == 0) { Print("ข้อมูลไม่พอคำนวณ"); return; }

   int f = FileOpen(InpOutFile, FILE_WRITE | FILE_CSV | FILE_ANSI, ',');
   PrintFormat("=== %s | %d วัน | ADR(%d) ===", _Symbol, gDays, InpADRPeriod);

   Print("--- 1) range เฉลี่ยรายชั่วโมง (UTC) เป็น % ของ ADR ---");
   if(f != INVALID_HANDLE) FileWrite(f, "section", "key", "value", "n");
   for(int h = 0; h < 24; h++)
   {
      double v = gHourCnt[h] > 0 ? 100.0 * gHourSum[h] / gHourCnt[h] : 0;
      PrintFormat("%02d:00  %.1f%%  (n=%d)", h, v, gHourCnt[h]);
      if(f != INVALID_HANDLE) FileWrite(f, "hour_range_pct_adr", h, DoubleToString(v, 2), gHourCnt[h]);
   }

   int boxAll = gBoxDays[0] + gBoxDays[1] + gBoxDays[2];
   PrintFormat("--- 2) กรอบเอเชียเฉลี่ย = %.1f%% ของ ADR ---", boxAll > 0 ? 100.0 * gAsiaSum / boxAll : 0);
   string bn[3] = {"<0.15 ADR", "0.15-0.45 ADR", ">0.45 ADR"};
   Print("--- 3) London เทียบกรอบเอเชีย แยกตามความกว้างกรอบ ---");
   for(int b = 0; b < 3; b++)
   {
      PrintFormat("[%s] วัน=%d | breakout=%d ไปต่อ1R=%.1f%% กลับกลางกรอบ=%.1f%% | sweep=%d ถึงกลางกรอบ=%.1f%%",
                  bn[b], gBoxDays[b], gBO[b], Pct(gBOCont[b], gBO[b]), Pct(gBOFail[b], gBO[b]),
                  gSweep[b], Pct(gSweepWin[b], gSweep[b]));
      if(f != INVALID_HANDLE)
      {
         FileWrite(f, "box_days",          bn[b], gBoxDays[b], boxAll);
         FileWrite(f, "breakout_cont_pct", bn[b], DoubleToString(Pct(gBOCont[b], gBO[b]), 1), gBO[b]);
         FileWrite(f, "breakout_fail_pct", bn[b], DoubleToString(Pct(gBOFail[b], gBO[b]), 1), gBO[b]);
         FileWrite(f, "sweep_win_pct",     bn[b], DoubleToString(Pct(gSweepWin[b], gSweep[b]), 1), gSweep[b]);
      }
   }

   Print("--- 4) NY-PM (4 ชม. หลัง London ปิด) ---");
   PrintFormat("วัน trend=%d | ปิดไปต่อทางเดิม=%.1f%% | ทำ extreme ใหม่=%.1f%% | move เฉลี่ยตามทาง=%.1f%% ADR",
               gTrendDays, Pct(gTrendCont, gTrendDays), Pct(gTrendNewExt, gTrendDays),
               gTrendDays > 0 ? 100.0 * gTrendMove / gTrendDays : 0);
   PrintFormat("วัน range=%d | หลุดกรอบของวัน=%.1f%% | range ช่วงบ่ายเฉลี่ย=%.1f%% ADR",
               gRangeDays, Pct(gRangeBreak, gRangeDays),
               gRangeDays > 0 ? 100.0 * gRangePM / gRangeDays : 0);
   if(f != INVALID_HANDLE)
   {
      FileWrite(f, "pm_trend_cont_pct",   "trend", DoubleToString(Pct(gTrendCont, gTrendDays), 1), gTrendDays);
      FileWrite(f, "pm_trend_newext_pct", "trend", DoubleToString(Pct(gTrendNewExt, gTrendDays), 1), gTrendDays);
      FileWrite(f, "pm_range_break_pct",  "range", DoubleToString(Pct(gRangeBreak, gRangeDays), 1), gRangeDays);
      FileClose(f);
      Print("บันทึก CSV: MQL5/Files/", InpOutFile);
   }
}
//+------------------------------------------------------------------+
