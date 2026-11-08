#!/usr/bin/env python3
"""
mt5_runner.py — compile + MT5 Strategy Tester (real ticks) from the command line, for either EA:
  --ea XAU_300_Research_v1 | XAU300_ORB_Research   (or --source path/to/Other.mq5)
Works on Windows (native) or Linux/macOS + Wine. Uses a DEDICATED PORTABLE terminal folder.

Compile (method verified on the user's Wine setup):
  the source is copied into a SPACES-FREE staging folder (default C:\\MT5stage), old .ex5/.log there are deleted,
  then   MetaEditor64.exe /portable /compile:C:\\MT5stage\\Name.mq5 /log:C:\\MT5stage\\Name.log
  (no embedded quotes). Success = a FRESH log with "0 errors" AND a FRESH non-empty .ex5; MetaEditor's exit code is
  ignored (it can be 1 on success). The .ex5 is then copied to <terminal>/MQL5/Experts/XAU300/.

Backtest: writes an INI with [Tester] Model=4, Deposit, Currency, Leverage, UseLocal=1, UseRemote=0, UseCloud=0 and the
preset in [TesterInputs] (+ a unique InpRunTag and equity CSV name). No Login/Password/Server is ever written;
[Experts] AllowLiveTrading=0, AllowDllImport=0. Only the process this script starts is terminated on timeout;
if a terminal from the same folder already runs, the script refuses to start.
After the run it requires: a report created after the start, History Quality >= 99% real ticks, deposit/leverage/
symbol match, Total Trades == closing deals parsed, net from deals == report net, the EA SUMMARY line carrying this
run's tag, and (if enabled in the preset) a fresh equity CSV, which is copied next to the report.
"""
import argparse, json, os, re, shutil, subprocess, sys, time, uuid, datetime as dt

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
EXPERTS = os.path.join(REPO, "MQL5", "Experts")
KNOWN_EAS = {"XAU_300_Research_v1": "XAU300", "XAU300_ORB_Research": "XAU300ORB",
             "XAU300_ORB_CappedRecovery_Research": "XAU300ORBCR"}   # name -> log prefix
EA_SUBDIR = "XAU300"


class RunnerError(Exception):
    pass


# ----------------------------------------------------------------------------- paths
def to_win_path(p, use_wine):
    """Path as the Windows program sees it. Under Wine, '<prefix>/drive_c/x' -> 'C:\\x'; else winepath; else Z:."""
    p = os.path.abspath(p)
    if not use_wine:
        return p
    m = re.search(r"/drive_c/(.*)$", p.replace("\\", "/"))
    if m:
        return "C:\\" + m.group(1).replace("/", "\\")
    wp = shutil.which("winepath")
    if wp:
        try:
            return subprocess.check_output([wp, "-w", p], text=True, stderr=subprocess.DEVNULL).strip()
        except Exception:
            pass
    return "Z:" + p.replace("/", "\\")


def default_stage_dir(terminal_dir, use_wine):
    t = os.path.abspath(terminal_dir).replace("\\", "/")
    if use_wine:
        m = re.search(r"^(.*?/drive_c)/", t + "/")
        if not m:
            raise RunnerError("cannot derive a C:\\ staging folder from --terminal-dir; pass --stage-dir <prefix>/drive_c/MT5stage")
        return os.path.join(m.group(1), "MT5stage")
    if os.name == "nt":
        return "C:\\MT5stage"
    return os.path.join(os.path.dirname(os.path.abspath(terminal_dir)), "MT5stage")


def exe_cmd(exe, args, wine):
    return ([wine, exe] if wine else [exe]) + args


def resolve_ea(a):
    if getattr(a, "source", None):
        src = os.path.abspath(a.source)
        name = os.path.splitext(os.path.basename(src))[0]
    else:
        name = a.ea
        src = os.path.join(EXPERTS, name + ".mq5")
    if " " in name:
        raise RunnerError("EA file name must not contain spaces")
    return name, src


def terminal_running(terminal_dir):
    """Best effort: is a terminal64.exe from THIS folder already running? (never kills anything)"""
    target = os.path.abspath(terminal_dir).lower()
    if os.name == "nt":
        try:
            out = subprocess.check_output(["powershell", "-NoProfile", "-Command",
                                           "Get-CimInstance Win32_Process -Filter \"Name='terminal64.exe'\" | ForEach-Object { $_.ExecutablePath }"],
                                          text=True, stderr=subprocess.DEVNULL)
            return any(target.replace("/", "\\") in l.strip().lower() for l in out.splitlines() if l.strip())
        except Exception:
            return False
    found = False
    for pid in (os.listdir("/proc") if os.path.isdir("/proc") else []):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as fh:
                cmd = fh.read().replace(b"\0", b" ").decode("utf-8", "ignore").lower()
        except Exception:
            continue
        if "terminal64.exe" in cmd and (target in cmd or target.replace("/", "\\") in cmd):
            found = True
    return found


