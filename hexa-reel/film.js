// XAU HEXA — 30 s explainer reel. Pure function of time: window.seek(t) paints frame t.
// Timing in beats (u) on the measured 124 bpm grid; docs/shotlist.md is the plan this follows.
// Every number on screen comes from assets/hexa_1pct.json (2-year backtest, Cent $300, risk 1%).
import * as M from './lib/motion.js';

const { W, H, FORMAT, E, prog, lerp, clamp, springU, SPRING, wobble, font, layout, glyph, text, fill, cover, rrect, hash01, kf } = M;

const C = {
  bg: '#04050E', deep: '#0E1128', ink: '#E6EBFF', muted: '#8E97C7', line: '#2A2F5A',
  gold: '#FFCD3C', goldDeep: '#6E3C00', up: '#00FFC8', dn: '#FF3A8C', red: '#FF4D6D',
};
const ENG = [
  { n: 'KST', tf: 'H1', d: 'วัดแรงส่งราคา', c: '#00DCFF' },
  { n: 'Coral', tf: 'H1', d: 'เส้นเทรนด์นุ่มลื่น', c: '#FF5AC8' },
  { n: 'Gann', tf: 'H1', d: 'ทะลุกรอบสูง-ต่ำ', c: '#FFCD3C' },
  { n: 'SSL', tf: 'H4', d: 'ยานแม่ · ทิศหลัก', c: '#78FF5A' },
  { n: 'PMO', tf: 'H4', d: 'ชีพจรโมเมนตัม', c: '#FF8C28' },
  { n: 'AO', tf: 'H4', d: 'คลื่นพลังเทรนด์', c: '#AA78FF' },
];
const DISPLAY = 'Display', UI = 'UI';
const P = FORMAT.portrait;
const S = FORMAT.safe;

const HITS = [
  [0, 'number slams', 'impact'],
  [3.25, 'number lands', 'bell', { pitch: 'E6' }],
  [4, 'strike martingale', 'whoosh', { len: 0.25, from: 3000, to: 900 }],
  [5, 'strike grid', 'whoosh', { len: 0.25, from: 3000, to: 900 }],
  [6, 'strike averaging', 'whoosh', { len: 0.25, from: 3000, to: 900 }],
  [7, 'SL every trade', 'pop', { pitch: 'A5' }],
  [8, 'mothership arrives', 'whoosh', { len: 0.6, from: 400, to: 2200 }],
  [9, 'title', 'thud'],
  [12, 'subtitle', 'click'],
  [16, 'engine 1', 'impact'],
  [18, 'engine 2', 'tick'], [20, 'engine 3', 'tick'], [22, 'engine 4', 'tick'], [24, 'engine 5', 'tick'], [26, 'engine 6', 'tick'],
  [28, 'chart', 'sub', { len: 0.6 }],
  [30, 'step 2', 'click'], [32, 'step 3', 'click'], [34, 'step 4', 'click'],
  [36, 'equity', 'whoosh', { len: 0.5, from: 500, to: 2600 }],
  [40, 'year 1', 'pop', { pitch: 'C6' }], [42, 'year 2', 'pop', { pitch: 'E6' }],
  [44, 'truth 1', 'thud'], [46, 'truth 2', 'thud'], [48, 'truth 3', 'thud'],
  [52, 'dashboard', 'whoosh', { len: 0.5, from: 2400, to: 600 }],
  [56, 'end card', 'impact'],
  [57, 'logo', 'bell', { pitch: 'A5' }],
];

// ------------------------------------------------------------------ shared pieces
let DATA = null, CANDLES = null;
const fmtUSD = (v) => '$' + Math.round(v).toLocaleString('en-US');

