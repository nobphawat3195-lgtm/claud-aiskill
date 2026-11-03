# YOUNGYUU · ไล่ทดสอบ indicator ทองทีละตัว

## ไฟล์ในชุดนี้

| ไฟล์ | ใช้กับ | วิธีใช้ |
|---|---|---|
| `00_YOUNGYUU_Signal_Tester.pine` | **ทุกตัวที่ไม่มีโค้ด** (Protected / Invite-only / Open-source ที่ยังไม่ได้ copy) | ใส่ indicator ตัวนั้นลงกราฟก่อน → ใส่ Tester → เลือก plot BUY / SELL → ติ๊ก "เริ่มทดสอบ" |
| `01_SmartAlgoSignals_AlgoChief_YY.pine` | #8 Smart Algo Signals Suite (โฟลเดอร์ 08) | วางทั้งไฟล์ใน Pine Editor → Add to chart (แผงต้นฉบับขวาบน · แผง YY ซ้ายบน) |
| `02_MomentumConfluenceEngine_YY.pine` | #18 Momentum Confluence Engine (โฟลเดอร์ 12) | วางทั้งไฟล์ → Add to chart (ตัว indicator อยู่ pane ล่าง · กล่อง/แผงอยู่บนกราฟราคา) |

> ไฟล์ 01 / 02 มีโค้ดของผู้เขียนต้นฉบับอยู่ข้างใน ใช้ทดสอบส่วนตัวเท่านั้น ห้ามเผยแพร่ต่อ

## ตั้งค่าเหมือนกันทุกตัว (ไม่งั้นเทียบกันไม่ได้)

| หัวข้อ | ค่าที่ใช้ |
|---|---|
| Symbol / TF | OANDA:XAUUSD · M5 (แล้วค่อยลอง M15 กับตัวที่ผ่าน) |
| ช่วงเวลา | ใช้ประวัติเท่าที่กราฟโหลดได้ ช่วงเดียวกันทุกตัว (จดวันที่เริ่ม–จบ) |
| ทุน / lot | $300 · 0.01 lot คงที่ |
| SL / TP | Swing · TP เป็น R · SL ขั้นต่ำ 500 จุด · TP 1·2·3·4·5R |
| ปิดไม้ | แบ่งปิด 20% ทุก TP · ถึง TP1 เลื่อน SL ที่ทุน · มีสัญญาณใหม่ = ถือไม้เดิม |
| ต้นทุน | ค่าคอม $7/lot · spread $0.20 · 1 lot = 100 oz (เช็คกับโบรกจริง) |

## Tester: เลือก plot ยังไง

- เปิด "สัญญาณ BUY จาก" → จะเห็นรายชื่อ plot ของ indicator ที่อยู่บนกราฟ เลือกตัวชื่อประมาณ Buy / Long / Bull / ▲
- "สัญญาณ SELL จาก" → Sell / Short / Bear / ▼
- ถ้า indicator ให้เส้นเดียว (+1 = ซื้อ, −1 = ขาย) เลือก "1 เส้น" แล้วใช้ช่อง BUY ช่องเดียว
- หา plot สัญญาณไม่เจอ = indicator วาดเป็น label อย่างเดียว → ทดสอบด้วย Tester ไม่ได้ จดไว้ว่า "ทดสอบไม่ได้"
- เช็คว่าตรง: ป้าย BUY/SELL ของ YY ต้องขึ้นแท่งเดียวกับสัญญาณของ indicator ถ้าไม่ตรง แปลว่าเลือก plot ผิด

## แต่ละตัวในรายการ ทดสอบด้วยอะไร

| โฟลเดอร์ | ตัว | ทดสอบด้วย |
|---:|---|---|
| 01 | Gold Sniper Confluence | Tester (ถ้ามี plot สัญญาณ) |
| 02 | Breakout & Retest Buy Sell | Tester |
| 03 | Smart Zone Retest | Tester |
| 04 | Trident Swing Projector | Tester |
| 05 | AMD Po3 Live Edge Stats | Tester |
| 06 | Liquidity Master (Protected) | Tester · ถ้าไม่มี plot สัญญาณ = ทดสอบไม่ได้ |
| 07 | EMA RSI Smart Money Zone | Tester |
| 08 | Smart Algo Signals Suite | **ไฟล์ 01** |
| 09 | Supply Demand Pro VWAP | Tester |
| 10 | Setup Scanner GBB | Tester |
| 11 | Harmonic Lab | Tester |
| 12 | Momentum Confluence Engine | **ไฟล์ 02** |
| 13 | Liquidation Reversal Signals | Tester |
| 14 | Key Levels & Sessions Coach | ไม่มีสัญญาณเข้า · ข้าม (ใช้เป็นตัวกรอง) |
| 15 | Gold SMF COT | ไม่มีสัญญาณเข้า · ข้าม |
| 16 | Day Type Radar | ไม่มีสัญญาณเข้า · ข้าม (ใช้เป็นตัวกรอง) |
| 17 | Liquidity Delta Engine 3D | Tester |
| 18 | Order Blocks FVG & BOS | โซน ไม่ใช่สัญญาณ · ข้าม |
| 19 | MarketMind | หาตัวจริงไม่เจอ · ข้าม |

## ตารางจดผล (แคปรูปแผง YY เก็บไว้ทุกตัว)

| # | ชื่อ | TF | ช่วงวันที่ | ไม้ | ชนะ % | PF | ต่อเดือน $ | ลดลงสูงสุด % | แพ้ติดกัน | ผลสรุป |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|
| 08 | Smart Algo Signals | M5 | | | | | | | | |
| 12 | MCE | M5 | | | | | | | | |
| 01 | Gold Sniper Confluence | M5 | | | | | | | | |
| … | | | | | | | | | | |

## เกณฑ์ตัดสิน

1. **ไม้ ≥ 100** ไม่งั้นยังสรุปไม่ได้ (แผงจะขึ้น "รอข้อมูล" ถ้าต่ำกว่า 20)
2. **PF ≥ 1.3** และ **ลดลงสูงสุด < 20%** หลังหักค่าคอม/spread แล้ว
3. ผ่านข้อ 1–2 แล้วจัดอันดับด้วย **PF ก่อน** แล้วดู **ต่อเดือน $**
4. ตัวที่ติด 3 อันดับแรก → ลองซ้ำ M15 และอีกช่วงเวลา ถ้ายังผ่าน ค่อยเอาไปทำ EA / forward test

> ผลทั้งหมดเป็นการจำลองจากแท่งกราฟ (SL ก่อน TP ถ้าแตะในแท่งเดียวกัน) ไม่มี slippage — ใช้เทียบกันเอง ไม่ใช่ผลเทรดจริง
