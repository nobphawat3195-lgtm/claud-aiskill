"""Unit + static tests for both research EAs, the runner, the report parser and the simulators.
Run from research/xau300:  python3 -m unittest discover -s tests -v   (stdlib only, no MT5 needed)"""
import os, re, sys, json, time, tempfile, unittest, datetime as dt, io, contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.abspath(os.path.join(HERE, ".."))
REPO = os.path.abspath(os.path.join(PKG, "..", ".."))
sys.path[:0] = [PKG, os.path.join(PKG, "sim"), os.path.join(REPO, "research", "xau300_orb15", "sim"), HERE]
import report_parser as RP
import mt5_runner as MR
import xau300_sim as S
import orb15_sim as O
import make_fixture as FX

EXPERTS = os.path.join(REPO, "MQL5", "Experts")
PRESET_DIR = os.path.join(REPO, "MQL5", "Presets")
EAS = {"XAU_300_Research_v1": "XAU_300_Research_v1_", "XAU300_ORB_Research": "XAU300_ORB_Research_"}


def presets_for(ea):
    return sorted(os.path.join(PRESET_DIR, f) for f in os.listdir(PRESET_DIR) if f.startswith(EAS[ea]) and f.endswith(".set"))


# ============================================================================ report parser
class ReportParser(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cls.rep = RP.parse_report(FX.write(os.path.join(cls.tmp, "r.htm")))

    def test_counts_kept_apart(self):
        self.assertEqual(self.rep["orders"], FX.EXPECT["orders"])
        self.assertEqual(self.rep["deals"], FX.EXPECT["deals"])
        self.assertEqual(self.rep["out_deals"], 7)
        self.assertEqual(self.rep["balance_deals"], 1)
        self.assertEqual(self.rep["stats"]["trades"], FX.EXPECT["trades"])

    def test_zero_orders_report_counts_zero(self):
        # regression: an empty Orders section used to swallow the Deals header/balance/totals rows (orders=4)
        r = RP.parse_report(FX.write(os.path.join(self.tmp, "z.htm"), FX.build_zero_orders_html()))
        self.assertEqual((r["orders"], r["deals"], r["out_deals"], r["stats"]["trades"]), (0, 0, 0, 0))
        self.assertEqual(r["balance_deals"], 1)
        self.assertEqual(RP.validate(r, "XAUUSD", 300.0, "1:500"), [])

    def test_partial_close_is_one_trade(self):
        t1 = self.rep["trades_list"][0]
        self.assertEqual(t1["partial_exits"], 2)
        self.assertAlmostEqual(t1["net"], 14.42, places=6)
        self.assertEqual(self.rep["stats"]["partial_close_trades"], 1)

    def test_win_loss_breakeven(self):
        st = self.rep["stats"]
        self.assertEqual((st["wins"], st["losses"], st["breakeven"]), (FX.EXPECT["wins"], FX.EXPECT["losses"], FX.EXPECT["breakeven"]))

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
            self.assertEqual(m[k]["trades"], n, k); self.assertAlmostEqual(m[k]["net"], net, places=6)

    def test_reversal_creates_new_trade(self):
        t6 = self.rep["trades_list"][-1]
        self.assertEqual(t6["dir"], -1); self.assertAlmostEqual(t6["net"], 2.0)

    def test_validation_uses_history_quality_not_model_text(self):
        self.assertEqual(RP.validate(self.rep, "XAUUSD", 300.0, "1:500"), [])
        self.assertEqual(len(RP.validate(self.rep, "XAUUSD", 1000.0, "1:100")), 2)
        bad = dict(self.rep); bad["summary"] = dict(self.rep["summary"]); bad["summary"]["History Quality"] = "87%"
        self.assertTrue(any("real ticks" in p for p in RP.validate(bad, "XAUUSD", 300.0, "1:500")))
        bad["summary"].pop("History Quality")
        self.assertTrue(any("History Quality missing" in p for p in RP.validate(bad, "XAUUSD", 300.0, "1:500")))

    def test_validation_exact_trade_count(self):
        bad = dict(self.rep); bad["report_trades"] = 8.0
        self.assertTrue(any("Total Trades 8 != closing deals parsed 7" in p for p in RP.validate(bad)))

    def test_utf8_and_xml_variants(self):
        p = os.path.join(self.tmp, "r8.html")
        with open(p, "w", encoding="utf-8") as f: f.write(FX.build_html())
        self.assertAlmostEqual(RP.parse_report(p)["stats"]["net"], 13.28, places=6)
        x = ['<?xml version="1.0"?><Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"><Worksheet><Table>']
        for k, v in FX.HEAD: x.append(f"<Row><Cell><Data>{k}</Data></Cell><Cell><Data>{v}</Data></Cell></Row>")
        x.append("<Row><Cell><Data>Deals</Data></Cell></Row>")
        x.append("<Row>" + "".join(f"<Cell><Data>{c}</Data></Cell>" for c in
                 ["Time", "Deal", "Symbol", "Type", "Direction", "Volume", "Price", "Order", "Commission", "Swap", "Profit", "Balance", "Comment"]) + "</Row>")
        for d in FX.DEALS: x.append("<Row>" + "".join(f"<Cell><Data>{c}</Data></Cell>" for c in d) + "</Row>")
        x.append("</Table></Worksheet></Workbook>")
        px = os.path.join(self.tmp, "r.xml")
        with open(px, "w", encoding="utf-8") as f: f.write("".join(x))
        rx = RP.parse_report(px)
        self.assertEqual(rx["stats"]["trades"], 6); self.assertAlmostEqual(rx["stats"]["net"], 13.28, places=6)


# ============================================================================ sizing
class Sizing(unittest.TestCase):
    def test_skip_when_min_lot_exceeds_budget(self):
        self.assertEqual(S.lots_for(300.0, 22.7, S.Cfg(risk_pct=1.0)), (0.0, "below_min_volume"))
        self.assertEqual(O.lots_for(300.0, 7.11, O.Cfg(risk_pct=2.0)), (0.0, "below_min_volume"))   # $7.11 > $6

    def test_never_forced_without_parity_switch(self):
        for risk in (1.0, 2.0, 5.0):
            self.assertEqual(S.lots_for(300.0, 40.0, S.Cfg(risk_pct=risk))[0], 0.0)

    def test_parity_switch_reproduces_old_force(self):
        self.assertEqual(S.lots_for(300.0, 15.0, S.Cfg(risk_pct=2.5, force_min_cap=6.0)), (0.01, "forced_min"))

    def test_floor_to_step_including_quarter_steps(self):
        self.assertEqual(S.lots_for(1000.0, 3.0, S.Cfg(risk_pct=2.0)), (0.06, "ok"))          # 0.0666 -> 0.06
        self.assertEqual(O.lots_for(1000.0, 0.3, O.Cfg(risk_pct=2.0, vol_step=0.25, vol_min=0.25)), (0.5, "ok"))  # 0.667 -> 0.50
        self.assertEqual(O.lots_for(1000.0, 1.0, O.Cfg(risk_pct=2.0, vol_step=0.25, vol_min=0.25)), (0.0, "below_min_volume"))


# ============================================================================ simulators
def v1_day():
    """Tuesday: range 98-101 from 00:00-00:59, M5 01:00 bar closes 101.5, then rally to 110."""
    bars, t0 = [], dt.datetime(2026, 1, 6)
    for m in range(60): bars.append((t0 + dt.timedelta(minutes=m), 100.5, 101.0, 98.0, 100.5))
    for m in range(60, 65): bars.append((t0 + dt.timedelta(minutes=m), 101.5, 101.6, 101.4, 101.5))
    for m in range(65, 70): bars.append((t0 + dt.timedelta(minutes=m), 101.5, 101.7, 101.4, 101.6))
    for m in range(70, 80): bars.append((t0 + dt.timedelta(minutes=m), 103.0, 110.0, 102.9, 109.0))
    return bars


def orb_day(day=dt.datetime(2026, 1, 6), last_close=100.8, rally_high=110.0, tail_minutes=200):
    """Range 99-101 (00:00-00:14), last range close sets the half filter, 00:15 bar closes 101.5 (break up)."""
    bars = []
    for m in range(15): bars.append((day + dt.timedelta(minutes=m), 100.0, 101.0, 99.0, last_close if m == 14 else 100.0))
    bars.append((day + dt.timedelta(minutes=15), 100.9, 101.6, 100.9, 101.5))
    for m in range(16, 16 + tail_minutes): bars.append((day + dt.timedelta(minutes=m), 101.6, min(rally_high, 101.7 + (m - 16) * 0.5), 101.55, 101.7))
    return bars


class Simulators(unittest.TestCase):
    def test_v1_breakout_to_take_profit(self):
        r = S.run(v1_day(), {}, S.Cfg(fixed_lot=0.01, daily_loss_pct=0, max_dd_pct=0))
        t = r["trades"][0]
        self.assertEqual((len(r["trades"]), t["dir"], t["reason"]), (1, 1, "TP"))
        self.assertAlmostEqual(t["entry"], 101.78); self.assertAlmostEqual(t["risk"], 3.78); self.assertAlmostEqual(t["r"], 2.0)
        self.assertEqual(t["open"], dt.datetime(2026, 1, 6, 1, 5))

    def test_v1_skip_and_filters(self):
        self.assertEqual(S.run(v1_day(), {}, S.Cfg(risk_pct=0.5))["skips"], {"below_min_volume": 1})
        fri = [(b[0] + dt.timedelta(days=3),) + b[1:] for b in v1_day()]
        self.assertEqual(S.run(fri, {}, S.Cfg(fixed_lot=0.01))["trades"], [])

    def _orb(self, bars, **kw):
        base = dict(fixed_lot=0.01, daily_loss_pct=0, max_dd_pct=0, roll_min_pct=0.0, roll_strict=False)
        base.update(kw)
        return O.run(bars, O.Cfg(**base), bars[0][0], bars[-1][0] + dt.timedelta(minutes=1))

    def test_orb_break_midpoint_sl_tp(self):
        r = self._orb(orb_day())
        t = r["trades"][0]
        self.assertEqual((len(r["trades"]), t["dir"], t["reason"]), (1, 1, "TP"))
        self.assertEqual(t["open"], dt.datetime(2026, 1, 6, 0, 16))            # next bar after the closed 00:15 bar
        self.assertAlmostEqual(t["entry"], 101.6 + 0.28)
        self.assertAlmostEqual(t["risk"], 101.88 - 100.0)                     # SL = midpoint of 99-101
        self.assertAlmostEqual(t["r"], 2.0)

    def test_orb_half_filter_blocks_wrong_half(self):
        r = self._orb(orb_day(last_close=99.5))                                # range closed in the bottom half
        self.assertEqual(r["trades"], [])
        self.assertEqual(list(r["days"].values())[0]["reason"], "half_filter")

    def test_orb_stop_move_then_max_hold(self):
        r = self._orb(orb_day(rally_high=103.0))                               # +0.5R reached, 2R never -> 90 min hold
        t = r["trades"][0]
        self.assertTrue(t["moved"]); self.assertEqual(t["reason"], "hold")
        self.assertEqual(t["close"] - t["open"], dt.timedelta(minutes=90))

    def test_orb_friday_off_and_strict_rolling(self):
        fri = [(b[0] + dt.timedelta(days=3),) + b[1:] for b in orb_day()]
        self.assertEqual(self._orb(fri)["trades"], [])
        r = self._orb(orb_day(), roll_min_pct=0.18, roll_strict=True)          # no history -> no trade
        self.assertEqual(list(r["days"].values())[0]["reason"], "roll_insufficient")

    def test_orb_daily_stop_flattens(self):
        bars = orb_day(tail_minutes=0)
        day = bars[0][0]
        bars += [(day + dt.timedelta(minutes=16 + k), 101.0, 101.1, 100.4, 100.5) for k in range(10)]
        r = self._orb(bars, fixed_lot=0.0, risk_pct=5.0, daily_loss_pct=3.0, deposit=1000.0)
        t = r["trades"][0]
        self.assertEqual(t["reason"], "daily_stop")
        self.assertAlmostEqual(t["pl"], -30.0, places=6)                     # -3% of $1000, no gap


# ============================================================================ runner
class Runner(unittest.TestCase):
    def run_cli(self, *args):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(io.StringIO()):
            code = MR.main(list(args))
        return code, buf.getvalue()

    def test_dry_run_backtest_both_eas(self):
        for ea in EAS:
            code, out = self.run_cli("backtest", "--ea", ea, "--terminal-dir", tempfile.mkdtemp(), "--preset", presets_for(ea)[0], "--dry-run")
            self.assertEqual(code, 0, ea)
            plan = json.loads(out)["backtest"]; ini = plan["ini"]
            for need in ("Model=4", "Deposit=300", "Currency=USD", "Leverage=1:500", "UseCloud=0", "UseRemote=0", "UseLocal=1",
                         "AllowLiveTrading=0", "AllowDllImport=0", "FromDate=2025.10.31", "ToDate=2026.10.31",
                         f"Expert=XAU300\\{ea}", "[TesterInputs]", f"InpRunTag={plan['run_id']}",
                         f"InpEquityFileName={ea}_{plan['run_id']}_equity.csv", "InpEquityCsv=true", "InpAllowRealAccount=false"):
                self.assertIn(need, ini, (ea, need))
            self.assertFalse(any(l.startswith(("Login", "Password", "Server", "ExpertParameters")) for l in ini))

    def test_dry_run_compile_spaces_free_stage_no_quotes(self):
        term = "/home/u/.wine/drive_c/Program Files/MetaTrader 5"
        code, out = self.run_cli("compile", "--ea", "XAU300_ORB_Research", "--terminal-dir", term, "--wine", "wine", "--dry-run")
        plan = json.loads(out)["compile"]
        self.assertEqual(code, 0)
        self.assertEqual(plan["command"][:3], ["wine", os.path.join(term, "MetaEditor64.exe"), "/portable"])
        self.assertIn("/compile:C:\\MT5stage\\XAU300_ORB_Research.mq5", plan["command"])
        self.assertIn("/log:C:\\MT5stage\\XAU300_ORB_Research.log", plan["command"])
        self.assertFalse(any('"' in c for c in plan["command"]))
        self.assertEqual(plan["cwd"], term)
        code, _ = self.run_cli("compile", "--terminal-dir", term, "--wine", "wine", "--stage-dir",
                               "/home/u/.wine/drive_c/my stage", "--dry-run")
        self.assertEqual(code, 1)                                                # spaces in the stage path are refused

    def test_refusals(self):
        p = presets_for("XAU_300_Research_v1")[0]
        self.assertEqual(self.run_cli("backtest", "--terminal-dir", "/tmp/x", "--preset", p, "--model", "1", "--dry-run")[0], 1)
        bad = os.path.join(tempfile.mkdtemp(), "bad.set")
        with open(bad, "w") as f: f.write("InpAllowRealAccount=true\nInpRunTag=\n")
        self.assertEqual(self.run_cli("backtest", "--terminal-dir", "/tmp/x", "--preset", bad, "--dry-run")[0], 1)
        old = os.path.join(tempfile.mkdtemp(), "old.set")
        with open(old, "w") as f: f.write("InpAllowRealAccount=false\nInpRiskPercent=1\n")       # pre-1.01 preset
        self.assertEqual(self.run_cli("backtest", "--terminal-dir", "/tmp/x", "--preset", old, "--dry-run")[0], 1)
        self.assertEqual(self.run_cli("backtest", "--terminal-dir", tempfile.mkdtemp(), "--preset", p)[0], 1)
        self.assertFalse(MR.terminal_running(tempfile.mkdtemp()))

    def test_compile_log_fresh_and_errors(self):
        d = tempfile.mkdtemp()
        ok = os.path.join(d, "ok.log")
        with open(ok, "w", encoding="utf-16") as f: f.write("...\nResult: 0 errors, 0 warnings, 812 msec elapsed\n")
        bad = os.path.join(d, "bad.log")
        with open(bad, "w", encoding="utf-16") as f: f.write("x.mq5(10,3) : error 256\nResult: 3 errors, 0 warnings\n")
        self.assertTrue(MR.parse_compile_log(ok)[0]); self.assertFalse(MR.parse_compile_log(bad)[0])
        self.assertFalse(MR.parse_compile_log(ok, fresh_after=time.time() + 60)[0])          # stale log rejected

    def test_summary_and_equity_csv_only_from_this_run(self):
        term = tempfile.mkdtemp(); logs = os.path.join(term, "Tester", "Agent-127.0.0.1-3000", "logs")
        files = os.path.join(term, "Tester", "Agent-127.0.0.1-3000", "MQL5", "Files")
        os.makedirs(logs); os.makedirs(files)
        old = os.path.join(logs, "20261101.log")
        with open(old, "w", encoding="utf-16") as f: f.write("XAU300|OLDRUN|SUMMARY|signals=9 opened=9\n")
        past = time.time() - 3600; os.utime(old, (past, past))
        t0 = time.time() - 1
        self.assertIsNone(MR.find_ea_summary(term, "NEWRUN", t0))
        with open(os.path.join(logs, "20261108.log"), "w", encoding="utf-16") as f:
            f.write("XAU300|OLDRUN|SUMMARY|signals=9\nXAU300|NEWRUN|SUMMARY|signals=3 opened=1\n")
        self.assertEqual(MR.find_ea_summary(term, "NEWRUN", t0), {"signals": "3", "opened": "1"})
        with open(os.path.join(files, "X_NEWRUN_equity.csv"), "w") as f: f.write("server_datetime,balance,equity\n")
        self.assertTrue(MR.find_equity_csv(term, "X_NEWRUN_equity.csv", t0))
        self.assertIsNone(MR.find_equity_csv(term, "X_OTHER_equity.csv", t0))


# ============================================================================ static checks (both EAs)
def strip_mql(src):
    src = re.sub(r"//[^\n]*", "", src)
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r'"(?:\\.|[^"\\])*"', '""', src)