function stars(ctx, u, drift = 1) {
  for (let i = 0; i < 170; i++) {
    const x = (hash01(i, 3) * W + u * drift * (2 + hash01(i, 9) * 6)) % W;
    const y = hash01(i, 5) * H;
    const tw = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(u * 1.7 + i));
    const s = hash01(i, 7) < 0.08 ? 2.6 : 1.4;
    ctx.globalAlpha = (0.25 + 0.55 * hash01(i, 11)) * tw;
    ctx.fillStyle = '#FFFFFF'; ctx.fillRect(x, y, s, s);
  }
  ctx.globalAlpha = 1;
}
function backdrop(ctx, u, glow = 0.18) {
  fill(ctx, C.bg);
  const g = ctx.createRadialGradient(W * 0.75, H * 0.2, 10, W * 0.75, H * 0.2, Math.max(W, H) * 0.75);
  g.addColorStop(0, `rgba(120,64,255,${glow})`); g.addColorStop(1, 'rgba(4,5,14,0)');
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);
  stars(ctx, u);
}
// Thai strings are drawn whole (combining marks must stay on their base letters).
function line(ctx, s, x, y, size, color, weight = 600, align = 'left', fam = UI) { text(ctx, s, x, y, font(size, weight, fam), color, align); }
function rise(ctx, u, u0, fn, dist = 60, cfg = SPRING.snappy) {
  const k = springU(u, u0, cfg); if (k <= 0.001) return;
  ctx.save(); ctx.globalAlpha = clamp(k * 1.4); ctx.translate(0, (1 - k) * dist); fn(); ctx.restore();
}
function ufo(ctx, x, y, s, u, beam = 0) {
  ctx.save(); ctx.translate(x, y); ctx.scale(s, s);
  if (beam > 0) {
    const g = ctx.createLinearGradient(0, 20, 0, 20 + 520 * beam);
    g.addColorStop(0, 'rgba(120,255,90,0.45)'); g.addColorStop(1, 'rgba(120,255,90,0)');
    ctx.fillStyle = g; ctx.beginPath(); ctx.moveTo(-46, 22); ctx.lineTo(46, 22); ctx.lineTo(150 * beam + 46, 20 + 520 * beam); ctx.lineTo(-150 * beam - 46, 20 + 520 * beam); ctx.fill();
  }
  ctx.fillStyle = '#0A5A50'; ctx.strokeStyle = C.up; ctx.lineWidth = 4;
  ctx.beginPath(); ctx.ellipse(0, -6, 44, 38, 0, Math.PI, 0); ctx.fill(); ctx.stroke();
  ctx.fillStyle = '#78FF5A'; [-14, 14].forEach((ex) => { ctx.beginPath(); ctx.ellipse(ex, -18, 7, 5, 0, 0, Math.PI * 2); ctx.fill(); });
  ctx.fillStyle = '#151A44'; ctx.strokeStyle = '#7840FF'; ctx.lineWidth = 5; ctx.shadowColor = '#7840FF'; ctx.shadowBlur = 30;
  ctx.beginPath(); ctx.ellipse(0, 4, 120, 26, 0, 0, Math.PI * 2); ctx.fill(); ctx.stroke(); ctx.shadowBlur = 0;
  for (let i = 0; i < 6; i++) { const on = Math.floor(u * 2 + i) % 3 === 0; ctx.fillStyle = on ? '#00FF96' : '#2A2F5A'; rrect(ctx, -92 + i * 34, -1, 16, 10, 3); ctx.fill(); }
  ctx.restore();
}
function check(ctx, x, y, s, k, color) {          // drawn check mark (fonts lack ✓)
  ctx.save(); ctx.strokeStyle = color; ctx.lineWidth = s * 0.16; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  ctx.beginPath(); const p = [[x - s * 0.4, y], [x - s * 0.1, y + s * 0.3], [x + s * 0.45, y - s * 0.35]];
  const a = clamp(k * 2), b = clamp(k * 2 - 1);
  ctx.moveTo(...p[0]); ctx.lineTo(lerp(p[0][0], p[1][0], a), lerp(p[0][1], p[1][1], a));
  if (b > 0) ctx.lineTo(lerp(p[1][0], p[2][0], b), lerp(p[1][1], p[2][1], b));
  ctx.stroke(); ctx.restore();
}

