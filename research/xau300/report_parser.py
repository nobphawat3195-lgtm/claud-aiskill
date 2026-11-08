#!/usr/bin/env python3
"""
report_parser.py — parse an MT5 Strategy Tester report (.htm/.html, UTF-16 or UTF-8, or SpreadsheetML .xml).

Keeps the three MT5 notions apart:
  orders  = order rows of the "Orders" table
  deals   = executions in the "Deals" table (balance rows excluded from trading stats)
  trades  = round trips rebuilt from deals (FIFO per symbol). A position closed in several parts is ONE trade
            with several exit deals; its P/L = sum(profit + swap + commission) of all its deals, including the
            entry commission.
Win / loss / breakeven is decided on trade net P/L (|P/L| <= 0.005 = breakeven).
Balance drawdown is recomputed from deals; equity drawdown can only come from the report summary
(it needs tick-level floating P/L) and is reported as such.
"""
import re, sys, json, html
from html.parser import HTMLParser
from collections import OrderedDict, defaultdict

EPS = 0.005


# ----------------------------------------------------------------------------- low level
def _decode(raw):
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16")
    if raw[:3] == b"\xef\xbb\xbf":
        return raw[3:].decode("utf-8")
    # UTF-16 without BOM: many NUL bytes
    if raw[1:2] == b"\x00" and raw.count(b"\x00") > len(raw) // 4:
        return raw.decode("utf-16-le")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("cp1252", "replace")