def read_text(path):
    with open(path, "rb") as fh:
        raw = fh.read()
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16", "ignore")
    if len(raw) > 1 and raw[1:2] == b"\x00":
        return raw.decode("utf-16-le", "ignore")
    return raw.decode("utf-8", "ignore")


# ----------------------------------------------------------------------------- presets / ini
def read_set(path):
    """Read a .set file (UTF-16 or UTF-8). Returns ordered list of (key, value)."""
    txt = read_text(path)
    items = []
    for line in txt.splitlines():
        line = line.strip()
        if not line or line.startswith(";") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        items.append((k.strip(), v.split("||")[0].strip()))
    return items


def check_preset_safety(items):
    d = dict(items)
    if d.get("InpAllowRealAccount", "false").lower() not in ("false", "0"):
        raise RunnerError("preset sets InpAllowRealAccount=true; the runner only runs research presets")
    return d


def build_ini(a, ea_name, inputs, report_rel):
    lines = ["; generated by mt5_runner.py - no credentials on purpose", "[Experts]", "AllowLiveTrading=0",
             "AllowDllImport=0", "Enabled=1", "", "[Tester]",
             f"Expert={EA_SUBDIR}\\{ea_name}", f"Symbol={a.symbol}", f"Period={a.period}", f"Model={a.model}",
             f"ExecutionMode={a.execution_mode}", "Optimization=0", f"FromDate={a.date_from}", f"ToDate={a.date_to}",
             "ForwardMode=0", f"Deposit={a.deposit:g}", f"Currency={a.currency}", f"Leverage={a.leverage}",
             "ProfitInPips=0", f"Report={report_rel}", "ReplaceReport=1", "ShutdownTerminal=1",
             "UseLocal=1", "UseRemote=0", "UseCloud=0", "Visual=0", "", "[TesterInputs]"]
    lines += [f"{k}={v}" for k, v in inputs]
    lines.append("")
    return "\r\n".join(lines)


def validate_args(a):
    if a.model != 4 and not a.allow_non_real_ticks:
        raise RunnerError(f"Model={a.model} is not real ticks (4). Pass --allow-non-real-ticks only for diagnostics.")
    for d in (a.date_from, a.date_to):
        dt.datetime.strptime(d, "%Y.%m.%d")
    if not re.fullmatch(r"1:\d+", a.leverage):
        raise RunnerError("--leverage must look like 1:500")


# ----------------------------------------------------------------------------- compile
def parse_compile_log(path, fresh_after=None):
    if not os.path.isfile(path):
        return False, f"compile log missing: {path}"
    if fresh_after is not None and os.path.getmtime(path) < fresh_after:
        return False, f"compile log is stale (older than this run): {path}"
    txt = read_text(path)
    m = None
    for m in re.finditer(r"(\d+)\s+errors?,\s*(\d+)\s+warnings?", txt, re.I):
        pass
    if not m:
        return False, "could not find 'N errors, M warnings' in compile log:\n" + txt[-2000:]
    errs, warns = int(m.group(1)), int(m.group(2))
    return errs == 0, f"compile: {errs} errors, {warns} warnings ({path})"


def cmd_compile(a):
    name, src = resolve_ea(a)
    term = os.path.abspath(a.terminal_dir)
    editor = os.path.join(term, "MetaEditor64.exe")
    stage = os.path.abspath(a.stage_dir or default_stage_dir(term, bool(a.wine)))
    s_src, s_ex5, s_log = (os.path.join(stage, name + e) for e in (".mq5", ".ex5", ".log"))
    w_src, w_log = to_win_path(s_src, bool(a.wine)), to_win_path(s_log, bool(a.wine))
    if " " in w_src or " " in w_log:
        raise RunnerError(f"staging path contains spaces ({w_src}); pass --stage-dir to a spaces-free folder")
    cmd = exe_cmd(editor, ["/portable", f"/compile:{w_src}", f"/log:{w_log}"], a.wine)
    dst = os.path.join(term, "MQL5", "Experts", EA_SUBDIR, name + ".ex5")
    plan = {"ea": name, "source": src, "stage": stage, "remove_first": [s_ex5, s_log], "command": cmd,
            "cwd": term, "success_requires": ["fresh log with 0 errors", "fresh non-empty .ex5"], "install_ex5_to": dst}
    if a.dry_run:
        print(json.dumps({"dry_run": True, "compile": plan}, indent=1)); return 0
    if not os.path.isfile(src):
        raise RunnerError(f"source not found: {src}")
    if not os.path.isfile(editor):
        raise RunnerError(f"MetaEditor64.exe not found in {term}")
    os.makedirs(stage, exist_ok=True)
    for f in (s_ex5, s_log):                       # no stale artifacts can be mistaken for success
        if os.path.exists(f): os.remove(f)
    shutil.copy2(src, s_src)
    t0 = time.time() - 1
    try:
        subprocess.run(cmd, cwd=term, timeout=a.timeout, check=False)
    except subprocess.TimeoutExpired:
        raise RunnerError(f"compile timeout after {a.timeout}s")
    ok, summary = parse_compile_log(s_log, t0)
    ex5_ok = os.path.isfile(s_ex5) and os.path.getmtime(s_ex5) >= t0 and os.path.getsize(s_ex5) > 0
    print(summary)
    if not ok or not ex5_ok:
        print(f"FAILED: log_ok={ok} fresh_ex5={ex5_ok} ({s_ex5})"); return 2
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if os.path.exists(dst): os.remove(dst)
    shutil.copy2(s_ex5, dst)
    print(f"ex5 {os.path.getsize(dst)} bytes -> {dst}")
    return 0