// ------------------------------------------------------------------ S1 hook (u 0..4)
function sHook(ctx, u) {
  backdrop(ctx, u);
  const cx = W / 2, cy = P ? H * 0.43 : H * 0.47;
  const big = Math.min(FORMAT.pick({ '9x16': 300, '1x1': 230 }), M.fitSize(ctx, '$10,370', 800, DISPLAY, S.w * 0.98));
  const v = Math.round(300 * (10370 / 300) ** E.outCubic(prog(u, 0.1, 3.2)));
  const str = fmtUSD(v);
  const k = springU(u, -0.15, SPRING.bouncy), sq = 1 + 0.08 * wobble(u * 0.48 - 1.56, 3, 5);
  const out = E.inBack(prog(u, 3.55, 4), 1.6);
  ctx.save(); ctx.translate(cx, cy); ctx.scale(k * (1 - out) * sq, k * (1 - out) / sq);
  ctx.shadowColor = C.gold; ctx.shadowBlur = 14;
  text(ctx, str, 5, 8, font(big, 800, DISPLAY), C.goldDeep, 'center');
  text(ctx, str, 0, 0, font(big, 800, DISPLAY), C.gold, 'center');
  ctx.restore();
  rise(ctx, u, 0.35, () => line(ctx, 'เริ่มต้น $300', cx, cy - big * 0.95, P ? 80 : 60, C.ink, 700, 'center'), 40);
  rise(ctx, u, 0.9, () => {
    const t = 'แบ็กเทส 2 ปี';
    const fs = P ? 64 : 50; ctx.font = font(fs, 700, UI); const w = ctx.measureText(t).width + 70;
    rrect(ctx, cx - w / 2, cy + big * 0.36, w, fs * 1.7, fs); ctx.fillStyle = C.gold; ctx.fill();
    line(ctx, t, cx, cy + big * 0.36 + fs * 1.22, fs, C.bg, 700, 'center');
    line(ctx, 'บัญชี Cent · เสี่ยง 1% ต่อไม้', cx, cy + big * 0.36 + fs * 2.9, P ? 50 : 40, C.muted, 500, 'center');
  }, 40);
}

// ------------------------------------------------------------------ S2 no martingale (u 4..8)
function sNoMarti(ctx, u) {
  backdrop(ctx, u);
  const items = ['Martingale', 'Grid', 'ถัวขาดทุน'];
  const fs = FORMAT.pick({ '9x16': 150, '1x1': 110 }), gap = fs * 1.3;
  const x0 = P ? S.x + 20 : W * 0.12, y0 = P ? H * 0.3 : H * 0.28;
  line(ctx, 'ไม่ใช่ระบบเสี่ยงตาย', x0, y0 - fs * 0.85, P ? 68 : 52, C.muted, 700);
  items.forEach((s, i) => {
    const y = y0 + i * gap + fs * 0.5, k = springU(u, 3.75 + i * 0.12, SPRING.snappy);
    ctx.save(); ctx.globalAlpha = clamp(k); ctx.translate((1 - k) * -80, 0);
    line(ctx, s, x0, y, fs, C.ink, 800, 'left', DISPLAY);
    ctx.font = font(fs, 800, DISPLAY); const w = ctx.measureText(s).width;
    const st = E.outQuint(prog(u, 4 + i, 4.45 + i));
    if (st > 0) {
      ctx.strokeStyle = C.red; ctx.lineWidth = fs * 0.11; ctx.lineCap = 'round'; ctx.shadowColor = C.red; ctx.shadowBlur = 18;
      ctx.beginPath(); ctx.moveTo(x0 - 16, y - fs * 0.32); ctx.lineTo(x0 - 16 + (w + 32) * st, y - fs * 0.32); ctx.stroke(); ctx.shadowBlur = 0;
      ctx.globalAlpha *= 0.6 * st; line(ctx, s, x0, y, fs, C.bg, 800, 'left', DISPLAY);
    }
    ctx.restore();
  });
  const k = springU(u, 7, SPRING.bouncy);
  if (k > 0) {
    const y = y0 + 3 * gap + fs * 0.75, s = fs * 0.75;
    ctx.save(); ctx.translate(x0 + s * 0.5, y - s * 0.3); ctx.scale(k, k); ctx.translate(-(x0 + s * 0.5), -(y - s * 0.3));
    check(ctx, x0 + s * 0.45, y - s * 0.3, s, prog(u, 7, 7.5), C.gold);
    line(ctx, 'มี SL ทุกไม้', x0 + s * 1.2, y, fs * 0.92, C.gold, 800, 'left', DISPLAY);
    ctx.restore();
  }
}

