# XAU300_ORB_CappedRecovery_Research — สเปกและ presets ที่ล็อกไว้ (research only, เสี่ยงสูง)

**สถานะ:** ยังไม่มีผล MT5 ไม่ได้รัน simulator (ตามคำสั่ง) และยังไม่เคย compile ใน cloud ผลจริงต้องมาจาก MT5 real tick ในเครื่องผู้ใช้
**ข้อตกลง:** เกณฑ์ DD 35% ที่ผู้ใช้กำหนดเป็นเกณฑ์ตัดสินผล backtest เท่านั้น **ไม่มีอะไรรับประกันว่า DD จะไม่เกิน 35%** EA ตัวนี้ใช้วิจัยเท่านั้น ห้ามใช้กับเงินจริง

## ที่มาของกฎ
- Entry, exit, one-shot และ rolling filter **เหมือน** `XAU300_ORB_Research.mq5` (preset costaware: ปิด spread gate) ทุกตัวอักษร
  - test ตรวจว่า function `RangeOf`, `RollingMedianPct`, `NewDay`, `EndDay`, `StopsOK`, `ManagePosition`, `FlattenMine`, `AnyPositionOnSymbol`, `VolumeFloor`, `DayAllowed` และ `OnTick` ตรงกับ ORB เดิม (ยกเว้นบรรทัด `ProcessClosedPosition()` ที่เพิ่มเข้าไป)
- สเปก ORB มาจาก anas1412/orb-mt5 @`0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9` (MIT, Copyright (c) 2026 anas1412) เขียนโค้ดใหม่ ไม่ได้คัดลอก
- ไฟล์ EA เดิมไม่ได้แก้ magic ใหม่คือ **300335**

## Capped loss-progression (เพิ่ม risk % ไม่ใช่คูณ lot)
- **ความเสี่ยงต่อไม้:** `effectiveRisk = min(baseRisk × multiplier^level, 8%)` โดย level มีแค่ 0, 1, 2
- **การเปลี่ยน level:**
  - ไม้ชนะ หรือ net อยู่ในช่วง ±0.01 (breakeven) → กลับ 0
  - ไม้แพ้ → level +1
  - แพ้ตอน level 2 → **จบ cycle กลับ 0** ไม่ค้างที่ risk สูง
- **นับเฉพาะเมื่อ position ปิดครบ:**
  - net = ผลรวม profit + swap + commission + fee ของทุก deal ใน position รวมค่าธรรมเนียมตอนเข้า
  - ถ้าเพิ่งปิดบางส่วน (partial close) จะรอจนปิดครบ ถ้า history ยังไม่ครบจะลองใหม่ tick ถัดไป
  - แต่ละ position id ถูกนับแค่ครั้งเดียว โดยเก็บ `lastpos` ไว้
- **เก็บ state ข้ามการรีสตาร์ท:** `level`, `track` และ `lastpos` แยกตาม account/magic/symbol ตอน restore ถ้า level อยู่นอกช่วง 0..MaxLevel หรือปิด recovery อยู่ จะตั้งเป็น 0
- **Lot:** ปัดลงเป็นจำนวนเต็มของ step, cap ด้วย `InpMaxLot=0.10` แล้วตรวจความเสี่ยงซ้ำ ถ้า lot ขั้นต่ำเกิน budget จะข้าม ไม่บังคับ 0.01
- ไม่มี grid หรือ averaging เปิดได้ครั้งละ 1 position ส่วน input ถูกจำกัดใน OnInit: cap ≤ 8%, MaxLevel ≤ 2, multiplier 1–3
- **Guards:**
  - DD stop 30% เผื่อ buffer ไว้ก่อนเกณฑ์ 35% แต่ถ้าราคากระโดด (gap) หรือ slippage ก็เกินได้
  - daily hard stop 3% เหมือนเดิม ถ้าความเสี่ยงต่อไม้เกิน 3% ไม้ที่แพ้มักถูก daily stop ปิดก่อนถึง SL เต็ม EA จะ log `NOTE` และนับ `risk_above_daily` ไว้

## Presets ที่ล็อกก่อนรัน MT5 (สูงสุด 4 ชุด)
| preset | recovery | base | mult | risk ตาม level 0/1/2 |
|---|---|---|---|---|
| `R0_autolot5` | ปิด | 5% | – | 5% (auto-lot อย่างเดียว) |
| `R1_marti2x_base2` | เปิด | 2% | 2.0 | 2% / 4% / 8% |
| `R2_marti1p5_base2` | เปิด | 2% | 1.5 | 2% / 3% / 4.5% |
| `R3_marti1p5_base3` | เปิด | 3% | 1.5 | 3% / 4.5% / 6.75% |

- **ค่าที่ทุก preset ใช้เหมือนกัน:** DD 30%, daily 3%, spread gate 0, max level 2, cap 8%, max lot 0.10, BE tolerance 0.01, equity CSV เปิด, ไม่อนุญาตบัญชี real
- **ความต่างระหว่าง preset:** มีแค่ `InpRiskPercent`, `InpRecoveryOn` และ `InpRecoveryMultiplier` ซึ่ง test ตรวจไว้แล้ว

## Tests
- `recovery_ref.py` เป็น oracle ฝั่ง Python ของ state machine
- tests ครอบคลุม: fixture net ของ position ที่ปิดแล้ว (ค่าธรรมเนียมตอนเข้า + partial close + swap/commission/fee = −6.00), การรอ partial close, การ retry, กันนับซ้ำ, การรีสตาร์ทที่ track ค้าง, บันไดระดับและการจบ cycle, การปัด breakeven, cap 8%, MaxLot และการไม่บังคับ lot ขั้นต่ำ
- มี source guard ที่เทียบกับ ORB เดิม และตรวจ presets R0–R3
