import time
import json
from datetime import datetime, timezone

import requests

GAMMA_API = "https://gamma-api.polymarket.com"
CLOB_API = "https://clob.polymarket.com"
COINS = ["btc", "eth", "sol", "xrp"]
INTERVALS = {
    "5m": {"seconds": 300, "label": "5分钟"},
    "15m": {"seconds": 900, "label": "15分钟"},
}

SESSION = requests.Session()
SESSION.headers.update({"Accept": "application/json"})


def parse_maybe_json(value):
    if isinstance(value, str):
        try:
            return json.loads(value)
        except Exception:
            return value
    return value


def get_current_interval_ts(interval_sec: int) -> int:
    now = int(time.time())
    return (now // interval_sec) * interval_sec + interval_sec


def get_next_interval_ts(interval_sec: int) -> int:
    now = int(time.time())
    return (now // interval_sec + 1) * interval_sec


def find_market(coin: str, interval: str, interval_ts: int):
    slug = f"{coin}-updown-{interval}-{interval_ts}"
    try:
        resp = SESSION.get(
            f"{GAMMA_API}/events",
            params={"slug": slug},
            timeout=10,
        )
        resp.raise_for_status()
        events = resp.json()
    except Exception as e:
        print(f"[ERROR] Gamma API request failed for {slug}: {e}")
        return None

    if not events:
        return None

    event = events[0]
    markets = event.get("markets", [])
    if not markets:
        return None

    m = markets[0]
    tokens = parse_maybe_json(m.get("clobTokenIds", []))
    prices = parse_maybe_json(m.get("outcomePrices", []))
    outcomes = parse_maybe_json(m.get("outcomes", []))

    if not isinstance(tokens, list) or len(tokens) < 2:
        return None

    return {
        "slug": slug,
        "question": m.get("question", ""),
        "condition_id": m.get("conditionId", ""),
        "up_token": tokens[0],
        "down_token": tokens[1],
        "outcomes": outcomes if isinstance(outcomes, list) else [],
        "outcome_prices": [float(p) for p in prices] if isinstance(prices, list) else [],
        "neg_risk": m.get("negRisk", False),
        "best_bid": float(m["bestBid"]) if m.get("bestBid") not in (None, "") else None,
        "best_ask": float(m["bestAsk"]) if m.get("bestAsk") not in (None, "") else None,
        "spread": float(m["spread"]) if m.get("spread") not in (None, "") else None,
        "last_price": float(m["lastTradePrice"]) if m.get("lastTradePrice") not in (None, "") else None,
        "liquidity": float(event["liquidity"]) if event.get("liquidity") not in (None, "") else None,
        "volume": float(m["volume"]) if m.get("volume") not in (None, "") else None,
        "end_date": m.get("endDate", ""),
        "active": m.get("active", False),
        "closed": m.get("closed", False),
    }


def get_orderbook(token_id: str):
    try:
        resp = SESSION.get(
            f"{CLOB_API}/book",
            params={"token_id": token_id},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
    except Exception as e:
        print(f"[ERROR] CLOB orderbook request failed for {token_id[:12]}...: {e}")
        return None

    bids = data.get("bids", [])
    asks = data.get("asks", [])

    best_bid = float(bids[-1]["price"]) if bids else None
    best_ask = float(asks[-1]["price"]) if asks else None

    return {
        "bids": bids,
        "asks": asks,
        "best_bid": best_bid,
        "best_ask": best_ask,
        "spread": round(best_ask - best_bid, 4) if best_bid is not None and best_ask is not None else None,
        "mid_price": round((best_ask + best_bid) / 2, 4) if best_bid is not None and best_ask is not None else None,
        "tick_size": data.get("tick_size", "0.01"),
        "min_order_size": data.get("min_order_size", ""),
        "last_price": data.get("last_trade_price", ""),
    }


def get_top_asks(token_id: str, n: int = 5):
    book = get_orderbook(token_id)
    if not book or not book["asks"]:
        return []

    asks = book["asks"]
    bottom_n = asks[-n:] if len(asks) >= n else asks[:]
    return [(float(a["price"]), float(a["size"])) for a in reversed(bottom_n)]


def compute_fee(shares: float, price: float) -> float:
    return shares * 0.25 * (price * (1 - price)) ** 2


def estimate_profit(shares: float, buy_price: float, win: bool):
    cost = shares * buy_price
    fee = compute_fee(shares, buy_price)

    if win:
        actual_shares = shares - fee
        payout = actual_shares
        pnl = payout - cost
    else:
        actual_shares = shares - fee
        payout = 0.0
        pnl = -cost

    return {
        "shares": shares,
        "buy_price": buy_price,
        "cost": round(cost, 4),
        "fee_shares": round(fee, 4),
        "actual_shares": round(actual_shares, 4),
        "payout": round(payout, 4),
        "pnl": round(pnl, 4),
        "roi_pct": round(pnl / cost * 100, 2) if cost > 0 else 0,
    }


def quick_lookup(coin: str, interval: str = "15m"):
    cfg = INTERVALS[interval]
    current_ts = get_current_interval_ts(cfg["seconds"])
    market = find_market(coin, interval, current_ts)
    if market is None:
        return None

    market["orderbook_up"] = get_orderbook(market["up_token"])
    market["orderbook_down"] = get_orderbook(market["down_token"])
    return market


def print_market(market: dict, prefix: str = ""):
    prices = market.get("outcome_prices", [])
    up_price = prices[0] if len(prices) > 0 else "?"
    down_price = prices[1] if len(prices) > 1 else "?"

    print(f"{prefix}{market['slug']}")
    print(f"  问题: {market['question']}")
    print(f"  状态: {'交易中' if market['active'] and not market['closed'] else '已关闭'}")
    print(f"  Up价格: {up_price} | Down价格: {down_price}")
    print(f"  最优买: {market['best_bid']} | 最优卖: {market['best_ask']} | 价差: {market['spread']}")
    if market['liquidity'] is not None:
        print(f"  流动性: ${market['liquidity']:,.2f}")
    if market['volume'] is not None:
        print(f"  成交量: ${market['volume']:,.2f}")
    print(f"  Up token: {market['up_token']}")
    print(f"  Down token: {market['down_token']}")

    top_asks = get_top_asks(market['up_token'], n=5)
    print("  -- Orderbook (Up/YES top asks) --")
    if top_asks:
        for i, (price, size) in enumerate(top_asks, start=1):
            marker = " <-- best ask" if i == 1 else ""
            print(f"    ASK {i}: {price:.4f} x {size:.2f}{marker}")
    else:
        print("    (no asks)")


def scan_all_markets(coins=None, intervals=None):
    coins = coins or COINS
    intervals = intervals or list(INTERVALS.keys())

    print("=" * 80)
    print("Polymarket Up-or-Down 市场扫描器")
    print(f"时间: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC")
    print(f"币种: {', '.join(c.upper() for c in coins)}")
    print(f"周期: {', '.join(intervals)}")
    print("=" * 80)

    for interval in intervals:
        cfg = INTERVALS[interval]
        interval_sec = cfg["seconds"]
        current_ts = get_current_interval_ts(interval_sec)
        next_ts = current_ts + interval_sec

        current_end = datetime.fromtimestamp(current_ts, tz=timezone.utc)
        next_end = datetime.fromtimestamp(next_ts, tz=timezone.utc)

        print("\n" + "-" * 80)
        print(f"{cfg['label']} ({interval})")
        print(f"当前区间结束: {current_end.strftime('%H:%M:%S')} UTC (ts={current_ts})")
        print(f"下一区间结束: {next_end.strftime('%H:%M:%S')} UTC (ts={next_ts})")
        print("-" * 80)

        for coin in coins:
            print(f"\n[{coin.upper()}]")
            market = find_market(coin, interval, current_ts)
            if market is None:
                print("  当前区间: 未找到市场")
            else:
                print_market(market, prefix="  当前区间: ")

            market_next = find_market(coin, interval, next_ts)
            if market_next is None:
                print("  下一区间: 未找到市场")
            else:
                print_market(market_next, prefix="  下一区间: ")


if __name__ == "__main__":
    info = quick_lookup("btc", "15m")
    if info:
        print_market(info, prefix="快速查询: ")
        if info.get("orderbook_up"):
            ask_price = info["orderbook_up"].get("best_ask") or 0.50
            print("\n盈亏估算 (买入 10 shares Up)")
            for outcome in [True, False]:
                result = estimate_profit(10, ask_price, win=outcome)
                label = "预测正确" if outcome else "预测错误"
                print(label, result)
    else:
        print("未找到 BTC 15m 当前市场")
