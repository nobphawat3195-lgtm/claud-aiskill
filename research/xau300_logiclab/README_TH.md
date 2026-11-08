# XAU300_ORB_LogicLab_v2 (research only)

- **ไฟล์:** EA อยู่ที่ `MQL5/Experts/XAU300_ORB_LogicLab_v2.mq5` (magic 300336) และ presets 3 ชุดที่ `MQL5/Presets/XAU300_ORB_LogicLab_v2_Q{0,1,2}_*.set`
- **กฎที่ล็อกไว้:** [PREREGISTRATION.md](PREREGISTRATION.md) commit `570b0f2` ก่อนเขียนโค้ดและก่อนมีผล
- **ที่มา:** สร้างจาก R0 (`XAU300_ORB_CappedRecovery_Research` ที่ปิด recovery) โดยไม่แก้ EA เดิมหรือ presets เดิม
  - Guards, sizing, exits, session, rolling, half filter, one-shot และ equity CSV เหมือนเดิม
  - สิ่งที่เพิ่มมีแค่ `InpEntryLogic` และ `InpBreakCloseLocationMin`
- **Mode 0 (control):** มีบรรทัดใน OnTick ที่เปลี่ยน 7 บรรทัด แต่ทุกบรรทัดไม่มีผลเมื่อ `InpEntryLogic=0` (ไม่มี pending state) test เทียบ function อื่นทั้งหมดกับ baseline ว่าตรงกันทุกตัวอักษร ต้องยืนยันด้วย parity run ใน MT5 แบบไม่มี random delay
- **Mode 1:** แท่ง breakout ต้องปิดในช่วง 25% สุดท้ายของแท่งฝั่งที่ทะลุ ถ้าไม่ผ่านจะจบวันนั้น
- **Mode 2 (retest):**
  - break แรกที่ผ่าน half filter จะ arm ทิศไว้และใช้สิทธิ์ one-shot ของวันทันที
  - แท่งที่ปิด**ทีหลัง**และยังอยู่ในหน้าต่าง 15 นาทีต้องแตะระดับที่ทะลุแล้วปิดเลยออกไป จึงเข้า market ด้วย TryEnter เดิม
  - ถ้าแท่งปิดกลับเข้ากรอบ ถือว่าโมฆะทันที ถ้าหมดหน้าต่างถือว่าหมดอายุ
  - pending **ไม่ถูกเก็บข้ามการรีสตาร์ท** ถ้ารีสตาร์ทตอนรออยู่ วันนั้นจะไม่เทรด เพราะ dayDone ถูกเก็บเป็น true ไว้แล้ว ส่วน NewDay จะล้าง pending ก่อน restore
- **Oracle:** `logic_ref.py` เป็นตัวอ้างอิงแบบ causal ประมวลผลทีละแท่งที่ปิดแล้ว ใช้ใน tests เท่านั้น ไม่ใช่ backtest
- **ไม่ได้ทำ:** ไม่ได้รัน sim, ไม่ได้รัน MT5 และไม่ได้ลองพารามิเตอร์อื่น
- **ข้อจำกัด:** ทั้งปี benchmark ถูกเห็นแล้ว จึงไม่มี OOS ที่สะอาด
- **เกณฑ์ตัดสิน (ฝั่งผู้ใช้):** median net ของ 3 รอบ random delay > +$538.42 และ DD ≤ 35% ทุกรอบ จึงจะถือว่าดีกว่าบนปีนี้ ซึ่งไม่ใช่หลักฐานของอนาคต
- **แหล่งไอเดีย:** แนวคิด retest และ close location พบใน phatnomenal/blackXAU_AUTOMATED-BOT-TRADE และ bsAmirHeydar/breakout-micro-following ซึ่งไม่มี LICENSE ที่ root จึงนำมาแค่แนวคิด เขียนโค้ดเองทั้งหมด
- **Attribution:** สเปก ORB จาก anas1412/orb-mt5 @`0301b3e` (MIT)
