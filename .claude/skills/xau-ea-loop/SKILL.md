---
name: xau-ea-loop
description: >
  The repeatable "loop engineering" workflow this repo's owner uses to find, test and ship XAUUSD (gold)
  MT5 EAs: pick ~10 TradingView indicators/strategies, port them, run the fixed test gates, combine the
  survivors into a portfolio, build the EA with the Thai mothership dashboard, document, and file
  everything in the locker and Google Drive. Use when the user asks for another round ("หาอีก 10 ตัว",
  "ทำตามขั้นตอนเดิม", "รอบใหม่", "สร้างอีเอตัวใหม่", "loop", "แผนงาน"), or for a scalping / M1-M5-M15 /
  new-style search. Load xau-ea-research for engine details and past results.
---

# XAU EA loop — แผนงานวนรอบ (ใช้ทุกครั้งที่หาเครื่องยนต์ / สร้างอีเอใหม่)

ตอบเป็นภาษาไทย สั้น ใช้ตาราง ผู้ใช้เป็นนักพัฆนา MQL5 (ทองคำ, Exness GMT+0, ทุน $300 → ใช้บัญชี Cent)

## กติกาถาวร (ไม่ต้องถามซ้ำ)
- ทดสอบ **2 ปี** (พ.ย. 2024 → ล่าสุด) บน Dukascopy M1 bid/ask (`m1.load_m1`, 4 pseudo-ticks/นาที) · ปีล่าสุดตรวจซ้ำด้วย real tick ได้ (`bt.load`)
- เป้า: กำไรเร็ว ไม้บ่อย DD ≤ 50% (ผู้ใช้ยอม 70% ได้เมื่อขอ) · ค่าเริ่มต้นความเสี่ยงใน EA = ระดับที่โอกาสชน DD 70% (bootstrap) ≤ ~5%
- **รายงานผลก่อนสร้างอีเอทุกครั้ง** แล้วรอผู้ใช้ยืนยัน
- ห้ามรัน/แกะ .ex5 ที่ crack · ห้ามใส่อีเมล/ข้อมูลส่วนตัวในงานภายนอก
- ทุน $300 Standard ใช้ไม่ได้กับระบบ SL กว้าง (0.01 ล็อตเสี่ยง 7–14%) → Cent เท่านั้น หรือ Standard ≥ $3,000

## ลูป 8 ขั้น

| # | ขั้น | ทำอะไร | ด่านผ่าน / ผลลัพธ์ |
|---|---|---|---|
| 1 | **เลือก 10 ตัว** | อินดิเคเตอร์/กลยุทธ์ TradingView ที่ยังไม่อยู่ในรายชื่อ "ไม่ผ่าน" (`MQL5/Locker/tradingview/C_*.md`) · ใช้ค่าเดิมของผู้สร้าง · ตัวที่เป็น community script ขอ Pine source จากผู้ใช้ (ให้ชื่อ+ผู้สร้างให้ค้น) | ตารางชื่อ / ประเภท / ค่า แจ้งผู้ใช้ก่อนรัน |
| 2 | **พอร์ต + ล็อกกติกาล่วงหน้า** | เขียนฟังก์ชันใน `MQL5/Research/xau_daytrend/indNN.py` คืนค่า event (bar, dir, exit_bar) · กำหนดชุดค่าที่จะลอง *ก่อน* รัน ห้ามไล่จูนหลังเห็นผล | ทดสอบกับข้อมูลสุ่มว่าคืนสัญญาณได้ |
| 3 | **ทดสอบเดี่ยว** | ทุก TF ที่ระบุ · เข้า tick ถัดไปหลังแท่งปิด · SL k×ATR14 · ออกตามสัญญาณ/TP/เวลา ตามที่ล็อกไว้ · หักสเปรดจริง | ไม้/เดือน, R/ไม้, ปีก่อน/ปีล่าสุด, Buy/Sell |
| 4 | **ด่านสถิติ** | สุ่มทิศ 2 ปี (สลับ Buy/Sell 3,000–10,000 รอบ) | **ผ่าน** = สุ่มทิศ ≥ 95% + บวกทั้ง 2 ปี · **A** = + Buy และ Sell บวก + ≥ 99.5% · **B** = ผ่านมีข้อสังเกต · **C** = พึ่งฝั่ง Buy |
| 5 | **ด่านพอร์ต** | ความสัมพันธ์ R รายสัปดาห์กับเครื่องยนต์เดิม · จำลองเงิน Cent $300 ทบต้น เพดาน 70% · เทียบ **ที่ DD เท่ากัน** (`sentinel_bt_run.run`) | ใส่ได้เฉพาะตัวที่ทำให้กำไรที่ DD เท่ากัน **เพิ่มขึ้น** |
| 6 | **รายงาน → รอยืนยัน** | ตารางผล + ข้อเสนอ EA + ข้อควรระวัง (เลือกหลังเห็นผล, ยังไม่หัก swap, จำนวนการทดสอบ) | ผู้ใช้ตอบ "สร้าง" |
| 7 | **สร้างอีเอ** | ต่อยอดจาก `XAU_QUARTET_v1.10.mq5` (แดชบอร์ดยานแม่ไทย, ล็อตอัตโนมัติ 5 โหมด, ความเสี่ยง 5 ระดับ, ธีมกราฟ) · เขียน `StateXXX()` ต่อเครื่องยนต์ · ตาราง BtEnd/BtDD/BtRuin จากการจำลอง 5 ระดับ + bootstrap · magic ใหม่ไม่ชนตัวเดิม | **parity 100%** (พอร์ต State function กลับเป็น Python เทียบสัญญาณวิจัย) |
| 8 | **เก็บงาน** | คู่มือ `MQL5/Docs/passed/NN_*.md` · README ใน Research · การ์ดใน `MQL5/Locker/tradingview/` (`make_tv_cards` pattern) · ภาพหน้าจอไทย (HTML → Playwright PNG) · commit+push PR · อัปโหลด Drive โฟลเดอร์ `EA_ผ่านการทดสอบ_2026-11-20/<NN_ชื่อ>` + ล็อกเกอร์ | ลิงก์ Drive + สรุปให้ผู้ใช้ |