// ------------------------------------------------------------------ S3 mothership (u 8..16)
function sMothership(ctx, u) {
  backdrop(ctx, u, 0.25);
  const k = springU(u, 7.45, SPRING.bouncy);
  const uy = lerp(-200, P ? H * 0.27 : H * 0.24, k) + 8 * Math.sin(u * 1.6);
  const beam = E.outCubic(prog(u, 8.6, 10)) * (1 - E.inCubic(prog(u, 15.2, 16)) * 0);
  ufo(ctx, W / 2, uy, P ? 2.1 : 1.6, u, beam);
  const L = layout(ctx, 'XAU HEXA', font(FORMAT.pick({ '9x16': 190, '1x1': 170 }), 800, DISPLAY), -4);
  const f = font(FORMAT.pick({ '9x16': 190, '1x1': 170 }), 800, DISPLAY);
  const base = P ? H * 0.56 : H * 0.66, x0 = W / 2 - L.width / 2;
  L.glyphs.forEach((g, j) => {
    const kk = springU(u, 9 + j * 0.2, SPRING.bouncy); if (kk <= 0 || g.ch === ' ') return;
    glyph(ctx, g.ch, x0 + g.cx + 4, base + 6 - (1 - kk) * 260, f, C.goldDeep, 1, 1);
    glyph(ctx, g.ch, x0 + g.cx, base - (1 - kk) * 260, f, C.gold, 1, 1);
  });
  rise(ctx, u, 12, () => line(ctx, 'EA ทองคำตามเทรนด์', W / 2, base + (P ? 130 : 100), P ? 76 : 58, C.ink, 700, 'center'), 40);
  rise(ctx, u, 12.5, () => line(ctx, '6 เครื่องยนต์', W / 2, base + (P ? 230 : 172), P ? 76 : 58, C.gold, 800, 'center', DISPLAY), 40);
  rise(ctx, u, 13.5, () => line(ctx, 'XAUUSD · MT5 · แดชบอร์ดภาษาไทย', W / 2, base + (P ? 320 : 236), P ? 48 : 38, C.muted, 500, 'center'), 30);
  const wipe = E.inCubic(prog(u, 15.3, 16));      // beam widens to fill the frame: carries into the engines
  if (wipe > 0) { ctx.fillStyle = `rgba(14,17,40,${wipe})`; ctx.fillRect(0, uy, W, H); }
}

// ------------------------------------------------------------------ S4 six engines (u 16..28)
function sEngines(ctx, u) {
  backdrop(ctx, u);
  const uy = P ? S.y + 40 : 70;
  ufo(ctx, W / 2, uy, P ? 0.9 : 0.6, u, 0);
  line(ctx, '6 เครื่องยนต์ ช่วยกันจับเทรนด์', W / 2, P ? S.y + 170 : 160, P ? 72 : 56, C.ink, 800, 'center', DISPLAY);
  line(ctx, 'H1 = ไม้บ่อย  ·  H4 = จับเทรนด์ใหญ่', W / 2, P ? S.y + 245 : 220, P ? 48 : 38, C.muted, 500, 'center');
  const cols = P ? 2 : 3, gx = P ? 26 : 20, gy = P ? 26 : 22, cw = P ? (S.w - gx) / 2 : (W - 2 * S.x - 2 * gx) / 3, ch = P ? 270 : 300;
  const top = P ? S.y + 300 : 260;
  const fold = E.inCubic(prog(u, 27.3, 28));
  ENG.forEach((e, i) => {
    const r = Math.floor(i / cols), c = i % cols;
    const x = S.x + c * (cw + gx), y = top + r * (ch + gy);
    const k = springU(u, (i ? 16 : 15.7) + i * 2, SPRING.bouncy); if (k <= 0.001) return;
    const sx = W / 2, sy = uy;
    ctx.save();
    const px = lerp(sx - cw / 2, x, k), py = lerp(sy, y, k);
    ctx.translate(px + cw / 2, py + ch / 2); ctx.scale(clamp(k) * (1 - fold * 0.95), clamp(k) * (1 - fold));
    ctx.translate(-cw / 2, -ch / 2);
    rrect(ctx, 0, 0, cw, ch, 22); ctx.fillStyle = C.deep; ctx.fill(); ctx.strokeStyle = e.c; ctx.lineWidth = 4; ctx.stroke();
    ctx.fillStyle = e.c; rrect(ctx, 0, 0, 12, ch, 6); ctx.fill();
    const nf = P ? 84 : 58;
    line(ctx, e.n, 36, 100, nf, e.c, 800, 'left', DISPLAY);
    ctx.font = font(nf, 800, DISPLAY); const nw = ctx.measureText(e.n).width;
    const bw = P ? 88 : 70; rrect(ctx, 46 + nw, P ? 44 : 52, bw, P ? 60 : 48, 12); ctx.fillStyle = e.tf === 'H1' ? '#1A2A55' : '#2A1A55'; ctx.fill();
    line(ctx, e.tf, 46 + nw + bw / 2, P ? 88 : 87, P ? 40 : 32, C.ink, 700, 'center');
    line(ctx, e.d, 36, P ? 180 : 170, P ? 50 : 36, C.ink, 500);
    const fillp = E.outCubic(prog(u, 16.4 + i * 2, 18 + i * 2));
    rrect(ctx, 36, ch - 52, cw - 72, 16, 8); ctx.fillStyle = '#1A1E40'; ctx.fill();
    rrect(ctx, 36, ch - 52, Math.max(16, (cw - 72) * fillp * (0.55 + 0.45 * hash01(i, 4))), 16, 8); ctx.fillStyle = e.c; ctx.fill();
    ctx.restore();
  });
  const yb = top + Math.ceil(6 / cols) * (ch + gy);
  rise(ctx, u, 24.5, () => line(ctx, '~98 ไม้ต่อเดือน', W / 2, P ? yb + 70 : H - 40, P ? 66 : 48, C.gold, 800, 'center', DISPLAY), 30);
}

