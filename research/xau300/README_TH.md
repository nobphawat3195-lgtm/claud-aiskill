# XAU300 research EAs — คู่มือย่อ (research only)

มี EA สองตัว ทั้งคู่**ใช้วิจัยเท่านั้น** และค่าเริ่มต้น `InpAllowRealAccount=false` ทำให้ปฏิเสธบัญชี REAL ส่วน Strategy Tester และบัญชีเดโมใช้ได้

| EA | logic | สถานะ |
|---|---|---|
| `MQL5/Experts/XAU_300_Research_v1.mq5` (v1.01) | Asia ORB 60 นาที, M5 close, SL อีกฝั่งของกรอบ | MT5 v1.00: P1/P2 ไม่มีไม้, P3 halt (ดู [RESULTS_TH.md](RESULTS_TH.md)) |
| `MQL5/Experts/XAU300_ORB_Research.mq5` (v1.00) | Asia ORB 15 นาที, M1 close, SL ที่จุดกึ่งกลาง (สเปกจาก anas1412/orb-mt5 @0301b3e, MIT) | มีแค่ผล Python ยังไม่มีผล MT5 (ดู [../xau300_orb15/RESULTS_TH.md](../xau300_orb15/RESULTS_TH.md)) |

**ระบบ risk ที่ทั้งสองตัวใช้เหมือนกัน:**
- คำนวณ lot ด้วย `OrderCalcProfit` ปัดลงเป็นจำนวนเต็มของ volume step แล้วตรวจความเสี่ยงซ้ำ ถ้า lot ขั้นต่ำเกิน budget จะข้าม (ไม่บังคับ 0.01)
- ตรวจ margin, stops level, freeze level และ filling mode ส่ง SL/TP ไปกับ order ฝั่ง server
- บล็อกการเข้าไม้ถ้ามี position ใดๆ บน symbol นี้อยู่แล้ว แม้จะเป็นของ EA อื่น
- **Daily hard stop 3%:** ปิดสถานะ (ลองปิดใหม่ทุก tick) และห้ามเข้าไม้จนจบวัน
- **Peak-equity DD stop 20%:** ปิดสถานะ, retry ทุก tick และหยุดถาวรจนกว่าจะ reset
- เก็บ state ข้ามการรีสตาร์ท ได้แก่ peak, halt, วัน, ยอดต้นวัน, daily halt และตัวนับสัญญาณ โดยแยกตาม account, magic และ symbol
- ไม่มี grid, martingale, DLL หรือ network
- **ข้อควรรู้:** เกณฑ์ daily/DD เป็นจุด**สั่งปิด** ไม่ได้รับประกันว่าจะขาดทุนไม่เกินนั้น ถ้าราคากระโดด (gap) หรือ slippage จะเสียเกินได้

**Presets:** มีชุดละ 3 แบบ คือ `safe1` (1%), `balanced2` (2%) และ `aggressive5_RESEARCH_ONLY` (5% เสี่ยงสูง ไม่แนะนำใช้จริง) ทั้งสามต่างกันแค่ RiskPercent และเปิด `InpEquityCsv=true` ไว้
- ORB preset กำหนด spread เป็นหน่วยราคา `InpMaxSpreadPrice=0.60` (USD ต่อ oz) และ `InpServerOffsetMinutes=0` สำหรับ DUKA ที่เป็น UTC ถ้าใช้โบรกเกอร์จริงต้องตั้ง offset เอง
- ที่ 5% ไม้ที่ขาดทุนมักโดน daily stop 3% ปิดก่อนถึง SL

## Equity CSV (เฉพาะใน tester)
- ไฟล์ `server_datetime,balance,equity` บันทึกที่ **tick แรกของทุกนาที** รวมวันที่ halt ด้วย และบังคับเขียนแถวสุดท้ายตอนจบ
- เขียนลง `MQL5/Files` ของ agent จากนั้น runner จะคัดลอกไฟล์ที่เพิ่งสร้างมาไว้เป็น `<report>.equity_m1.csv`
- ตอนพล็อตให้ระบุว่าเป็นค่าที่ sample ทุก M1 ส่วน DD ที่แม่นระดับ tick ให้อ่านจากสรุปในรายงาน MT5
- **ห้ามเรียกกราฟ Balance หรือกราฟจาก Python ว่า Equity**

