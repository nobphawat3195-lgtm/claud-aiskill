"""Builds a synthetic MT5-style tester report (UTF-16 HTML) with known answers.
Deals cover: initial balance, entry commission, partial close in two exits, swap, a zero-net (breakeven) trade,
a commission-only loser, a plain loser and an in/out reversal."""
import os

HEAD = [("Expert:", "XAU_300_Research_v1"), ("Symbol:", "XAUUSD"), ("Period:", "M1 (2025.10.31 - 2026.10.31)"),
        ("Model:", "Every tick based on real ticks"), ("Initial Deposit:", "300.00"), ("Leverage:", "1:500"),
        ("History Quality:", "100%"), ("Total Net Profit:", "13.28"), ("Profit Factor:", "3.17"),
        ("Total Trades:", "7"), ("Balance Drawdown Maximal:", "6.14 (1.95%)"), ("Equity Drawdown Maximal:", "9.50 (3.01%)")]

ORDERS = [
    ("2025.11.03 01:05:00", "2", "xauusd", "buy", "0.02 / 0.02", "2000.00", "1990.00", "2020.00", "2025.11.03 01:05:00", "filled", ""),
    ("2025.11.03 02:00:00", "3", "xauusd", "sell", "0.01 / 0.01", "2010.00", "", "", "2025.11.03 02:00:00", "filled", ""),
    ("2025.11.03 03:00:00", "4", "xauusd", "sell", "0.01 / 0.01", "2005.00", "", "", "2025.11.03 03:00:00", "filled", ""),
]

# Time, Deal, Symbol, Type, Direction, Volume, Price, Order, Commission, Swap, Profit, Balance, Comment
DEALS = [
    ("2025.10.31 00:00:00", "1", "", "balance", "", "", "", "", "0.00", "0.00", "300.00", "300.00", ""),
    # T1: buy 0.02, partial close 0.01 + final 0.01 with swap -> net 10 + 5 - 0.14 - 0.07 - 0.07 - 0.30 = 14.42
    ("2025.11.03 01:05:00", "2", "XAUUSD", "buy", "in", "0.02", "2000.00", "2", "-0.14", "0.00", "0.00", "299.86", ""),
    ("2025.11.03 02:00:00", "3", "XAUUSD", "sell", "out", "0.01", "2010.00", "3", "-0.07", "0.00", "10.00", "309.79", "partial"),
    ("2025.11.04 03:00:00", "4", "XAUUSD", "sell", "out", "0.01", "2005.00", "4", "-0.07", "-0.30", "5.00", "314.42", "tp"),
    # T2: sell 0.01 closed flat, commissions only -> net -0.14 (loss)
    ("2025.11.10 01:10:00", "5", "XAUUSD", "sell", "in", "0.01", "2010.00", "5", "-0.07", "0.00", "0.00", "314.35", ""),
    ("2025.11.10 05:00:00", "6", "XAUUSD", "buy", "out", "0.01", "2010.00", "6", "-0.07", "0.00", "0.00", "314.28", ""),
    # T3: exact breakeven (no commission) -> BE
    ("2026.01.06 01:10:00", "7", "XAUUSD", "buy", "in", "0.01", "2100.00", "7", "0.00", "0.00", "0.00", "314.28", ""),
    ("2026.01.06 04:00:00", "8", "XAUUSD", "sell", "out", "0.01", "2100.00", "8", "0.00", "0.00", "0.00", "314.28", "sl"),
    # T4: loser -6
    ("2026.01.07 01:10:00", "9", "XAUUSD", "buy", "in", "0.01", "2100.00", "9", "0.00", "0.00", "0.00", "314.28", ""),
    ("2026.01.07 03:00:00", "10", "XAUUSD", "sell", "out", "0.01", "2094.00", "10", "0.00", "0.00", "-6.00", "308.28", "sl"),
    # T5 buy 0.01, reversed by sell 0.02 in/out (+3) -> T6 sell 0.01 closed +2
    ("2026.02.02 01:10:00", "11", "XAUUSD", "buy", "in", "0.01", "2200.00", "11", "0.00", "0.00", "0.00", "308.28", ""),
    ("2026.02.02 02:00:00", "12", "XAUUSD", "sell", "in/out", "0.02", "2203.00", "12", "0.00", "0.00", "3.00", "311.28", ""),
    ("2026.02.02 03:00:00", "13", "XAUUSD", "buy", "out", "0.01", "2201.00", "13", "0.00", "0.00", "2.00", "313.28", ""),
]

EXPECT = dict(trades=6, wins=3, losses=2, breakeven=1, net=13.28, commission=-0.42, swap=-0.30,
              partial_close_trades=1, balance_dd_money=6.14, balance_dd_pct=6.14 / 314.42 * 100, orders=3, deals=12,
              monthly={"2025-11": (2, 14.28), "2026-01": (2, -6.0), "2026-02": (2, 5.0)})


def row(cells, tag="td"):
    return "<tr>" + "".join(f"<{tag}>{c}</{tag}>" for c in cells) + "</tr>"


def build_html():
    h = ["<html><head><meta charset='utf-16'><title>Strategy Tester Report</title></head><body><table>"]
    h += [row([k, v]) for k, v in HEAD]
    h.append(row([""]))
    h.append(row(["Orders"], "th"))
    h.append(row(["Open Time", "Order", "Symbol", "Type", "Volume", "Price", "S / L", "T / P", "Time", "State", "Comment"]))
    h += [row(o) for o in ORDERS]
    h.append(row([""]))
    h.append(row(["Deals"], "th"))
    h.append(row(["Time", "Deal", "Symbol", "Type", "Direction", "Volume", "Price", "Order", "Commission", "Swap", "Profit", "Balance", "Comment"]))
    h += [row(d) for d in DEALS]
    h.append(row(["", "", "", "", "", "", "", "", "-0.42", "-0.30", "14.00", "313.28", ""]))
    h.append("</table></body></html>")
    return "\n".join(h)


def write(path):
    with open(path, "w", encoding="utf-16") as f:
        f.write(build_html())
    return path


if __name__ == "__main__":
    print(write(os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "synthetic_report_utf16.htm")))