// ------------------------------------------------------------------ S5 how it works (u 28..36)
function sHow(ctx, u) {
  backdrop(ctx, u, 0.12);
  const box = P ? { x: S.x, y: S.y + 130, w: S.w, h: H * 0.40 } : { x: 40, y: 150, w: W * 0.56, h: H - 230 };
  line(ctx, 'ทำงานยังไง?', P ? W / 2 : 40, P ? S.y + 80 : 100, P ? 76 : 58, C.ink, 800, P ? 'center' : 'left', DISPLAY);
  const n = CANDLES.length, shown = Math.floor(lerp(14, n, E.outCubic(prog(u, 28, 33))));
  const lo = Math.min(...CANDLES.map((c) => c[2])) - 10, hi = Math.max(...CANDLES.map((c) => c[1])) + 10;
  const bw = box.w / n, Y = (v) => box.y + box.h - ((v - lo) / (hi - lo)) * box.h;
  const zoomOut = E.inOutCubic(prog(u, 35.2, 36));
  ctx.save(); ctx.globalAlpha = 1 - zoomOut;
  for (let i = 0; i < shown; i++) {
    const [o, h, l, c] = CANDLES[i], upc = c >= o, x = box.x + i * bw + bw / 2, col = upc ? C.up : C.dn;
    ctx.strokeStyle = col; ctx.lineWidth = 2; ctx.shadowColor = col; ctx.shadowBlur = 8;
    ctx.beginPath(); ctx.moveTo(x, Y(h)); ctx.lineTo(x, Y(l)); ctx.stroke();
    ctx.fillStyle = upc ? '#00786E' : '#6E0050'; const y1 = Y(Math.max(o, c)), y2 = Y(Math.min(o, c));
    ctx.fillRect(x - bw * 0.33, y1, bw * 0.66, Math.max(2, y2 - y1)); ctx.strokeRect(x - bw * 0.33, y1, bw * 0.66, Math.max(2, y2 - y1)); ctx.shadowBlur = 0;
  }
  // entry arrows at real flips (beats 30, 32) and the SL line
  [[22, 1, 30], [58, 1, 32]].forEach(([i, d, ub]) => {
    if (i >= shown) return; const k = springU(u, ub, SPRING.bouncy); if (k <= 0) return;
    const x = box.x + i * bw + bw / 2, y = Y(CANDLES[i][2]) + 30;
    ctx.fillStyle = C.gold; ctx.shadowColor = C.gold; ctx.shadowBlur = 20; ctx.beginPath();
    ctx.moveTo(x, y - (1 - k) * 60); ctx.lineTo(x - 16, y + 26 - (1 - k) * 60); ctx.lineTo(x + 16, y + 26 - (1 - k) * 60); ctx.fill(); ctx.shadowBlur = 0;
  });
  if (u >= 32 && 58 < shown) {
    const slp = E.outCubic(prog(u, 32, 32.8)), y = Y(CANDLES[58][3] - 30);
    ctx.setLineDash([10, 10]); ctx.strokeStyle = C.red; ctx.lineWidth = 3; ctx.beginPath();
    ctx.moveTo(box.x + 58 * bw, y); ctx.lineTo(box.x + 58 * bw + (box.w - 58 * bw) * slp, y); ctx.stroke(); ctx.setLineDash([]);
    line(ctx, 'SL', box.x + 58 * bw + 10, y + 40, 32, C.red, 600);
  }
  ctx.restore();
  const steps = P ? ['รอแท่งเทียนปิด', 'เทรนด์กลับทิศ = เข้าไม้', 'ตั้ง SL ทุกไม้', 'ถือจนเทรนด์จบ ไม่ตั้ง TP'] : ['รอแท่งเทียนปิด', 'กลับทิศ = เข้าไม้', 'ตั้ง SL ทุกไม้', 'ถือจนเทรนด์จบ'];
  const sx = P ? S.x + 10 : W * 0.6, sy = P ? box.y + box.h + 90 : 270, sg = P ? 82 : 170;
  steps.forEach((s, i) => rise(ctx, u, 28 + i * 2, () => {
    ctx.globalAlpha *= 1 - zoomOut;
    const y = sy + i * sg;
    ctx.beginPath(); ctx.arc(sx + 30, y - 18, 30, 0, Math.PI * 2); ctx.fillStyle = C.gold; ctx.fill();
    line(ctx, String(i + 1), sx + 30, y - 2, 40, C.bg, 800, 'center', DISPLAY);
    line(ctx, s, sx + 80, y, P ? 54 : 40, C.ink, 600);
  }, 40));
}