## ไฟล์/เครื่องมือหลัก
- เอนจิน: `bt.py` (`bars`, `execute(tt,tb,ta,sig,tps,slip)` → คอลัมน์ `r<tp>`, `x<tp>`), `m1.py` (`load_m1`)
- อินดิเคเตอร์ที่ผ่าน: `MQL5/Locker/tradingview/locker_indicators.py` · ผลดิบ `multi_tf.csv`, `ind11.csv`, `fast_tf.csv`
- จำลองเงิน: `sentinel_bt_run.run(parts, f, cent, halt, cap)` · Standard: `std_cap.py`
- ข้อมูลอยู่ใน scratchpad ของ session (`bt/m1raw`, `bt/days`) หายได้เมื่อ session ใหม่ → ดาวน์โหลดใหม่ด้วย `dl.py` (tick) / `dlc.py` (M1) ใน Research
- Drive: โฟลเดอร์หลัก `EA_ผ่านการทดสอบ_2026-11-20` · ล็อกเกอร์ `00_ล็อกเกอร์_กลยุทธ์ที่ผ่าน` · อัปโหลดไฟล์ด้วย file reference `sha256:<hex>:<path>`; PNG/mq5/csv ต้อง `disableConversionToGoogleType`

## รูปแบบรอบ "สาย Scalping" (M1 / M5 / M15)
บทเรียนเดิม: อินดิเคเตอร์เทรนด์ที่ถือจนกลับทิศ **ขาดทุนทุกตัวบน M5** (สเปรด ~$0.6 ≈ 12% ของ SL $5) แม้กรองด้วย SSL H4 · Straddle/Scalper เดิมแพ้สเปรด
ดังนั้นรอบ scalping ต้องล็อกไว้ก่อนรัน:
- เข้าไม้เฉพาะช่วงสเปรดแคบ/วอลุ่มสูง (07:00–20:00 UTC) · หลีกเลี่ยง 20:00–23:00 UTC (สเปรดกว้าง)
- ทางออกแบบ scalping: SL 1×ATR14 ของ TF, TP 1.5R, ออกตามเวลา (48 แท่ง) · เทียบแบบมี/ไม่มีตัวกรองทิศ H1
- ด่านเพิ่ม: R/ไม้หลังหักสเปรด > +0.05 และ ≥ 40 ไม้/เดือนต่อเครื่อง จึงจะนับว่าเป็น "สาย scalping ที่ใช้ได้"
- ถ้าไม่มีตัวผ่าน: รายงานตรง ๆ ไม่สร้างอีเอที่ขาดทุน · เสนอทางเลือกที่ผ่านแล้ว (TURBO M30, ORB M15)

## ประวัติรอบ (อัปเดตทุกครั้งที่จบรอบ)
| รอบ | วันที่ | ผลลัพธ์ |
|---|---|---|
| 1–5 | 2026-11 | SSL, MACD, Coral, Aroon, KST ฯลฯ → SENTINEL, THUNDER, QUARTET |
| 6 | 2026-11-21 | 10 ตัว: PMO, AO, MAMA ผ่าน (H4 ช่วยพอร์ต) → HEXA |
| 7 | 2026-11-21 | M5/M15/M30 + กรอง H4: M5 ตายหมด, AO M30 ผ่าน → HEXA TURBO |
| 8 | 2026-11-21 | สาย scalping M1/M5/M15 (10 กลยุทธ์) — ดู README "Batch 8" |
