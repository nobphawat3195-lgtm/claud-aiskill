# แบบ EA ทองคำหลายเซสชัน (XAUUSD, M1/M5, MQL5)

สถานะ: แบบร่าง ยังไม่มี backtest รองรับ ตัวเลขทุกตัวเป็นค่าเริ่มต้นสำหรับ optimize
ต้องยืนยันด้วย `MQL5/Scripts/XAU_SessionStats.mq5` และ Strategy Tester (real ticks) ก่อนใช้จริง

## 1. โครงสร้างรวม

EA ตัวเดียว มี session router เลือกโมดูลตามเวลา และใช้ระบบจัดการกลางร่วมกัน

```
OnTick
 ├─ GlobalGuard   : daily loss / DD / spread / news / rollover / Friday
 ├─ SessionRouter : เวลา UTC + DST → ASIA | LONDON | NY | NY_PM | OFF
 ├─ Module[sess]  : สร้าง signal อย่างเดียว (entry, SL, TP, type)
 ├─ RiskEngine    : lot จาก risk% กับระยะ SL, ตรวจเพดาน risk รวม
 ├─ Execution     : ส่ง order, ตรวจ stops/freeze level, retry, จำกัด slippage
 ├─ TradeManager  : partial / BE / trail / time-stop แยกตาม magic
 └─ TradeLog      : CSV ทุกไม้ (ราคาที่ขอ, ราคาที่ได้, spread, slippage, ผลเป็น R)
```

หลักการ:

- Magic แยกโมดูล: base+1 Asia, +2 London, +3 NY, +4 NY-PM
- ทุกระยะคิดเป็นเท่าของ ATR และต้องไม่ต่ำกว่า 5 เท่าของ spread ปัจจุบัน ไม่ใช้ fixed points
- 1 signal ต่อ 1 ไม้ ไม่มี grid, averaging หรือ martingale
- เวลาใช้ UTC ทั้งหมด แปลงจากเวลาเซิร์ฟเวอร์ตามกฎ DST ของโบรกเกอร์ และแยก DST ลอนดอนกับนิวยอร์ก

## 2. ตารางเซสชัน (UTC ฤดูหนาว)

ช่วง DST เลื่อน London เร็วขึ้น 1 ชม. ตาม DST ยุโรป และ NY / NY-PM ตาม DST สหรัฐ

| เซสชัน | เวลา | ลักษณะตลาด | Logic | Risk ต่อไม้ |
|---|---|---|---|---|
| Asia | 00:00–06:00 | range แคบ สภาพคล่องต่ำ | Mean reversion | 0.75% |
| London | 07:00–10:30 | ขยับจริงครั้งแรกของวัน | Asian box breakout + sweep reversal | 1.5% |
| New York | 12:30–16:00 | volatility สูงสุด ขับด้วยข่าว USD | ORB + trend pullback | 1.5% |
| NY-PM | 16:00–20:00 | volatility ลดลงหลัง London ปิด | Continuation หรือ VWAP fade ตามประเภทวัน | 0.75% |
| OFF | 20:30–24:00 | ตลาดพัก, rollover, spread ถ่าง | ไม่เทรด เก็บ high/low หลัง 23:00 ให้กรอบเอเชีย | – |

## 3. Logic รายโมดูล

### 3.1 Asia: range fade (M5)

- Regime filter: ADX(M15,14) < 20 และกรอบเอเชียปัจจุบัน < 0.35×ADR(D1,14) ไม่ผ่านให้ปิดโมดูลทั้งเซสชัน
- Entry: ราคาแตะ BB(20, 2.0) ด้านนอก, RSI(7) < 25 หรือ > 75, แท่ง M1 ปิดกลับเข้า band ใช้ limit order
- SL: 1.0×ATR(M5) เลยจุด extreme
- TP: เส้นกลาง BB หรือ session VWAP
- ข้อจำกัด: สูงสุด 3 ไม้ต่อเซสชัน แพ้ 2 ไม้ติดให้หยุด
- ปิดทุกไม้ก่อน 06:30 และบันทึก `AsiaHigh/AsiaLow` ส่งต่อให้ London