## คำสั่ง (runner ใช้ได้กับทั้งสอง EA)
```bash
cd research/xau300
python3 -m unittest discover -s tests -v          # 36 tests, stdlib only, ไม่ต้องใช้ MT5

MT5="$HOME/.wine/drive_c/MT5_research"            # โฟลเดอร์ portable เฉพาะงานนี้
EA=XAU300_ORB_Research                            # หรือ XAU_300_Research_v1

python3 mt5_runner.py compile  --ea $EA --terminal-dir "$MT5" --wine wine --dry-run
python3 mt5_runner.py compile  --ea $EA --terminal-dir "$MT5" --wine wine
for p in safe1 balanced2 aggressive5_RESEARCH_ONLY; do
  python3 mt5_runner.py backtest --ea $EA --terminal-dir "$MT5" --wine wine --symbol XAUUSD_DUKA \
          --preset ../../MQL5/Presets/${EA}_$p.set --from 2025.10.31 --to 2026.10.31 --timeout 5400
done
python3 mt5_runner.py parse --report "$MT5/reports/<name>.htm"
```
- ถ้าใช้ไฟล์ .mq5 อื่น ใส่ `--source path/Other.mq5` แทน `--ea` (ชื่อไฟล์ห้ามมี space)
- บน Windows ไม่ต้องใส่ `--wine` และใช้ `python`

**Compile (ตามวิธีที่ยืนยันแล้วว่าใช้ได้บน Wine ในเครื่องผู้ใช้):**
- คัดลอก source ไปไว้ที่ staging ที่ไม่มี space (ค่าเริ่มต้น `C:\MT5stage` คำนวณจาก `.../drive_c/` หรือกำหนดเองด้วย `--stage-dir`)
- ลบ .ex5 และ .log เก่าออกก่อน แล้วรัน `MetaEditor64.exe /portable /compile:C:\MT5stage\Name.mq5 /log:C:\MT5stage\Name.log` โดยไม่มี embedded quotes และใช้ cwd เป็นโฟลเดอร์ terminal
- **ถือว่าสำเร็จเมื่อ** log ใหม่แสดง 0 errors **และ**ได้ .ex5 ใหม่ที่ไม่ว่าง (ไม่ดู exit code เพราะอาจเป็น 1 แม้สำเร็จ) จากนั้นคัดลอก .ex5 ไปที่ `MQL5/Experts/XAU300/`

**Backtest:**
- INI ระบุ `Model=4`, `Deposit=300`, `Currency=USD`, `Leverage=1:500`, `UseLocal=1`, `UseRemote=0`, `UseCloud=0`, `[Experts] AllowLiveTrading=0`, `AllowDllImport=0`
- preset ใส่ใน `[TesterInputs]` พร้อม `InpRunTag` และชื่อ equity CSV ที่ไม่ซ้ำ **ไม่มี Login/Password/Server**
- ถ้ามี terminal จากโฟลเดอร์เดียวกันรันอยู่ จะไม่เริ่มและไม่ปิดให้ เมื่อ timeout จะปิดเฉพาะ process ที่ runner เปิดเอง
- **ตรวจผลหลังรัน:**
  - รายงานต้องสร้างหลังเวลาเริ่มรัน
  - `History Quality` ≥ 99% real ticks (รายงาน HTML ไม่แสดงชื่อ model จึงบันทึก Model=4 จาก INI ไว้ใน json แทน)
  - symbol, deposit และ leverage ตรง
  - `Total Trades` == จำนวน closing deals ที่อ่านได้ และ net จาก deals == Total Net Profit
  - ถ้ารายงานบอกว่ามีไม้แต่อ่าน deals ได้ 0 ถือว่าผิด
  - ต้องมีบรรทัด SUMMARY ที่มี run tag ของรอบนี้ จาก log ที่เพิ่งเขียน และมี equity CSV ใหม่
  - ถ้าข้อใดไม่ผ่าน exit code = 3

## Report parser
แยก orders, deals และ trades ออกจากกัน โดยอ่านแต่ละ section แยกกัน และนับเฉพาะแถวที่หมายเลข Order/Deal เป็นตัวเลข จึงนับ 0 order ได้ถูกต้อง trade ประกอบจาก deals แบบ FIFO รวม partial close, commission, swap และ in/out reversal ส่วน balance DD คำนวณจาก deals และ equity DD อ่านจากรายงาน

## Provenance
- กฎของ v1 มาจากงานวิจัย YY19 family ภายในโปรเจกต์ (เขียนโค้ดใหม่ ไม่คัดลอก source เดิม)
- กฎของ ORB มาจาก [anas1412/orb-mt5](https://github.com/anas1412/orb-mt5) @`0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9` (MIT) แต่เขียนโค้ดใหม่
- แนวทาง MQL5 อ้างอิง [thomaspraun/mql-developer](https://github.com/thomaspraun/mql-developer) (MIT, @3b5e358) โดยไม่ใช้คำแนะนำที่ว่า generated ticks เทียบเท่า real ticks
- **ยังไม่ได้ compile v1.01 และ ORB ใน MT5 จริง** ต้องรอผลจากเครื่องผู้ใช้ เพราะ cloud ไม่มี MetaEditor