// ------------------------------------------------------------------ S6 equity curve (u 36..44)
function sEquity(ctx, u) {
  backdrop(ctx, u, 0.15);
  const cv = DATA.curve, n = cv.length;
  const box = P ? { x: S.x + 70, y: S.y + 330, w: S.w - 90, h: H * 0.36 } : { x: 140, y: 300, w: W - 200, h: H - 520 };
  const lo = Math.log(220), hi = Math.log(Math.max(...cv) * 1.12);
  const X = (i) => box.x + (i / (n - 1)) * box.w, Y = (v) => box.y + box.h - ((Math.log(v) - lo) / (hi - lo)) * box.h;
  const dp = E.inOutCubic(prog(u, 36, 40.5)), m = Math.max(2, Math.floor(dp * (n - 1)) + 1);
  line(ctx, 'ผลทดสอบ 2 ปี', P ? W / 2 : box.x, P ? S.y + 80 : 110, P ? 76 : 56, C.ink, 800, P ? 'center' : 'left', DISPLAY);
  const cur = cv[m - 1];
  ctx.save(); ctx.shadowColor = C.gold; ctx.shadowBlur = 24;
  text(ctx, fmtUSD(cur), P ? W / 2 : box.x, P ? S.y + 230 : 230, font(P ? 150 : 120, 800, DISPLAY), C.gold, P ? 'center' : 'left'); ctx.restore();
  [300, 1000, 3000, 10000].forEach((v) => {
    ctx.strokeStyle = C.line; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(box.x, Y(v)); ctx.lineTo(box.x + box.w, Y(v)); ctx.stroke();
    line(ctx, v >= 1000 ? `$${v / 1000}k` : `$${v}`, box.x - 14, Y(v) + 12, P ? 36 : 30, C.muted, 500, 'right');
  });
  const g = ctx.createLinearGradient(0, box.y, 0, box.y + box.h); g.addColorStop(0, 'rgba(0,255,200,0.30)'); g.addColorStop(1, 'rgba(0,255,200,0)');
  ctx.beginPath(); ctx.moveTo(X(0), box.y + box.h); for (let i = 0; i < m; i++) ctx.lineTo(X(i), Y(cv[i])); ctx.lineTo(X(m - 1), box.y + box.h); ctx.fillStyle = g; ctx.fill();
  ctx.beginPath(); for (let i = 0; i < m; i++) (i ? ctx.lineTo : ctx.moveTo).call(ctx, X(i), Y(cv[i]));
  ctx.strokeStyle = C.up; ctx.lineWidth = 6; ctx.shadowColor = C.up; ctx.shadowBlur = 16; ctx.stroke(); ctx.shadowBlur = 0;
  const lab = P ? [['ปีแรก', '$300 → $1,713', 40], ['ปีที่สอง', '$300 → $1,815', 42]] : [['ปีแรก', '$300 → $1,713', 40], ['ปีที่สอง', '$300 → $1,815', 42]];
  lab.forEach(([a, b, ub], i) => rise(ctx, u, ub, () => {
    const x = P ? S.x + i * (S.w / 2) + 10 : box.x + i * 560, y = box.y + box.h + (P ? 120 : 120);
    line(ctx, a, x, y - 56, P ? 46 : 36, C.muted, 600);
    line(ctx, b, x, y + 14, P ? 60 : 52, C.ink, 800, 'left', DISPLAY);
  }, 30));
  rise(ctx, u, 40.5, () => line(ctx, 'ระหว่างทางเคยลดลงสูงสุด 46% (DD)', P ? W / 2 : box.x, P ? S.y + 300 : 278, P ? 36 : 30, C.muted, 500, P ? 'center' : 'left'), 15);
  rise(ctx, u, 42.6, () => line(ctx, 'เริ่ม $300 ใหม่ทุกปี · กำไรใกล้กันทั้ง 2 ปี', W / 2, P ? box.y + box.h + 230 : box.y + box.h + 200, P ? 44 : 36, C.gold, 600, 'center'), 20);
}