### 3.2 London: Asian box สองโหมด (M5)

- Box filter: ความกว้างกรอบ 0.15–0.45×ADR
- โหมด A (breakout): M5 ปิดนอกกรอบเกิน 0.1×ATR และ ATR(M5) สูงกว่าค่าเฉลี่ย 20 แท่ง
  วาง stop order เหนือ high ของแท่ง breakout
  SL ที่กลางกรอบหรือ 1.5×ATR (เลือกค่าที่แคบกว่า), TP1 ที่ 1R ปิดครึ่ง ที่เหลือ trail
- โหมด B (sweep reversal): ราคาทะลุกรอบอย่างน้อย 0.15×ATR แล้ว M5 ปิดกลับเข้ากรอบภายใน 3 แท่ง ให้ fade
  SL เลย wick ของ sweep, TP1 ที่กลางกรอบ, TP2 ที่ขอบตรงข้าม
- ถ้าโหมด A โดน SL แล้วเข้าเงื่อนไขโหมด B กลับด้านได้ 1 ครั้ง จำกัดฝั่งละ 1 ไม้ต่อวัน
- โหมด A ใช้โครง Buy Stop/Sell Stop ของ StraddleScalper ได้ โดยอ้างอิงขอบกรอบเอเชียและตัด recenter ออก

### 3.3 New York: momentum (M5 entry, M15 bias)

- Bias: EMA50(M15) ร่วมกับตำแหน่งราคาเทียบ session VWAP เทรดทางเดียวตาม bias
- Setup 1 (ORB): กรอบ 15 นาทีแรกหลัง 13:30 UTC เข้าเมื่อ M5 ปิดนอกกรอบตาม bias
  SL ที่ฝั่งตรงข้ามของกรอบ ไม่เกิน 2×ATR
- Setup 2 (pullback): หลัง impulse เกิน 1.5×ATR รอย่อถึง EMA20(M5) หรือ VWAP เข้าเมื่อมีแท่งกลับตัว
  ใช้ logic break+retest ของ VWSR Zone EA ได้
- News filter: งดเปิดไม้ใหม่ 5 นาทีก่อนถึง 3 นาทีหลังข่าว USD high-impact และยกเลิก pending ก่อนข่าว
  `CalendarValueHistory` ใช้ใน Strategy Tester ไม่ได้ ต้องโหลดข่าวย้อนหลังจาก CSV
- ส่งต่อที่ 16:00: ไม้ที่กำไรเกิน 1R ให้ trail ต่อ ไม้ที่เหลือปิด

### 3.4 NY-PM: เลือกโหมดตามประเภทวัน (M5)

จำแนกวันที่ 16:00 แล้วใช้โหมดเดียวทั้งเซสชัน

- Trend day: range ของวัน > 1.0×ADR, ราคาอยู่ใน 25% บนหรือล่างของ range วัน, ADX(M15) > 25
- Range day: range ของวัน < 0.7×ADR, ADX(M15) < 20, ราคาตัด session VWAP อย่างน้อย 3 ครั้งนับจาก 12:30
- ไม่เข้าทั้งสองแบบ: ปิดโมดูลวันนั้น

โหมด A (continuation, trend day):

- เทรดทางเดียวตามทิศของวัน
- Entry เมื่อย่อถึง EMA20(M5) หรือ VWAP band 1σ แล้วแท่ง M5 กลับตัวปิดตามเทรนด์
- SL 1.2×ATR(M5) เลย swing ของการย่อ
- TP1 ที่ 1R ปิดครึ่ง ที่เหลือเป้า high/low ของวัน

โหมด B (VWAP fade, range day):

- Entry เมื่อราคาแตะ VWAP band 2σ, RSI(7) สุดขั้ว, M1 ปิดกลับเข้า band
- SL 1.0×ATR(M5) เลยจุด extreme, TP ที่ VWAP

ข้อจำกัดเฉพาะโมดูล:

