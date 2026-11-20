# Phase 1 — รายงานตรวจสอบ REA (morluto/rea) เทียบกับงาน EX5/MQL5

วันที่ตรวจ: 2026-10-12 · Commit ที่ตรวจ: `6611bcf6e866` (main, shallow clone) · แพ็กเกจ npm: `rea-agents@6.4.0` (latest ตรงกับ `package.json`) · License: MIT

> สถานะหลักฐาน: **[S]** = อ่านจาก source/docs ใน repo · **[T]** = ทดสอบรันจริงในเครื่องนี้ · **[K]** = ความรู้ทั่วไปของผม ยังไม่ได้ตรวจกับไฟล์จริง (ถือเป็นสมมติฐาน)

## 0. สรุปสั้น

| คำถาม | คำตอบ |
|---|---|
| REA รองรับ EX5 โดยตรงหรือไม่ | **ไม่รองรับ** — มีหลักฐาน [S][T] |
| กู้ MQ5 ต้นฉบับได้ไหม | **ไม่ได้ผ่าน REA** และ REA ไม่ได้ออกแบบมาเพื่อสิ่งนี้ |
| ควรทำต่ออย่างไร | **หยุดแนวทาง "REA → EX5"** แล้วเปลี่ยนเป็นวิเคราะห์พฤติกรรมผ่าน Strategy Tester + วิเคราะห์ MQ5/MQH ที่มีสิทธิ์ (ดูข้อ 8) |

## 1. REA ทำงานอย่างไร [S]

- เป็น CLI + MCP server (Node.js/TypeScript, `bin: rea / rea-agents`) ที่ agent เรียกผ่าน MCP (`npx rea-agents setup` ลงทะเบียน MCP server + skill ให้ Claude Code/Codex/Cursor ฯลฯ และสำรอง config เดิม)
- REA **ไม่ได้ถอดรหัสเอง** สำหรับ native binary — มันเป็น adapter ที่ส่งไฟล์ให้ engine ภายนอก (**Hopper / Ghidra 12.1.x / IDA**) แล้วรวบรวมผลเป็น "Evidence" ที่มีหลักฐานและข้อจำกัดกำกับ
- โมดูลอื่นเป็น static analyzer แยกเอง: JavaScript/Electron, .NET (CIL), APK (ผ่าน JADX), WASM (WABT), EVM bytecode, ELF layout (pwntools), firmware (binwalk/unblob), HAR/เว็บ
- ประมวลผลในเครื่อง; model provider ของ agent ได้รับเฉพาะผลลัพธ์ของ tool (README FAQ "Does REA upload my app?")

## 2. ชนิดไฟล์ที่รองรับ [S]

ตาราง "What you can analyze" ใน README: native binaries (ผ่าน Hopper/Ghidra/IDA), ELF, WASM, EVM, Linux crash, JS/Electron, เว็บ/HAR, .NET, APK/ADB, JEB, firmware, package/resource, process capture
ตัวตรวจ header ที่ใช้เปิดไบนารี: `src/domain/binaryTarget.ts` `parseExecutableHeader` รับเฉพาะ
**ELF (`7f 45 4c 46`), MZ → PE/DOS, Mach-O/FAT (`feedface/feedfacf/cafebabe…`)** นอกนั้นคืน `unsupported binary format`
นอกจากนี้มีโหมด `raw-binary` (ต้องระบุ architecture x86/x86_64/arm/arm64 และ entry point เอง; Ghidra เท่านั้น; Hopper/IDA ปฏิเสธ) — `docs/raw-binary.md`

## 3. หลักฐานเรื่อง EX5 [S][T]

1. `grep -rniE 'ex5|mql4|mql5|metatrader|metaquotes|mt5'` ทั้ง repo (ไม่รวม lockfile/.git) → **0 ไฟล์ที่ตรง** ไม่มีทั้งในโค้ด เอกสาร fixtures และ tests
2. README/ตารางความสามารถ/Roadmap ไม่ระบุ EX5 หรือ MQL เลย
3. ทดสอบจริง: ติดตั้ง `rea-agents@6.4.0` ใน scratchpad (`--ignore-scripts`) แล้วรัน `rea inspect` กับไฟล์สุ่ม 4 KB ที่ตั้งชื่อ `.ex5`
   → exit 1, `code: target_unavailable`, `reason: unsupported binary format`
   **ข้อควรระวัง:** ไฟล์นี้เป็น *ไฟล์สังเคราะห์* ไม่ใช่ EX5 จริง (ผมไม่มี EX5 จริงในเซสชันนี้) จึงพิสูจน์ได้เพียงว่า "ไฟล์ที่ไม่มี magic ของ ELF/PE/Mach-O ถูกปฏิเสธ" ซึ่งสอดคล้องกับข้อ 1 และโค้ด parser — ยังไม่ได้ทดสอบกับ EX5 จริง