// ------------------------------------------------------------------ S7 the truth (u 44..52)
function sTruth(ctx, u) {
  backdrop(ctx, u, 0.1);
  line(ctx, 'ทำไม HEXA น่าสนใจ', P ? W / 2 : S.x, P ? S.y + 80 : 130, P ? 72 : 56, C.ink, 800, P ? 'center' : 'left', DISPLAY);
  const F = [['2.3×', 'ไม้ชนะใหญ่กว่าไม้แพ้', 'ไม่ตั้ง TP ปล่อยกำไรวิ่ง', C.gold], ['~98', 'ไม้ต่อเดือน', '6 เครื่องยนต์ทำงานพร้อมกัน', C.up], ['100%', 'มี SL ทุกไม้', 'ไม่ Martingale · ไม่ถัวขาดทุน', C.gold]];
  F.forEach(([v, a, b, col], i) => {
    const y = P ? S.y + 340 + i * 380 : 290 + i * 250, x = P ? S.x + 10 : S.x;
    const k = springU(u, (i ? 44 : 43.7) + i * 2, SPRING.bouncy); if (k <= 0.001) return;
    ctx.save(); ctx.beginPath(); ctx.rect(0, y - 220, W, 260); ctx.clip();
    text(ctx, v, x, y + (1 - k) * 200, font(P ? 200 : 150, 800, DISPLAY), col, 'left');
    ctx.restore();
    rise(ctx, u, 44.3 + i * 2, () => { line(ctx, a, P ? x + 10 : x + 520, P ? y + 80 : y - 70, P ? 58 : 46, C.ink, 700); line(ctx, b, P ? x + 10 : x + 520, P ? y + 150 : y - 12, P ? 46 : 38, C.muted, 500); }, 30);
  });
}