- สูงสุด 2 ไม้ต่อเซสชัน แพ้ 1 ไม้ให้หยุด
- Spread ไม่เกิน 12% ของระยะ SL
- ไม่เปิดถ้า daily loss ใช้ไปเกินครึ่งของเพดาน
- วัน FOMC ปิดโมดูลทั้งวัน
- ไม่เปิดไม้ใหม่หลัง 20:00 ปิดทั้งหมดก่อน 20:30

## 4. ระบบจัดการกลาง

### 4.1 ความเสี่ยง (เพดาน DD 50%)

| รายการ | ค่า |
|---|---|
| Risk ต่อไม้ London / NY | 1.5% ของ equity |
| Risk ต่อไม้ Asia / NY-PM | 0.75% ของ equity |
| Risk รวมที่เปิดอยู่ | ไม่เกิน 4% |
| Daily loss | 6% แล้วหยุดทั้งวัน |
| DD จาก peak ถึง 25% | ลด risk ทุกโมดูลเหลือครึ่ง |
| DD จาก peak ถึง 40% | ลด risk เหลือหนึ่งในสี่ |
| DD จาก peak ถึง 45% | หยุด EA จนกว่าจะ reset เอง |

- Position sizing: `lot = (Equity × risk%) / (SL_points × tick_value_per_point)` normalize ตาม `SYMBOL_VOLUME_STEP`
  ถ้าต่ำกว่า min lot ให้ข้ามไม้ ไม่ปัดขึ้น
- Lot คิดจาก equity ปัจจุบันทุกไม้ กำไรจึงทบต้นเอง
- ไม่เพิ่ม lot หลังแพ้
- หยุดที่ 45% เพื่อเผื่อ slippage และ gap ของไม้ที่ยังเปิดอยู่
- Risk 1.5% เป็นค่าประมาณ ต้องปรับตาม DD จริงจาก backtest ของแต่ละโมดูล

### 4.2 ตัวกรองและการจัดการไม้

- Spread guard: spread ไม่เกิน 15% ของระยะ SL และไม่เกิน 2 เท่าของ median spread 200 tick ล่าสุด
- Trade management: ปิด 50% ที่ 1R, เลื่อน SL ไป BE บวก spread, trail แบบ chandelier 1.0–1.5×ATR(M5)
- Time-stop: ไม่ถึง 0.5R ภายใน N แท่งให้ปิด (Asia 12, London และ NY 8, NY-PM 10)
- ช่วงห้ามเทรด: rollover 21:00–23:00 UTC, วันศุกร์ปิดทุกไม้ก่อน 20:00 UTC, วันหยุดสหรัฐและอังกฤษ
- State: daily counter, กรอบเอเชีย, สถานะโมดูล, equity peak เก็บใน GlobalVariable
  เมื่อ restart ให้ scan position ตาม magic เพื่อกู้สถานะ

## 5. ขั้นตอนพิสูจน์

1. รัน `XAU_SessionStats.mq5` เพื่อตั้งค่าเริ่มต้นจากข้อมูลโบรกเกอร์จริง
2. Backtest ทีละโมดูลใน MT5 โหมด "Every tick based on real ticks" ตัดโมดูลที่ไม่มี edge
3. Walk-forward ข้ามหลาย regime แล้วรวมโมดูลและทดสอบเพดาน risk รวม
4. Forward test บน demo หรือ cent ของโบรกเกอร์เดียวกัน 2–4 สัปดาห์
5. Backtest ช่วงเดียวกับ forward แล้วเทียบไม้ต่อไม้จาก TradeLog เพื่อหาว่าต้องหักผล backtest ลงเท่าไร

## 6. ข้อมูลที่ยังขาด

- ขนาดทุน และประเภทบัญชี (Standard หรือ Cent, ส่วนตัวหรือ prop firm)
- GMT offset และกฎ DST ของเซิร์ฟเวอร์โบรกเกอร์
- บัญชี hedging หรือ netting
- ชื่อ symbol, spread เฉลี่ย และ commission
