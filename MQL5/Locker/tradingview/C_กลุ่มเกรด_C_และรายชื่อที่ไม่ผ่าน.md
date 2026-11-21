# เกรด C — ผ่าน 2 ปีแต่กำไรมาจากฝั่ง Buy เป็นหลัก (ใช้เป็นตัวกรองทิศ/ฝั่งซื้อได้)

| อินดิเคเตอร์ | ที่มา (ค้นใน TradingView) | TF | R/ไม้ | 2 ปี | สุ่มทิศ 2 ปี | Buy / Sell | หมายเหตุ |
|---|---|---|---|---|---|---|---|
| Hull Suite (HMA 55) | "Hull Suite by InSilico" | H1 | +0.12 / +0.26 | +97R | 99.6% | +108 / −11 | ปีก่อนดีกว่าปีล่าสุด |
| Aroon 14 | built-in "Aroon" | H1 | +0.12 / +0.05 | +66R | 99.3% | +80 / −14 | |
| CCI 20 | built-in "Commodity Channel Index" | H1 | +0.19 / +0.14 | +70R | 96.5% | +81 / −11 | |
| MACD 12/26/9 | built-in "MACD" | H1 | +0.18 / −0.02 | +74R | 98.8% | +80 / −6 | ปีก่อนติดลบ → THUNDER/SENTINEL เทอร์โบพัง |
| MA Cross 9/18 | built-in strategy "MovingAvg2Line Cross" | H1 | +0.08 / +0.15 | +83R | 99.8% | +91 / −7 | สัมพันธ์กับ Coral 0.81 |
| Chande Kroll Stop 10/1/9 | built-in "Chande Kroll Stop" | H1 | +0.11 / +0.10 | +62R | 98.5% | +63 / −1 | |
| Ichimoku 9/26/52 | built-in "Ichimoku Cloud" | H1 | +0.37 / +0.27 | +68R | 95.4% | +72 / −4 | ไม้น้อย 9/เดือน |

R/ไม้ = ปีก่อน / ปีล่าสุด (ข้อมูล M1 bid/ask, กติกาเดียวกันทุกตัว)

## ไม่ผ่าน (ไม่ต้องลองซ้ำ)
UT Bot, SuperTrend, Range Filter, Twin Range, Chandelier, HalfTrend, QQE MOD, Squeeze Momentum, Lorentzian Classification, WaveTrend, Bollinger, RSI2, StochRSI, Donchian, PSAR, Smoothed Heikin Ashi, DMI, Williams Vix Fix, Schaff Trend Cycle, MavilimW (Short ติดลบ), Andean Oscillator, Nadaraya-Watson (jdehorty), RVI, LSMA, Trendilo, McGinley, Laguerre RSI, JMA, TRIX, Alligator, Elder, Fisher, KAMA, T3, Trend Magic, Vortex, Volatility Stop, Keltner, ZLT, PP SuperTrend, AlphaTrend · และทุกอินดิเคเตอร์บน M5 (แม้ใส่ตัวกรอง H4)

### รอบ 8 สาย Scalping (M1/M5/M15, SL 1×ATR, TP 1.5R, 07–20 UTC) — ขาดทุนทั้ง 60 แบบ ไม่มี edge แม้ก่อนหักสเปรด
EMA 9/21 + EMA50, CM Sling Shot 38/62, Stochastic 5/3/3 Pullback, VWAP Cross รายวัน, Bollinger 20/2 Fade, RSI 7 Fade 30/70, SuperTrend 10/3, Keltner 20/1.5 Breakout, NY Opening Range Breakout (13:30–14:00 UTC), London Opening Range Breakout (07:00–08:00 UTC)

### รอบ 9 สาย Scalping รอบ 2 (กติกาเดียวกับรอบ 8) — ไม่ผ่านทั้ง 60 แบบ
Previous Day High/Low Breakout, Turtle Soup, Asian Range Breakout (M15 + กรอง H1 บวก +0.04R แต่ปีแรกติดลบ · edge ก่อนหักสเปรด +0.14R → ใช้แนว ORB ถือนานกว่าแทน), Inside Bar Breakout, Three-Bar Momentum, Volatility Expansion, Pivot S1/R1 Rejection, \$10 Round Number Bounce, Heikin Ashi + EMA200, Williams Fractal Breakout · M1 ติดลบทุกแบบแม้ก่อนหักสเปรด