// ------------------------------------------------------------------ S8 dashboard (u 52..56)
function sDash(ctx, u, IMG) {
  backdrop(ctx, u, 0.2);
  const img = IMG.dash; if (!img) return;
  const k = springU(u, 51.8, SPRING.gentle);
  // the dashboard panel is the left ~41% of the screenshot (x 0..1240 of 3000 px); 1x1 keeps some chart
  const srcW = P ? 1240 : 1900, srcH = img.height;
  const boxW = P ? S.w : W - 2 * S.x, boxH = Math.min(P ? S.h - 120 : H - 2 * S.y - 90, boxW * (srcH / srcW));
  const x = (W - boxW) / 2, y = (P ? S.y + 110 : S.y + 70) + (1 - k) * H;
  const z = 1.0 * (1.12 / 1.0) ** E.inOutSine(prog(u, 52, 56));
  ctx.save(); rrect(ctx, x, y, boxW, boxH, 24); ctx.clip();
  const sw = srcW / z, sh = Math.min(srcH, sw * (boxH / boxW)); const sx = (srcW - sw) * 0.3, sy = Math.max(0, (srcH - sh) * 0.15 * (z - 1) / 0.12);
  ctx.drawImage(img, sx, sy, sw, sh, x, y, boxW, boxH); ctx.restore();
  rrect(ctx, x, y, boxW, boxH, 24); ctx.strokeStyle = C.up; ctx.lineWidth = 4; ctx.stroke();
  line(ctx, 'หน้าจอ EA ภาษาไทย', W / 2, (P ? S.y + 70 : S.y + 40), P ? 70 : 50, C.ink, 800, 'center', DISPLAY);
  line(ctx, 'ภาพตัวอย่างหน้าจอ', W / 2, y + boxH + 56, P ? 40 : 32, C.muted, 500, 'center');
}

// ------------------------------------------------------------------ S9 end card (u 56..)
function sEnd(ctx, u) {
  backdrop(ctx, u, 0.28);
  ufo(ctx, W / 2, P ? H * 0.24 : H * 0.18, P ? 1.5 : 1.1, u, 0);
  const f = font(FORMAT.pick({ '9x16': 180, '1x1': 160 }), 800, DISPLAY);
  const L = layout(ctx, 'XAU HEXA', f, -4), base = P ? H * 0.47 : H * 0.48, x0 = W / 2 - L.width / 2;
  L.glyphs.forEach((g, j) => {
    const p = E.outBack(prog(u, 55.7 + j * 0.05, 56.15 + j * 0.05), 1.5); if (p <= 0 || g.ch === ' ') return;
    ctx.save(); ctx.beginPath(); ctx.rect(0, 0, W, base + L.desc + 6); ctx.clip();
    glyph(ctx, g.ch, x0 + g.cx + 4, base + 6 + (1 - p) * (L.asc + 50), f, C.goldDeep);
    glyph(ctx, g.ch, x0 + g.cx, base + (1 - p) * (L.asc + 50), f, C.gold); ctx.restore();
  });
  rise(ctx, u, 56.8, () => line(ctx, 'บัญชี Cent · เสี่ยง 1% ต่อไม้', W / 2, base + (P ? 130 : 100), P ? 62 : 48, C.ink, 700, 'center'), 30);
  rise(ctx, u, 57.3, () => line(ctx, 'ทดลอง Demo ก่อนเสมอ', W / 2, base + (P ? 220 : 168), P ? 62 : 48, C.gold, 800, 'center', DISPLAY), 30);
  rise(ctx, u, 57.8, () => line(ctx, 'ผลแบ็กเทสไม่ใช่การรับประกันกำไร', W / 2, base + (P ? 310 : 228), P ? 44 : 34, C.muted, 500, 'center'), 20);
}

M.film({
  fonts: [font(100, 800, DISPLAY), font(40, 500, UI), font(40, 600, UI), font(40, 700, UI)],
  images: { dash: 'assets/shots/hexa_dashboard_th.png' },
  hits: HITS,
  samples: (t) => (t < 1.65 ? 1 : 16),   // the counting hook stays crisp; everything else gets motion blur
  async init() {
    [DATA, CANDLES] = await Promise.all([fetch('assets/hexa_1pct.json').then((r) => r.json()), fetch('assets/xau_h1_candles.json').then((r) => r.json())]);
  },
  draw(ctx, u, t, IMG) {
    if (u < 4) sHook(ctx, u);
    else if (u < 8) sNoMarti(ctx, u);
    else if (u < 16) sMothership(ctx, u);
    else if (u < 28) sEngines(ctx, u);
    else if (u < 36) sHow(ctx, u);
    else if (u < 44) sEquity(ctx, u);
    else if (u < 52) sTruth(ctx, u);
    else if (u < 56) sDash(ctx, u, IMG);
    else sEnd(ctx, u);
  },
});
