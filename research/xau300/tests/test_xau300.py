"""Unit + static tests for the XAU_300_Research_v1 package. Run:  python -m unittest discover -s tests -v"""
import os, re, sys, json, tempfile, unittest, datetime as dt, io, contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(PKG, "..", ".."))
sys.path[:0] = [PKG, os.path.join(PKG, "sim"), HERE]
import report_parser as RP
import mt5_runner as MR
import xau300_sim as S
import make_fixture as FX

EA = os.path.join(REPO, "MQL5", "Experts", "XAU_300_Research_v1.mq5")
PRESETS = [os.path.join(REPO, "MQL5", "Presets", f) for f in os.listdir(os.path.join(REPO, "MQL5", "Presets"))
           if f.startswith("XAU_300_Research_v1")]


class ReportParser(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.path = FX.write(os.path.join(cls.tmp, "r.htm"))
        cls.rep = RP.parse_report(cls.path)

    def test_counts_kept_apart(self):
        self.assertEqual(self.rep["orders"], FX.EXPECT["orders"])
        self.assertEqual(self.rep["deals"], FX.EXPECT["deals"])
        self.assertEqual(self.rep["balance_deals"], 1)
        self.assertEqual(self.rep["stats"]["trades"], FX.EXPECT["trades"])

    def test_partial_close_is_one_trade(self):
        t1 = self.rep["trades_list"][0]
        self.assertEqual(t1["partial_exits"], 2)
        self.assertAlmostEqual(t1["net"], 14.42, places=6)
        self.assertEqual(self.rep["stats"]["partial_close_trades"], 1)

    def test_win_loss_breakeven(self):
        st = self.rep["stats"]
        self.assertEqual((st["wins"], st["losses"], st["breakeven"]),
                         (FX.EXPECT["wins"], FX.EXPECT["losses"], FX.EXPECT["breakeven"]))

    def test_costs_and_net(self):
        st = self.rep["stats"]
        self.assertAlmostEqual(st["net"], FX.EXPECT["net"], places=6)
        self.assertAlmostEqual(st["commission"], FX.EXPECT["commission"], places=6)
        self.assertAlmostEqual(st["swap"], FX.EXPECT["swap"], places=6)
        self.assertAlmostEqual(st["final_balance_from_deals"], 313.28, places=6)

    def test_balance_drawdown(self):
        st = self.rep["stats"]
        self.assertAlmostEqual(st["balance_dd_money"], FX.EXPECT["balance_dd_money"], places=6)
        self.assertAlmostEqual(st["balance_dd_pct"], FX.EXPECT["balance_dd_pct"], places=6)
        self.assertAlmostEqual(self.rep["report_equity_dd_pct"], 3.01)

    def test_monthly(self):
        m = self.rep["stats"]["monthly"]
        for k, (n, net) in FX.EXPECT["monthly"].items():
            self.assertEqual(m[k]["trades"], n, k)
            self.assertAlmostEqual(m[k]["net"], net, places=6)

    def test_reversal_creates_new_trade(self):
        t6 = self.rep["trades_list"][-1]
        self.assertEqual(t6["dir"], -1)
        self.assertAlmostEqual(t6["net"], 2.0)

    def test_validation_passes_and_catches_mismatch(self):
        self.assertEqual(RP.validate(self.rep, "XAUUSD", 300.0, "1:500", "Every tick based on real ticks"), [])
        probs = RP.validate(self.rep, "XAUUSD", 1000.0, "1:100", "Open prices only")
        self.assertEqual(len(probs), 3)

    def test_utf8_and_xml_variants(self):
        p = os.path.join(self.tmp, "r8.html")
        open(p, "w", encoding="utf-8").write(FX.build_html())
        self.assertAlmostEqual(RP.parse_report(p)["stats"]["net"], 13.28, places=6)
        x = ['<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet><Table>']
        for k, v in FX.HEAD: x.append(f"<Row><Cell><Data>{k}</Data></Cell><Cell><Data>{v}</Data></Cell></Row>")
        x.append("<Row><Cell><Data>Deals</Data></Cell></Row>")
        x.append("<Row>" + "".join(f"<Cell><Data>{c}</Data></Cell>" for c in
                 ["Time", "Deal", "Symbol", "Type", "Direction", "Volume", "Price", "Order", "Commission", "Swap", "Profit", "Balance", "Comment"]) + "</Row>")
        for d in FX.DEALS: x.append("<Row>" + "".join(f"<Cell><Data>{c}</Data></Cell>" for c in d) + "</Row>")
        x.append("</Table></Worksheet></Workbook>")
        px = os.path.join(self.tmp, "r.xml"); open(px, "w", encoding="utf-8").write("".join(x))
        rx = RP.parse_report(px)
        self.assertEqual(rx["stats"]["trades"], 6); self.assertAlmostEqual(rx["stats"]["net"], 13.28, places=6)


class Sizing(unittest.TestCase):
    def test_skip_when_min_lot_exceeds_budget(self):
        cfg = S.Cfg(risk_pct=1.0)
        lots, why = S.lots_for(300.0, 22.7, cfg)          # median 1R on 2026 gold: 0.01 lot loses $22.7 > $3
        self.assertEqual((lots, why), (0.0, "below_min_volume"))

    def test_never_forced_without_parity_switch(self):
        for risk in (1.0, 2.0, 5.0):
            lots, _ = S.lots_for(300.0, 40.0, S.Cfg(risk_pct=risk))
            self.assertEqual(lots, 0.0)

    def test_parity_switch_reproduces_old_force(self):
        lots, why = S.lots_for(300.0, 15.0, S.Cfg(risk_pct=2.5, force_min_cap=6.0))
        self.assertEqual((lots, why), (0.01, "forced_min"))

    def test_floor_to_step(self):
        lots, why = S.lots_for(1000.0, 3.0, S.Cfg(risk_pct=2.0))   # 20 / 300 = 0.0666 -> 0.06
        self.assertEqual((lots, why), (0.06, "ok"))


def synthetic_day(spread=0.28):
    """Tuesday: range 98-101 from 00:00-00:59, M5 01:00 bar closes 101.5, then rally to 110."""
    bars, t0 = [], dt.datetime(2026, 1, 6)
    for m in range(60):
        bars.append((t0 + dt.timedelta(minutes=m), 100.5, 101.0, 98.0, 100.5))
    for m in range(60, 65):
        bars.append((t0 + dt.timedelta(minutes=m), 101.5, 101.6, 101.4, 101.5))
    for m in range(65, 70):
        bars.append((t0 + dt.timedelta(minutes=m), 101.5, 101.7, 101.4, 101.6))
    for m in range(70, 80):
        bars.append((t0 + dt.timedelta(minutes=m), 103.0, 110.0, 102.9, 109.0))
    return bars


class Simulator(unittest.TestCase):
    def test_breakout_to_take_profit(self):
        cfg = S.Cfg(fixed_lot=0.01, daily_loss_pct=0, max_dd_pct=0)
        r = S.run(synthetic_day(), {}, cfg)
        self.assertEqual(len(r["trades"]), 1)
        t = r["trades"][0]
        self.assertEqual((t["dir"], t["reason"]), (1, "TP"))
        self.assertAlmostEqual(t["entry"], 101.5 + 0.28)                  # next M5 open + spread
        self.assertAlmostEqual(t["risk"], 101.78 - 98.0)                  # SL = range low
        self.assertAlmostEqual(t["r"], 2.0)
        self.assertEqual(t["open"], dt.datetime(2026, 1, 6, 1, 5))       # closed-bar signal, no lookahead

    def test_skip_logged_when_budget_too_small(self):
        r = S.run(synthetic_day(), {}, S.Cfg(risk_pct=0.5))              # $1.5 budget < $3.78 loss of 0.01 lot
        self.assertEqual(r["trades"], [])
        self.assertEqual(r["skips"], {"below_min_volume": 1})

    def test_friday_and_kill_filter(self):
        fri = [(b[0] + dt.timedelta(days=3),) + b[1:] for b in synthetic_day()]
        self.assertEqual(S.run(fri, {}, S.Cfg(fixed_lot=0.01))["trades"], [])
        low = {dt.date(2026, 1, 6) - dt.timedelta(days=k): 1.0 for k in range(1, 25)}
        self.assertEqual(S.run(synthetic_day(), low, S.Cfg(fixed_lot=0.01))["trades"], [])


class Runner(unittest.TestCase):
    def run_cli(self, *args):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            code = MR.main(list(args))
        return code, buf.getvalue()

    def test_dry_run_ini_is_safe_and_explicit(self):
        code, out = self.run_cli("backtest", "--terminal-dir", tempfile.mkdtemp(), "--preset", PRESETS[0], "--dry-run")
        self.assertEqual(code, 0)
        ini = json.loads(out)["backtest"]["ini"]
        for need in ("Model=4", "Deposit=300", "Currency=USD", "Leverage=1:500", "UseCloud=0", "UseRemote=0",
                     "AllowLiveTrading=0", "AllowDllImport=0", "FromDate=2025.10.31", "ToDate=2026.10.31", "Symbol=XAUUSD"):
            self.assertIn(need, ini)
        self.assertFalse(any(l.startswith(("Login", "Password", "Server")) for l in ini))

    def test_wine_dry_run_uses_wine(self):
        code, out = self.run_cli("backtest", "--terminal-dir", "/tmp/mt5x", "--wine", "wine", "--preset", PRESETS[0], "--dry-run")
        self.assertEqual(json.loads(out)["backtest"]["command"][0], "wine")
        code, out = self.run_cli("compile", "--terminal-dir", "/tmp/mt5x", "--wine", "wine", "--dry-run")
        self.assertIn("/compile:", " ".join(json.loads(out)["compile"]["command"]))

    def test_refuses_non_real_ticks_and_real_presets(self):
        code, _ = self.run_cli("backtest", "--terminal-dir", "/tmp/x", "--preset", PRESETS[0], "--model", "1", "--dry-run")
        self.assertEqual(code, 1)
        bad = os.path.join(tempfile.mkdtemp(), "bad.set")
        open(bad, "w").write("InpAllowRealAccount=true\nInpRiskPercent=1\n")
        code, _ = self.run_cli("backtest", "--terminal-dir", "/tmp/x", "--preset", bad, "--dry-run")
        self.assertEqual(code, 1)

    def test_missing_terminal_is_an_error_not_a_kill(self):
        code, _ = self.run_cli("backtest", "--terminal-dir", tempfile.mkdtemp(), "--preset", PRESETS[0])
        self.assertEqual(code, 1)
        self.assertFalse(MR.terminal_running(tempfile.mkdtemp()))

    def test_compile_log_parser(self):
        d = tempfile.mkdtemp()
        ok = os.path.join(d, "ok.log"); open(ok, "w", encoding="utf-16").write("...\nResult: 0 errors, 2 warnings, 812 msec elapsed\n")
        bad = os.path.join(d, "bad.log"); open(bad, "w", encoding="utf-16").write("x.mq5(10,3) : error 256\nResult: 3 errors, 0 warnings\n")
        self.assertTrue(MR.parse_compile_log(ok)[0]); self.assertFalse(MR.parse_compile_log(bad)[0])


def strip_mql(src):
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', src)


class StaticEA(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = open(EA, encoding="utf-8").read()
        cls.code = strip_mql(cls.src)
        cls.inputs = dict(re.findall(r"^\s*input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);", cls.src, re.M))

    def test_balanced(self):
        for o, c in ("{}", "()", "[]"):
            self.assertEqual(self.code.count(o), self.code.count(c), o + c)

    def test_no_dll_network_credentials(self):
        for bad in ("#import", "WebRequest", "SocketCreate", "SendFTP", "SendMail", "SendNotification", "FileOpen",
                    "password", "Password", "ShellExecute"):
            self.assertNotIn(bad, self.code, bad)

    def test_safe_defaults(self):
        i = {k: v.strip() for k, v in self.inputs.items()}
        self.assertEqual(i["InpAllowRealAccount"], "false")
        self.assertEqual(float(i["InpRiskPercent"]), 1.0)
        self.assertEqual(float(i["InpDailyLossPct"]), 3.0)
        self.assertEqual(float(i["InpMaxDDPct"]), 20.0)

    def test_required_broker_checks_present(self):
        for need in ("OrderCalcProfit", "OrderCalcMargin", "OrderCheck", "SYMBOL_VOLUME_STEP", "SYMBOL_VOLUME_MIN",
                     "SYMBOL_TRADE_TICK_SIZE", "SYMBOL_TRADE_STOPS_LEVEL", "SYMBOL_TRADE_FREEZE_LEVEL",
                     "SYMBOL_FILLING_MODE", "ACCOUNT_TRADE_MODE_REAL", "GlobalVariableSet", "PositionModify"):
            self.assertIn(need, self.code, need)

    def test_no_min_lot_forcing_and_no_lookahead(self):
        self.assertIsNone(re.search(r"lots\s*=\s*vmin\b", self.code))
        self.assertIsNone(re.search(r"i(Close|High|Low)\(\s*_Symbol\s*,\s*InpSignalTF\s*,\s*0\s*\)", self.code))
        self.assertIn("iClose(_Symbol, InpSignalTF, 1)", self.code)

    def test_sl_tp_sent_with_order(self):
        self.assertRegex(self.code, r"g_trade\.Buy\(lots, _Symbol, 0\.0, sl, tp")
        self.assertRegex(self.code, r"g_trade\.Sell\(lots, _Symbol, 0\.0, sl, tp")

    def test_presets_match_inputs(self):
        self.assertEqual(len(PRESETS), 3)
        risks = {}
        for p in PRESETS:
            items = dict(MR.read_set(p))
            self.assertEqual(set(items), set(self.inputs), os.path.basename(p))
            self.assertEqual(items["InpAllowRealAccount"], "false")
            risks[os.path.basename(p)] = float(items["InpRiskPercent"])
            # only RiskPercent may differ from the EA defaults
            for k, v in items.items():
                if k == "InpRiskPercent": continue
                dv = self.inputs[k].strip().strip('"')
                if k == "InpSignalTF": dv = "5" if dv == "PERIOD_M5" else dv
                self.assertEqual(str(v).lower(), dv.lower(), f"{os.path.basename(p)}:{k}")
        self.assertEqual(sorted(risks.values()), [1.0, 2.0, 5.0])
        self.assertTrue(any("RESEARCH_ONLY" in n for n, r in risks.items() if r == 5.0))


if __name__ == "__main__":
    unittest.main()