4. ห้ามสรุปว่า "รองรับเพราะมี raw-binary" — raw-binary ต้องรู้ CPU/entry/memory map เอง และไม่ได้เข้าใจ container/loader ของ EX5 [S]

ข้อสรุป: **ไม่มีหลักฐานว่า REA รองรับ EX5; มีหลักฐานทางอ้อมว่าไม่รองรับ** และไม่มีแผนใน repo ที่จะรองรับ

## 4. ระดับการวิเคราะห์ EX5 ที่ทำได้

- Functions / Pseudocode / Assembly แบบ Ghidra/Hopper: **ทำไม่ได้โดยตรง** เพราะไฟล์ไม่ผ่านการรับเข้า (ข้อ 3)
- ทางอ้อม (ไม่ยืนยัน): ถ้า EX5 ภายในมี native code ที่ดึงออกมาได้ อาจป้อนเป็น raw-binary ได้ในทางทฤษฎี **[K]** แต่ต้องรู้โครงสร้าง container, การเข้ารหัสของ Market, และมี legal risk (ข้อ 6) — ไม่แนะนำ และผมไม่ได้ตรวจ
- Pseudocode ที่ Ghidra ให้ ไม่ใช่ source ต้นฉบับ (docs/ghidra-provider.md ระบุชัด)

## 5. กู้ MQ5 ต้นฉบับ

REA/Ghidra/Hopper ไม่มีฟีเจอร์ "กู้ source ภาษา MQL5" (ไม่มี symbol/ชื่อตัวแปร/คอมเมนต์/โครงสร้างคลาสจากการ compile) และ repo ไม่มีการกล่าวถึง MQL ดังนั้น **ห้ามอ้างว่ากู้ logic ครบได้**

## 6. ข้อจำกัด / ความเสี่ยง

**เทคนิค [S][T]**
- ต้องมี engine ภายนอกอย่างน้อยหนึ่งตัว: Ghidra 12.1.x + full JDK 21+ (ฟรี), Hopper (เชิงพาณิชย์/มี demo), IDA (เชิงพาณิชย์) — `rea doctor` ในเครื่องนี้รายงาน engine ทั้งสามเป็น missing (ตามคาด)
- Windows: Ghidra รองรับแบบ *experimental P0* — เฉพาะ PE native x86/x86-64 บน NTFS, อ่านอย่างเดียว (`docs/windows-ghidra-p0.md`); Hopper บน Windows ไม่อยู่ในบรรทัดฐานที่รองรับ (baseline: macOS 12+, Ubuntu 24.04+, Fedora 41+, Arch)
- Node.js ^22.19 / ^24.11 / ≥26 (ทดสอบกับ 22.22.0)
- โครงการเปลี่ยนแปลงเร็ว (v6.4.0, commit ล่าสุดคือวันก่อนหน้า) → ต้อง pin เวอร์ชัน

**ความปลอดภัย [S]**
- Dependencies ตรงของ npm 36 แพ็กเกจ (รวม `playwright-core`, `@lydell/node-pty`, `isomorphic-git`) — ผมติดตั้งแบบ `--ignore-scripts` แล้ว 144 แพ็กเกจรวม transitive ยังไม่ได้ audit ช่องโหว่ / ยังไม่ได้ตรวจ supply chain ของ native addon
- `SECURITY.md`: ไม่ใช่ sandbox; การเปิดไบนารีที่ไม่น่าเชื่อถือคือมอบการ parse ให้ Ghidra/Hopper ด้วยสิทธิ์ผู้ใช้ → ถ้าจะวิเคราะห์ไฟล์ไม่ทราบที่มา ควรทำใน VM/เครื่องแยก
- `rea setup` แก้ config ของ agent (มี backup และขออนุมัติ) — ผม **ไม่ได้รัน setup**; เซสชันนี้ไม่มีการเปลี่ยน `~/.claude.json`

**กฎหมาย/สิทธิ์ [K — ไม่ใช่คำปรึกษากฎหมาย]**
- EA จาก MQL5 Market ส่วนใหญ่ถูกป้องกัน/เข้ารหัสและมีข้อตกลงผู้ขาย/EULA ที่อาจห้าม reverse engineering. README ของ REA ระบุว่าผู้ใช้ต้องรับผิดชอบเรื่องสิทธิ์เอง — **ต้องอ่าน EULA ของแต่ละตัวก่อน** ตามข้อกำหนดโปรเจกต์ที่ห้ามถอดรหัสผลิตภัณฑ์ที่ไม่มีสิทธิ์
- ห้ามอัปโหลดไฟล์ EA ไปบริการภายนอก: REA ประมวลผลในเครื่อง แต่ผลลัพธ์ tool จะถูกส่งให้โมเดลของ agent — นับเป็นการส่งข้อมูลออก หากเป็นผลวิเคราะห์ของ EA ที่ซื้อมา

