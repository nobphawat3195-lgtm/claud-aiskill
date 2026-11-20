# 03 · XMS v2.90 (XAU MultiSession, สร้างโดย Grok Bot)

## ไฟล์
- XAU_MultiSession_EA_v2.90_USD.ex5 + XMS_v2.90_USD_300_STANDARD.set (แพ็กเกจ XMS_USD300_BEST ของคุณ)
- README_TH.txt, tester_XMS290_STANDARD.ini
- XMS_v2.91_source.zip: source code v2.91 (ใช้ตรวจ logic; v2.91 เพิ่มเฉพาะตัวเลือกที่ปิดเป็นค่าเริ่มต้น)

## LOGIC (โหมด RECENT, 5 โมดูล)
- ORB_A: กรอบ 00:00–01:00 UTC บน M5 breakout 01:05–06:00 SL 1.75 ATR(H1)
- DM_A: 01:00 UTC ถ้า ADX(H1) < 25 ทิศตามราคาปิด H1 00:00 เทียบราคาเปิดวันก่อน SL 1 ATR ถือถึงปิดวัน
- DM_L, ASIA_B, LON_A: โมดูลเสริมช่วงเอเชีย/ลอนดอน
- ขนาด lot ตามความเสี่ยง 1.5% ใช้ lot ขั้นต่ำได้เมื่อเสี่ยงจริง ≤ 5.5% (ORB_A/DM_A/DM_L) หรือ ≤ 2% (ASIA_B/LON_A) · ลดความเสี่ยงที่ DD 35/45% หยุดที่ 48%

## ผลทดสอบ (Standard 300 USD, ปีล่าสุด)
- MT5 Strategy Tester ของ Grok (real tick): +3,461 USD, DD 32.5%, 471 ไม้
- Replica ของเรา (Dukascopy real tick): +3,367 USD, DD 44%, ~34 ไม้/เดือนเมื่อทุนโต
- ชนะการสุ่มทิศ 100% ของ 10,000 รอบ · ถือ Buy ตลอด −84R
- ตรวจ source v2.91 แล้ว: .set ใช้ได้กับทุน 300 จริง (cap 5.5% ใน RECENT)

## ความเสี่ยงสำคัญ
- ผลขึ้นกับวันเริ่ม: bootstrap 1 ปีจาก 3 ปี โอกาสขาดทุน 52%, ชนจุดหยุด 81% · ปี 2024 ชนจุดหยุดตั้งแต่ ก.พ.
- เดือนแรกๆ ข้ามไม้เยอะ (SL กว้างกว่า cap ที่ทุน 300)
- ค่าถูกปรับบนปีเดียวกัน · ลอง ปรับ SL แล้ว PBO 0.57 → ใช้ค่าเดิม
- ห้ามใช้ preset v4.10 USD300 HIGH_RISK (ปิดจุดหยุด DD)

## การใช้งาน
Exness Standard 300, กราฟ XAUUSD M5, โหลด XMS_v2.90_USD_300_STANDARD.set, demo 4–8 สัปดาห์ก่อน