# ----------------------------------------------------------------------------- backtest
def find_report(term, report_rel, t0):
    base = os.path.join(term, report_rel.replace("\\", os.sep))
    for ext in (".htm", ".html", ".xml"):
        p = base + ext
        if os.path.isfile(p) and os.path.getmtime(p) >= t0:
            return p
    return None


def find_ea_summary(term, run_tag, t0):
    """SUMMARY line of THIS run only: logs modified after start, line must carry '|<run_tag>|SUMMARY|'."""
    hit = None
    for root, _d, files in os.walk(os.path.join(term, "Tester")):
        for fn in files:
            p = os.path.join(root, fn)
            if not fn.endswith(".log") or os.path.getmtime(p) < t0:
                continue
            for line in read_text(p).splitlines():
                if f"|{run_tag}|SUMMARY|" in line:
                    hit = line.split("|SUMMARY|", 1)[1].strip()
    if not hit:
        return None
    return dict(kv.split("=", 1) for kv in hit.split() if "=" in kv)


def find_equity_csv(term, name, t0):
    for root, _d, files in os.walk(os.path.join(term, "Tester")):
        if name in files:
            p = os.path.join(root, name)
            if os.path.getmtime(p) >= t0:
                return p
    return None


def cmd_backtest(a):
    validate_args(a)
    name, _src = resolve_ea(a)
    term = os.path.abspath(a.terminal_dir)
    terminal = os.path.join(term, "terminal64.exe")
    preset = os.path.abspath(a.preset)
    items = read_set(preset); d = check_preset_safety(items)
    if "InpRunTag" not in d:
        raise RunnerError(f"preset {os.path.basename(preset)} has no InpRunTag input: wrong EA for this preset?")
    run_id = dt.datetime.now().strftime("%Y%m%d_%H%M%S") + "_" + uuid.uuid4().hex[:6]
    eq_name = f"{name}_{run_id}_equity.csv"
    inputs = [(k, run_id if k == "InpRunTag" else (eq_name if k == "InpEquityFileName" else v)) for k, v in items]
    tag = os.path.splitext(os.path.basename(preset))[0]
    report_rel = f"reports\\{tag}_{run_id}"
    ini_path = os.path.join(term, "xau300_runs", f"{tag}_{run_id}.ini")
    ini = build_ini(a, name, inputs, report_rel)
    cmd = exe_cmd(terminal, ["/portable", f"/config:{to_win_path(ini_path, bool(a.wine))}"], a.wine)
    plan = {"ea": name, "run_id": run_id, "terminal": terminal, "ini_path": ini_path, "ini": ini.split("\r\n"),
            "ex5_expected": os.path.join(term, "MQL5", "Experts", EA_SUBDIR, name + ".ex5"),
            "report_base": os.path.join(term, report_rel.replace("\\", os.sep)), "equity_csv": eq_name,
            "command": cmd, "cwd": term, "timeout_s": a.timeout}
    if a.dry_run:
        print(json.dumps({"dry_run": True, "backtest": plan}, indent=1)); return 0
    if not os.path.isfile(terminal):
        raise RunnerError(f"terminal64.exe not found in {term} (use a dedicated portable install)")
    if not os.path.isfile(plan["ex5_expected"]):
        raise RunnerError("EA not compiled for this terminal: run the 'compile' command first")
    if terminal_running(term):
        raise RunnerError("a terminal from this folder is already running; close it yourself (the runner never kills it)")
    os.makedirs(os.path.dirname(ini_path), exist_ok=True); os.makedirs(os.path.join(term, "reports"), exist_ok=True)
    with open(ini_path, "w", encoding="utf-16") as f:
        f.write(ini)
    t0 = time.time() - 1
    proc = subprocess.Popen(cmd, cwd=term)
    try:
        proc.wait(timeout=a.timeout)
    except subprocess.TimeoutExpired:
        proc.terminate()                                   # only our own child process
        try: proc.wait(30)
        except subprocess.TimeoutExpired: proc.kill()
        raise RunnerError(f"timeout after {a.timeout}s (terminated only the process started by this runner)")
    rep = find_report(term, report_rel, t0)
    if not rep:
        raise RunnerError(f"no fresh report at {plan['report_base']}.(htm|html|xml); check {term}/Tester/logs")
    sys.path.insert(0, HERE)
    import report_parser as RP
    res = RP.parse_report(rep)
    problems = RP.validate(res, expect_symbol=a.symbol, expect_deposit=a.deposit, expect_leverage=a.leverage)
    summ = find_ea_summary(term, run_id, t0)
    if summ is None:
        problems.append(f"EA SUMMARY line with run tag {run_id} not found in fresh tester logs")
    eq_csv = None
    if d.get("InpEquityCsv", "false").lower() in ("true", "1"):
        src_csv = find_equity_csv(term, eq_name, t0)
        if src_csv:
            eq_csv = os.path.splitext(rep)[0] + ".equity_m1.csv"
            shutil.copy2(src_csv, eq_csv)
        else:
            problems.append(f"equity CSV {eq_name} not found under {term}/Tester (fresh)")
    res["runner"] = {"run_id": run_id, "ea": name, "seconds": round(time.time() - t0, 1), "ini": ini_path,
                     "ini_model": a.model, "report": rep, "preset": dict(inputs), "ea_summary": summ,
                     "equity_csv_m1_sampled": eq_csv, "validation_problems": problems}
    out = a.json or os.path.splitext(rep)[0] + ".summary.json"
    with open(out, "w") as f:
        json.dump(res, f, indent=1, default=str)
    RP.print_human(res)
    print(f"\nsummary json: {out}" + (f"\nequity csv (M1-sampled): {eq_csv}" if eq_csv else ""))
    if problems:
        print("VALIDATION PROBLEMS:\n - " + "\n - ".join(problems)); return 3
    return 0


