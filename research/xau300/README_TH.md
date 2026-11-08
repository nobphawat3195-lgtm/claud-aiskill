# XAU_300_Research_v1 — คู่มือย่อ (research only)

EA ตัวนี้ใช้ทดสอบเท่านั้น ยังไม่พิสูจน์ว่ามี edge (ดู [RESULTS_TH.md](RESULTS_TH.md)) ห้ามใช้กับเงินจริง
ค่าเริ่มต้น `InpAllowRealAccount=false` ทำให้ EA ปฏิเสธบัญชี REAL ส่วน Strategy Tester และบัญชีเดโมใช้งานได้ปกติ

## ไฟล์
| path | หน้าที่ |
|---|---|
| `MQL5/Experts/XAU_300_Research_v1.mq5` | EA: Asia ORB แบบ closed-bar, sizing ด้วย OrderCalcProfit, เช็ก margin/stops/freeze/filling, SL/TP ฝั่ง server, เปิดได้ครั้งละ 1 ไม้, daily loss 3%, peak-equity DD 20% (เก็บค่าข้ามการรีสตาร์ท), risk 1% |
| `MQL5/Presets/XAU_300_Research_v1_safe1.set` | risk 1% |
| `MQL5/Presets/XAU_300_Research_v1_balanced2.set` | risk 2% |
| `MQL5/Presets/XAU_300_Research_v1_aggressive5_RESEARCH_ONLY.set` | risk 5% **เสี่ยงสูง ใช้วิจัยเท่านั้น ไม่แนะนำ live** |
| `research/xau300/mt5_runner.py` | สั่ง compile และ backtest จาก command line, ตรวจรายงาน |
| `research/xau300/report_parser.py` | อ่านรายงาน MT5 (.htm UTF-16/UTF-8 หรือ .xml) แยก orders/deals/trades และคำนวณสถิติ |
| `research/xau300/sim/` | simulator Python ที่ใช้นิยามกฎของ EA และผลบน Dukascopy M1 |
| `research/xau300/tests/` | unit tests และ static checks |

## สิ่งที่ต้องระบุก่อนรัน
1. **โฟลเดอร์ MT5 แบบ portable ที่ใช้เฉพาะงานนี้** (`--terminal-dir`): ติดตั้ง/คัดลอก MT5 ไปไว้โฟลเดอร์ใหม่ แล้วเปิดด้วย `/portable` อย่างน้อยหนึ่งครั้ง ไม่ต้องล็อกอินบัญชีจริง
2. **ชื่อ symbol** (`--symbol`): เช่น `XAUUSD` หรือชื่อ custom symbol ที่ใส่ Dukascopy real ticks ไว้ ต้องมี tick ครบช่วง 2025-10-01 → 2026-10-31
3. **เวลา server:** กฎใช้เวลา server ถ้า symbol เป็น GMT+0 ใช้ค่าเริ่มต้นได้เลย ถ้าเป็น GMT+2/+3 ต้องแก้ `InpRangeStartHour`, `InpEntryEndHour`, `InpExitHour` ใน .set
4. **Wine** (`--wine wine`): ใส่เฉพาะเมื่อรันบน Linux/macOS บน Windows ไม่ต้องใส่

## คำสั่ง
```bash
cd research/xau300
python3 -m unittest discover -s tests -v                 # tests (ไม่ต้องใช้ MT5)

# ดูไฟล์และคำสั่งที่จะใช้ก่อน โดยยังไม่รันอะไร
python3 mt5_runner.py compile  --terminal-dir "$MT5" --wine wine --dry-run
python3 mt5_runner.py backtest --terminal-dir "$MT5" --wine wine --dry-run \
        --preset ../../MQL5/Presets/XAU_300_Research_v1_safe1.set

# รันจริง
python3 mt5_runner.py compile  --terminal-dir "$MT5" --wine wine
for p in safe1 balanced2 aggressive5_RESEARCH_ONLY; do
  python3 mt5_runner.py backtest --terminal-dir "$MT5" --wine wine --symbol XAUUSD \
          --preset ../../MQL5/Presets/XAU_300_Research_v1_$p.set \
          --from 2025.10.31 --to 2026.10.31 --timeout 5400
done

# อ่านรายงานที่มีอยู่แล้ว
python3 mt5_runner.py parse --report "$MT5/reports/<ชื่อ>.htm" --json out.json

# simulator Python (ต้องมีไฟล์ Dukascopy YYYYMMDD.bi5)
python3 sim/run_preregistered.py --data /path/to/raw_m1
```
บน Windows ให้ใช้ `python` และ `--terminal-dir "C:\MT5_research"` โดยไม่ใส่ `--wine`