class _Tables(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.rows = []; self._row = None; self._cell = None
    def handle_starttag(self, tag, attrs):
        if tag == "tr": self._row = []
        elif tag in ("td", "th") and self._row is not None:
            self._cell = []
            span = dict(attrs).get("colspan")
            self._span = int(span) if span and span.isdigit() else 1
    def handle_endtag(self, tag):
        if tag in ("td", "th") and self._cell is not None and self._row is not None:
            txt = " ".join("".join(self._cell).split())
            self._row.append(txt)
            for _ in range(self._span - 1): self._row.append("")
            self._cell = None
        elif tag == "tr" and self._row is not None:
            self.rows.append(self._row); self._row = None
    def handle_data(self, data):
        if self._cell is not None: self._cell.append(data)


def _rows_from_xml(txt):
    rows = []
    for r in re.findall(r"<Row[^>]*>(.*?)</Row>", txt, re.S | re.I):
        cells = [html.unescape(re.sub(r"<[^>]+>", "", c)).strip() for c in re.findall(r"<Cell[^>]*>(.*?)</Cell>", r, re.S | re.I)]
        rows.append(cells)
    return rows


def num(s):
    if s is None: return None
    s = s.replace("\xa0", " ").strip()
    m = re.match(r"^-?[\d ]+(?:[.,]\d+)?", s)
    if not m: return None
    v = m.group(0).replace(" ", "")
    if v.count(",") == 1 and "." not in v: v = v.replace(",", ".")
    try: return float(v)
    except ValueError: return None


def pct_in(s):
    m = re.search(r"\(?\s*(-?[\d.]+)\s*%\s*\)?", s or "")
    return float(m.group(1)) if m else None


# ----------------------------------------------------------------------------- report structure
def load_rows(path):
    txt = _decode(open(path, "rb").read())
    if "<Workbook" in txt[:5000] or "urn:schemas-microsoft-com:office:spreadsheet" in txt[:5000]:
        return _rows_from_xml(txt)
    p = _Tables(); p.feed(txt); return p.rows


def _summary(rows):
    """label:value pairs from all rows ('Total Net Profit:' -> '123.45')."""
    out = OrderedDict()
    for r in rows:
        cells = [c for c in r if c != ""]
        for i, c in enumerate(cells[:-1]):
            if c.endswith(":"):
                k = c[:-1].strip()
                if k not in out: out[k] = cells[i + 1]
    return out


def _table(rows, title, must_have):
    """Return (header, data_rows) of the table whose header row contains all `must_have` columns,
    searching after a row whose first non-empty cell equals `title`."""
    start = 0
    for i, r in enumerate(rows):
        ne = [c for c in r if c]
        if ne and ne[0].strip().lower() == title.lower():
            start = i + 1; break
    for i in range(start, len(rows)):
        hdr = [c.strip() for c in rows[i]]
        if all(any(h.lower() == m.lower() for h in hdr) for m in must_have):
            data = []
            for r in rows[i + 1:]:
                ne = [c for c in r if c]
                if not ne:
                    if data: break
                    continue
                if len(ne) <= 2 and data: break      # section title / totals row
                data.append(r)
            return hdr, data
    return None, []


def _rowdict(hdr, r):
    d = {}
    for i, h in enumerate(hdr):
        if h and i < len(r): d[h.lower()] = r[i]
    return d


# ----------------------------------------------------------------------------- trades from deals
def build_trades(deals):
    """FIFO round trips per symbol. Handles partial closes, multiple exits, 'in/out' reversals,
    commission on entry and exit deals, and swap."""
    open_lots = defaultdict(list)     # symbol -> list of dict(dir, vol, price, time, comm_per_lot, trade)
    trades = []
    for d in deals:
        if d["kind"] != "trade": continue
        sym, vol = d["symbol"], d["volume"]
        dirn = 1 if d["type"] == "buy" else -1
        entry = d["direction"]
        if entry == "in":
            t = dict(symbol=sym, dir=dirn, open_time=d["time"], open_price=d["price"], volume=vol, closed_volume=0.0,
                     profit=0.0, swap=0.0, commission=d["commission"], exits=[], close_time=None)
            open_lots[sym].append(dict(vol=vol, trade=t)); trades.append(t)
            # entry deals usually carry 0 profit; keep anything they report
            t["profit"] += d["profit"]; t["swap"] += d["swap"]
            continue
        # out / inout / out_by: close FIFO
        remaining = vol
        share_cost = (d["profit"], d["swap"], d["commission"])
        q = open_lots[sym]
        close_vol = vol if entry != "inout" else min(vol, sum(x["vol"] for x in q))
        remaining = close_vol
        while remaining > 1e-9 and q:
            lot = q[0]; take = min(lot["vol"], remaining); frac = take / close_vol if close_vol > 0 else 0
            t = lot["trade"]
            t["profit"] += share_cost[0] * frac; t["swap"] += share_cost[1] * frac; t["commission"] += share_cost[2] * frac
            t["closed_volume"] += take; t["exits"].append(dict(time=d["time"], price=d["price"], volume=take))
            t["close_time"] = d["time"]
            lot["vol"] -= take; remaining -= take
            if lot["vol"] <= 1e-9: q.pop(0)
        if entry == "inout":
            rest = vol - close_vol
            if rest > 1e-9:
                t = dict(symbol=sym, dir=dirn, open_time=d["time"], open_price=d["price"], volume=rest, closed_volume=0.0,
                         profit=0.0, swap=0.0, commission=0.0, exits=[], close_time=None)
                open_lots[sym].append(dict(vol=rest, trade=t)); trades.append(t)
    for t in trades:
        t["net"] = t["profit"] + t["swap"] + t["commission"]
        t["closed"] = t["closed_volume"] >= t["volume"] - 1e-9
        t["partial_exits"] = len(t["exits"])
    return trades


def parse_deals(hdr, rows):
    out = []
    for r in rows:
        d = _rowdict(hdr, r)
        typ = (d.get("type") or "").strip().lower()
        if not typ: continue
        kind = "trade" if typ in ("buy", "sell") else "balance" if typ in ("balance", "credit", "deposit", "withdrawal", "bonus") else "other"
        direction = (d.get("direction") or "").strip().lower().replace(" ", "")
        direction = {"in/out": "inout", "out_by": "out", "outby": "out"}.get(direction, direction)
        out.append(dict(time=d.get("time", ""), deal=d.get("deal", ""), symbol=d.get("symbol", ""), type=typ, kind=kind,
                        direction=direction, volume=num(d.get("volume", "")) or 0.0, price=num(d.get("price", "")) or 0.0,
                        order=d.get("order", ""), commission=num(d.get("commission", "")) or 0.0,
                        swap=num(d.get("swap", "")) or 0.0, profit=num(d.get("profit", "")) or 0.0,
                        balance=num(d.get("balance", "")), comment=d.get("comment", "")))
    return out


def stats_from(trades, deals, initial=None):
    closed = [t for t in trades if t["closed"]]
    nets = [t["net"] for t in closed]
    wins = [x for x in nets if x > EPS]; losses = [x for x in nets if x < -EPS]
    gp, gl = sum(wins), -sum(losses)
    # balance curve from deals in order
    bal = None; peak = None; max_dd = 0.0; max_dd_pct = 0.0
    if initial is None:
        dep = [d for d in deals if d["kind"] == "balance"]
        initial = sum(d["profit"] for d in dep) if dep else 0.0
    bal = initial; peak = initial
    for d in deals:
        if d["kind"] != "trade": continue
        bal += d["profit"] + d["swap"] + d["commission"]
        peak = max(peak, bal)
        if peak > 0:
            max_dd = max(max_dd, peak - bal); max_dd_pct = max(max_dd_pct, (peak - bal) / peak * 100.0)
    monthly = OrderedDict()
    for t in sorted(closed, key=lambda t: t["close_time"]):
        k = t["close_time"][:7].replace(".", "-")
        m = monthly.setdefault(k, {"trades": 0, "net": 0.0, "wins": 0, "losses": 0})
        m["trades"] += 1; m["net"] += t["net"]; m["wins"] += t["net"] > EPS; m["losses"] += t["net"] < -EPS
    return dict(trades=len(closed), open_trades=len(trades) - len(closed), wins=len(wins), losses=len(losses),
                breakeven=len(closed) - len(wins) - len(losses), gross_profit=gp, gross_loss=gl,
                net=sum(nets), pf=(gp / gl if gl > 0 else None), initial_deposit=initial,
                final_balance_from_deals=bal, balance_dd_money=max_dd, balance_dd_pct=max_dd_pct,
                commission=sum(t["commission"] for t in closed), swap=sum(t["swap"] for t in closed),
                partial_close_trades=sum(1 for t in closed if t["partial_exits"] > 1),
                largest_win=max(nets) if nets else 0.0, largest_loss=min(nets) if nets else 0.0,
                monthly=monthly)


def parse_report(path):
    rows = load_rows(path)
    summ = _summary(rows)
    dh, drows = _table(rows, "Deals", ["Deal", "Direction"])
    oh, orows = _table(rows, "Orders", ["Order", "State"])
    deals = parse_deals(dh, drows) if dh else []
    trades = build_trades(deals)
    st = stats_from(trades, deals, num(summ.get("Initial Deposit")))
    rep = dict(file=path, summary=dict(summ), orders=len(orows), deals=len([d for d in deals if d["kind"] == "trade"]),
               balance_deals=len([d for d in deals if d["kind"] == "balance"]), stats=st,
               report_equity_dd=summ.get("Equity Drawdown Maximal"), report_balance_dd=summ.get("Balance Drawdown Maximal"),
               report_net=num(summ.get("Total Net Profit")), report_pf=num(summ.get("Profit Factor")),
               report_trades=num(summ.get("Total Trades")),
               trades_list=[{k: t[k] for k in ("symbol", "dir", "open_time", "close_time", "volume", "open_price",
                                               "profit", "swap", "commission", "net", "partial_exits")} for t in trades])
    rep["report_equity_dd_pct"] = pct_in(rep["report_equity_dd"]) if rep["report_equity_dd"] else None
    rep["report_balance_dd_pct"] = pct_in(rep["report_balance_dd"]) if rep["report_balance_dd"] else None
    return rep


def validate(rep, expect_symbol=None, expect_deposit=None, expect_leverage=None, expect_model_text=None):
    """Return list of problems (empty = ok)."""
    p = []; s = rep["summary"]; flat = " ".join(f"{k}: {v}" for k, v in s.items())
    if expect_symbol and expect_symbol.lower() not in (s.get("Symbol", "") or "").lower():
        p.append(f"symbol in report {s.get('Symbol')!r} != {expect_symbol}")
    if expect_deposit is not None:
        dep = num(s.get("Initial Deposit"))
        if dep is None or abs(dep - expect_deposit) > 0.01: p.append(f"initial deposit {dep} != {expect_deposit}")
    if expect_leverage and expect_leverage not in (s.get("Leverage", "") or ""):
        p.append(f"leverage {s.get('Leverage')!r} != {expect_leverage}")
    if expect_model_text and expect_model_text.lower() not in flat.lower():
        p.append(f"model text {expect_model_text!r} not found in report header")
    hq = s.get("History Quality")
    if hq is not None and (pct_in(hq) or 0) < 99.0:
        p.append(f"history quality {hq} < 99%")
    st = rep["stats"]
    if rep["report_net"] is not None and abs(rep["report_net"] - st["net"]) > 0.05:
        p.append(f"net from deals {st['net']:.2f} != report Total Net Profit {rep['report_net']:.2f}")
    if rep["report_trades"] is not None and st["trades"] and int(rep["report_trades"]) < st["trades"]:
        p.append(f"report Total Trades {rep['report_trades']} < round trips rebuilt {st['trades']}")
    if st["open_trades"]:
        p.append(f"{st['open_trades']} trade(s) still open at report end")
    return p


def print_human(rep):
    st = rep["stats"]
    pf = f"{st['pf']:.2f}" if st["pf"] else "n/a"
    print(f"report: {rep['file']}")
    for k in ("Expert", "Symbol", "Period", "Model", "Initial Deposit", "Leverage", "History Quality", "Bars", "Ticks"):
        if k in rep["summary"]: print(f"  {k}: {rep['summary'][k]}")
    print(f"orders {rep['orders']} | deals {rep['deals']} (+{rep['balance_deals']} balance) | trades {st['trades']} "
          f"(win {st['wins']} / loss {st['losses']} / BE {st['breakeven']}, partial-close trades {st['partial_close_trades']})")
    print(f"net {st['net']:+.2f} | PF {pf} | balance DD {st['balance_dd_pct']:.2f}% (${st['balance_dd_money']:.2f}) | "
          f"equity DD (report) {rep['report_equity_dd']} | commission {st['commission']:.2f} | swap {st['swap']:.2f}")
    for m, v in st["monthly"].items():
        print(f"  {m}: {v['trades']:3d} trades  {v['net']:+9.2f}")


if __name__ == "__main__":
    r = parse_report(sys.argv[1])
    print_human(r)
    if len(sys.argv) > 2: json.dump(r, open(sys.argv[2], "w"), indent=1, default=str)
