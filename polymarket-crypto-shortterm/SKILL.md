---
name: polymarket-crypto-shortterm
description: Research and monitor Polymarket crypto 5m/15m up-or-down markets, including slug discovery, token IDs, orderbooks, liquidity, fees, and starter bot workflow.
version: 1.0.0
author: Hermes Agent
---

# Polymarket Crypto Short-Term Markets

Use this skill when working on Polymarket crypto 5m/15m up-or-down markets for BTC, ETH, SOL, XRP, or similar short-duration prediction markets.

## What this skill covers

- How 5m/15m market slugs are constructed
- How to find the currently trading and next interval market
- How to extract Up/Down token IDs
- How to fetch public CLOB orderbooks without auth
- How to estimate top-of-book, spread, liquidity, and simple fees
- How to turn the data into a starter monitoring / quant research workflow

## Core market structure

Polymarket usually pre-creates short-horizon crypto markets with slugs like:

`{coin}-updown-{interval}-{unix_timestamp}`

Examples:
- `btc-updown-5m-1773127800`
- `eth-updown-15m-1773128700`

The timestamp is the interval END time in Unix seconds, aligned to the interval boundary.

## Public APIs

1. Gamma API: market discovery and metadata
   - Base: `https://gamma-api.polymarket.com`
   - Typical endpoint: `/events?slug=...`

2. CLOB API: orderbook and top-of-book
   - Base: `https://clob.polymarket.com`
   - Typical endpoint: `/book?token_id=...`

No API key is required for these read-only queries.

## Important parsing details

Gamma often returns these fields as JSON-encoded strings inside JSON:
- `clobTokenIds`
- `outcomes`
- `outcomePrices`

Always parse them defensively with `json.loads(...)` when needed.

## Important orderbook detail

On Polymarket CLOB responses, do not assume array order without checking. In the commonly observed format for these markets:
- `bids` are ascending by price, so best bid is often `bids[-1]`
- `asks` may appear descending by price, so best ask is often `asks[-1]`

Verify this against live data before relying on it in automation.

## Recommended workflow

1. Compute the current interval end timestamp
2. Build the expected slug for each coin and interval
3. Query Gamma `/events?slug=...`
4. Extract the first market from the event
5. Parse token IDs and prices
6. Query CLOB `/book?token_id=...` for both Up and Down tokens
7. Record:
   - slug
   - question
   - conditionId
   - up/down token IDs
   - outcome prices
   - best bid / ask
   - spread
   - top ask depth
   - event liquidity
   - volume
8. Estimate fees and net edge before any strategy logic

## Quant-starter checklist

Before using the data in a bot, verify:
- Current market is active and not closed
- The slug points to the intended interval
- Up and Down token IDs are mapped correctly
- Best ask / best bid are from live book data, not stale Gamma metadata alone
- Liquidity is sufficient for your intended size
- Fee-adjusted expected value is positive
- Execution risk from one-sided fills is modeled

## Common pitfalls

- Using displayed page prices instead of live orderbook prices
- Not parsing JSON-encoded fields from Gamma
- Misreading ask ordering and taking the wrong best ask
- Trading based on next interval markets before liquidity appears
- Ignoring fees near 0.50, where they are highest
- Treating market liquidity as directly executable size

## Fee heuristic used in many community scripts

One commonly used fee-share approximation is:

`fee_shares = shares * 0.25 * (price * (1 - price))^2`

This is useful for rough modeling, but always confirm against Polymarket’s latest official fee docs before deploying real capital.

## Starter implementation notes

See `references/restored-monitor-script.py` for a cleaned starter script and `references/study-plan.md` for a structured learning path.

## Good first projects

1. Build a scanner for BTC/ETH 5m and 15m current markets
2. Log every 15 seconds into CSV
3. Compute spread, top-of-book size, and fee-adjusted expected value
4. Add alerts when spread compresses or price jumps near expiry
5. Backtest simple signals before considering automation