## สิ่งที่ runner ทำและไม่ทำ
- เขียนไฟล์ ini ที่ระบุค่าชัดเจน: `Model=4` (real ticks), `Deposit=300`, `Currency=USD`, `Leverage=1:500`, `UseLocal=1`, `UseRemote=0`, `UseCloud=0`, `[Experts] AllowLiveTrading=0`, `AllowDllImport=0` **ไม่มี Login/Password/Server**
- ถ้าสั่ง Model อื่นที่ไม่ใช่ 4 จะปฏิเสธ ยกเว้นใส่ `--allow-non-real-ticks` ซึ่งใช้วิเคราะห์เท่านั้น
- ถ้า preset ตั้ง `InpAllowRealAccount=true` จะปฏิเสธ
- ถ้ามี terminal จากโฟลเดอร์เดียวกันรันอยู่แล้ว จะ**ไม่ปิดให้** แต่แจ้ง error แทน เมื่อหมดเวลา (timeout) จะปิดเฉพาะ process ที่ runner เปิดเองเท่านั้น
- หลังรัน จะหารายงาน `reports/<preset>_<เวลา>.htm|.xml` แล้วตรวจว่า symbol, deposit, leverage, ข้อความ "Every tick based on real ticks" และ History Quality ≥ 99% ถูกต้อง รวมทั้ง net จาก deals ต้องตรงกับ Total Net Profit ในรายงาน ถ้ามีข้อใดไม่ผ่านจะ exit code 3
- อ่านบรรทัด `XAU300|SUMMARY|...` จาก tester log เพื่อนับสัญญาณที่ถูกข้าม เช่น `skip_min_volume`

## ข้อจำกัดที่รู้แล้ว
- สภาพแวดล้อม cloud ที่ใช้เขียนโค้ดนี้ **ไม่มี MetaEditor/MT5** จึงยังไม่เคย compile หรือ backtest จริง ทดสอบได้แค่ static checks ของไฟล์ .mq5 และ unit tests ของ runner/parser/simulator ผล compile และ backtest จริงต้องได้จากเครื่องของผู้ใช้
- ไม่สามารถเปิดเอกสารออนไลน์ของ MT5 ได้ (network บล็อก) รูปแบบ `[Tester]` ใน ini จึงอิงจากรูปแบบที่ MT5 ใช้ทั่วไป ถ้า terminal ไม่สร้างรายงาน ให้ดู `Tester/logs` แล้วส่งกลับมา
- รายงานแบบ .htm ไม่มีคอลัมน์ position id runner จึงประกอบ trade จาก deals แบบ FIFO ต่อ symbol ซึ่งถูกต้องเมื่อ EA เปิดได้ครั้งละ 1 ไม้ตามที่ออกแบบไว้
- ค่า equity DD อ่านจากสรุปในรายงาน MT5 ได้อย่างเดียว ส่วน balance DD คำนวณใหม่จาก deals

## ส่งอะไรกลับมาให้ตรวจ
ไฟล์ `*.summary.json`, รายงาน `.htm`, และ `Tester/logs/*.log` ของแต่ละ preset รวมทั้ง log การ compile (`MQL5/Experts/XAU300/XAU_300_Research_v1.compile.log`)

## Provenance
- กฎ ORB มาจากงานวิจัยในโปรเจกต์ (สรุป YY19 / Doc ภายใน) โค้ด EA และ simulator เขียนขึ้นใหม่ ไม่ได้คัดลอก source เดิม
- อ้างอิงแนวทาง MQL5 (filling, margin, OrderCalcProfit) จาก [thomaspraun/mql-developer](https://github.com/thomaspraun/mql-developer) (MIT, commit 3b5e358) แต่ไม่ใช้คำแนะนำทั่วไปที่ว่า generated ticks เทียบเท่า real ticks