## 7. ต้นทุน

REA (MIT) และ Ghidra/JDK ฟรี; Hopper/IDA เสียเงิน; ค่า token ของ Claude ตามการใช้งาน. ต้นทุนหลักคือเวลา setup และความเสี่ยงทางสิทธิ์ ไม่ใช่ license

## 8. ทางเลือกเมื่อ REA ใช้กับ EX5 ไม่ได้ (เรียงตามความเหมาะสม)

1. **MQ5/MQH ที่มีสิทธิ์**: Claude อ่านวิเคราะห์ตรงๆ — ไม่ต้องใช้ REA (เป็นข้อความธรรมดา)
2. **Black-box behavioral analysis ใน MT5 (ถูกต้องตามสิทธิ์)**: Strategy Tester (Every tick based on real ticks) + Visual mode, ตรวจ Inputs/`.set`, Trade History, Backtest Report (HTML/XML), export deals → วิเคราะห์ entry/exit pattern, ช่วงเวลา, SL/TP/trailing, lot progression, grid/martingale จากสถิติ
3. **EA logger ของเราเอง** (MQL5): ขณะ backtest/demo บันทึก `OnTradeTransaction`, ราคา/spread/ATR/indicator ณ จุดเข้า-ออก ลง CSV เพื่อทำ hypothesis ที่มีหลักฐาน
4. **Ghidra/IDA กับ native PE ของ EA ที่เป็น DLL ภายนอก** (ถ้ามีและได้รับอนุญาต) — ใช้ได้เฉพาะ DLL ไม่ใช่ EX5
5. ตัว decompiler EX5 ของบุคคลที่สาม: **ไม่แนะนำ** (ความถูกต้องไม่ยืนยัน, เสี่ยงมัลแวร์, เสี่ยงละเมิดสิทธิ์) — ผมไม่ได้ประเมิน

## 9. Workflow ที่แนะนำ (ปรับใหม่)

`inventory (hash + magic bytes + metadata) → จัดหมวด (EX5/MQ5/MQH/SET/archive) → MQ5: วิเคราะห์ source | EX5: behavioral analysis ใน Strategy Tester → บันทึกสมมติฐาน+หลักฐาน → ออกแบบ EA ใหม่ → backtest IS/OOS/walk-forward`

## 10. ขั้นตอนทดสอบซ้ำได้ (สิ่งที่ผมรันจริง)

```bash
git clone --depth 1 https://github.com/morluto/rea && cd rea && git rev-parse HEAD   # 6611bcf6e866…
grep -rniE 'ex5|mql4|mql5|metatrader|metaquotes|mt5' --exclude=package-lock.json --exclude-dir=.git .   # → ไม่มีผลลัพธ์
mkdir t && cd t && npm init -y && npm i rea-agents@6.4.0 --ignore-scripts
head -c 4096 /dev/urandom > synthetic.ex5
npx rea inspect "$PWD/synthetic.ex5" --json     # exit 1, unsupported binary format
npx rea doctor --json                           # Hopper/Ghidra/IDA = missing_analysis_engine
```
**ยังไม่ได้ทดสอบ:** ไฟล์ EX5 จริง (ต้องให้ผู้ใช้อนุญาตและนำมาเอง), Windows host, Ghidra จริง, Google Drive

## 11. ข้อเสนอแนะ

- **หยุด** แนวทางใช้ REA กับ EX5 (ไม่มีหลักฐานรองรับ, ความเสี่ยงสิทธิ์สูง, ไม่คุ้ม)
- **ดำเนินโครงการต่อ** ในรูปแบบใหม่ที่ไม่พึ่ง REA: Phase 2 ตรวจ Windows + MT5 + Strategy Tester + MCP; Phase 4 ระบบ inventory/จัดหมวดไฟล์; Phase 5 pipeline วิเคราะห์ backtest
- ถ้าต้องการยืนยัน 100% ว่า REA ปฏิเสธ EX5 จริง ให้ผู้ใช้ **รันคำสั่ง `rea inspect` กับ EX5 จริง 1 ไฟล์ที่ตนมีสิทธิ์** บนเครื่องตัวเอง (ในเครื่อง ไม่อัปโหลด) แล้วส่งเฉพาะข้อความ error กลับมา
- Google Drive: เซสชันนี้มีเครื่องมือ Google Drive connector แต่ **ยังไม่ได้ใช้/ทดสอบ** — จะขออนุญาตก่อนใน Phase 4