def func_body(code, name):
    i = code.index(name + "(")
    j = code.index("{", i); depth = 0
    for k in range(j, len(code)):
        depth += code[k] == "{"; depth -= code[k] == "}"
        if depth == 0: return code[j:k + 1]
    raise AssertionError(name)


class StaticEA(unittest.TestCase):
    def each(self):
        for ea in EAS:
            src = open(os.path.join(EXPERTS, ea + ".mq5"), encoding="utf-8").read()
            yield ea, src, strip_mql(src), dict(re.findall(r"^\s*input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);", src, re.M))

    def test_balanced(self):
        for ea, _s, code, _i in self.each():
            for o, c in ("{}", "()", "[]"):
                self.assertEqual(code.count(o), code.count(c), (ea, o + c))

    def test_no_dll_network_credentials_grid(self):
        for ea, _s, code, _i in self.each():
            for bad in ("#import", "WebRequest", "SocketCreate", "SendFTP", "SendMail", "SendNotification", "ShellExecute",
                        "password", "Password", "OrderSendAsync", "BuyLimit", "SellLimit", "BuyStop", "SellStop"):
                self.assertNotIn(bad, code, (ea, bad))
            self.assertNotRegex(code, r"lots\s*\*=", ea)                      # no lot multiplication (martingale)

    def test_file_io_is_tester_only_equity_csv(self):
        for ea, _s, code, _i in self.each():
            self.assertEqual(code.count("FileOpen("), 1, ea)
            body = func_body(code, "void EquityOpen")
            self.assertIn("FileOpen(", body); self.assertIn("MQLInfoInteger(MQL_TESTER)", body)
            self.assertIn("FILE_ANSI", body)
            self.assertIn("EquitySample(false);", func_body(code, "void OnTick").split("\n")[1])   # first statement
            self.assertIn("EquityClose();", func_body(code, "void OnDeinit"))
            self.assertNotIn("FileFlush", code)

    def test_safe_defaults(self):
        for ea, _s, _c, i in self.each():
            self.assertEqual(i["InpAllowRealAccount"].strip(), "false", ea)
            self.assertEqual(float(i["InpRiskPercent"]), 1.0, ea)
            self.assertEqual(float(i["InpDailyLossPct"]), 3.0, ea)
            self.assertEqual(float(i["InpMaxDDPct"]), 20.0, ea)
            self.assertEqual(i["InpEquityCsv"].strip(), "false", ea)

    def test_broker_checks_and_guards(self):
        for ea, src, code, _i in self.each():
            for gv in ('"daybal"', '"dhalt"', '"day"', '"halt"', '"peak"'):              # persisted state names
                self.assertTrue(gv in src, (ea, gv))
            for need in ("OrderCalcProfit", "OrderCalcMargin", "OrderCheck", "SYMBOL_VOLUME_STEP", "SYMBOL_VOLUME_MIN",
                         "SYMBOL_TRADE_TICK_SIZE", "SYMBOL_TRADE_STOPS_LEVEL", "SYMBOL_TRADE_FREEZE_LEVEL",
                         "SYMBOL_FILLING_MODE", "ACCOUNT_TRADE_MODE_REAL", "GlobalVariableSet", "PositionModify",
                         "AnyPositionOnSymbol()", "FlattenMine(", "TRADE_RETCODE_DONE"):
                self.assertTrue(need in code, (ea, need))
            self.assertNotIn("CloseMine", code, ea)
            self.assertNotRegex(code, r"while\s*\(\s*GetMyPosition", ea)       # no unbounded close loops
            self.assertNotIn("MathLog10", code, ea)                             # old step-precision bug
            self.assertIn("(long)MathFloor(v / step + 1e-9)", code, ea)        # integer step units
            self.assertIsNone(re.search(r"lots\s*=\s*vmin\b", code), ea)       # never forced to min lot
            tick = func_body(code, "void OnTick")
            self.assertRegex(tick, r"if\(g_halted\)\s*\{\s*FlattenMine\(\"\"\);\s*return;\s*\}", ea)   # retried every tick
            self.assertRegex(tick, r"if\(g_dailyHalt\)\s*\{\s*FlattenMine\(\"\"\);\s*return;\s*\}", ea)
            self.assertIn("AnyPositionOnSymbol()", func_body(code, "void TryEnter"))

    def test_closed_bar_signals_only(self):
        for ea, _s, code, _i in self.each():
            self.assertIsNone(re.search(r"i(Close|High|Low)\(\s*_Symbol\s*,\s*\w+\s*,\s*0\s*\)", code), ea)
        v1 = strip_mql(open(os.path.join(EXPERTS, "XAU_300_Research_v1.mq5")).read())
        self.assertIn("iClose(_Symbol, InpSignalTF, 1)", v1)
        orb = strip_mql(open(os.path.join(EXPERTS, "XAU300_ORB_Research.mq5")).read())
        self.assertIn("CopyRates(_Symbol, PERIOD_M1, 1, 1, b)", orb)

    def test_sl_tp_sent_with_order(self):
        for ea, _s, code, _i in self.each():
            self.assertRegex(code, r"g_trade\.Buy\(lots, _Symbol, 0\.0, sl, tp", ea)
            self.assertRegex(code, r"g_trade\.Sell\(lots, _Symbol, 0\.0, sl, tp", ea)

    def test_versions_and_attribution(self):
        v1 = open(os.path.join(EXPERTS, "XAU_300_Research_v1.mq5")).read()
        self.assertIn('#property version   "1.01"', v1)
        orb = open(os.path.join(EXPERTS, "XAU300_ORB_Research.mq5")).read()
        self.assertIn("0301b3ed4ba3aa53d00459e0e6e565aa3e71d5a9", orb); self.assertIn("MIT", orb)

    def test_presets_match_inputs(self):
        for ea, _s, _c, inputs in self.each():
            ps = presets_for(ea)
            self.assertEqual(len(ps), 3, ea)
            risks = {}
            for p in ps:
                items = dict(MR.read_set(p))
                self.assertEqual(set(items), set(inputs), os.path.basename(p))
                self.assertEqual(items["InpAllowRealAccount"], "false"); self.assertEqual(items["InpRunTag"], "")
                risks[os.path.basename(p)] = float(items["InpRiskPercent"])
                for k, v in items.items():
                    if k in ("InpRiskPercent", "InpEquityCsv"): continue           # sizing + research export only
                    dv = inputs[k].strip().strip('"')
                    if k == "InpSignalTF": dv = "5" if dv == "PERIOD_M5" else dv
                    self.assertEqual(str(v).lower(), dv.lower(), f"{os.path.basename(p)}:{k}")
                self.assertEqual(items["InpEquityCsv"], "true")
            self.assertEqual(sorted(risks.values()), [1.0, 2.0, 5.0], ea)
            self.assertTrue(any("RESEARCH_ONLY" in n for n, r in risks.items() if r == 5.0), ea)
        orb = dict(MR.read_set(presets_for("XAU300_ORB_Research")[0]))
        self.assertEqual(orb["InpMaxSpreadPrice"], "0.60"); self.assertEqual(orb["InpServerOffsetMinutes"], "0")


if __name__ == "__main__":
    unittest.main()