def cmd_parse(a):
    sys.path.insert(0, HERE)
    import report_parser as RP
    res = RP.parse_report(a.report)
    if a.json:
        with open(a.json, "w") as f:
            json.dump(res, f, indent=1, default=str)
    RP.print_human(res)
    probs = RP.validate(res)
    if probs:
        print("VALIDATION PROBLEMS:\n - " + "\n - ".join(probs))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for nm in ("compile", "backtest"):
        s = sub.add_parser(nm)
        g = s.add_mutually_exclusive_group()
        g.add_argument("--ea", choices=sorted(KNOWN_EAS), default="XAU_300_Research_v1")
        g.add_argument("--source", help="any .mq5 path (name without spaces)")
        s.add_argument("--terminal-dir", required=True, help="dedicated PORTABLE MT5 folder (contains terminal64.exe)")
        s.add_argument("--wine", default=None, help="wine executable on Linux/macOS (e.g. wine); omit on Windows")
        s.add_argument("--timeout", type=int, default=3600)
        s.add_argument("--dry-run", action="store_true")
    sub.choices["compile"].add_argument("--stage-dir", default=None, help="spaces-free staging folder (default C:\\MT5stage)")
    b = sub.choices["backtest"]
    b.add_argument("--preset", required=True)
    b.add_argument("--symbol", default="XAUUSD")
    b.add_argument("--period", default="M1")
    b.add_argument("--from", dest="date_from", default="2025.10.31")
    b.add_argument("--to", dest="date_to", default="2026.10.31")
    b.add_argument("--model", type=int, default=4)
    b.add_argument("--allow-non-real-ticks", action="store_true")
    b.add_argument("--execution-mode", type=int, default=0, help="0 = no delay; -1 random delay; N ms")
    b.add_argument("--deposit", type=float, default=300.0)
    b.add_argument("--currency", default="USD")
    b.add_argument("--leverage", default="1:500")
    b.add_argument("--json", default=None)
    p = sub.add_parser("parse")
    p.add_argument("--report", required=True)
    p.add_argument("--json", default=None)
    a = ap.parse_args(argv)
    try:
        return {"compile": cmd_compile, "backtest": cmd_backtest, "parse": cmd_parse}[a.cmd](a)
    except RunnerError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
