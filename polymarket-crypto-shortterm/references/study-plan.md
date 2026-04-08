# Polymarket Crypto 5m/15m Systematic Study Plan

## Phase 1: Market structure
- Understand binary outcome pricing: Up price + Down price is usually near 1
- Learn the difference between event liquidity, volume, and executable orderbook depth
- Understand current interval vs next interval market creation

## Phase 2: Data collection
- Monitor BTC and ETH 15m markets first
- For each sample, record:
  - UTC time
  - slug
  - interval end time
  - Up/Down prices
  - Up/Down best bid and ask
  - spread
  - top 3 ask sizes
  - liquidity
  - volume
- Save to CSV and inspect manually for one week

## Phase 3: Microstructure
- Measure how often books are empty
- Measure how often displayed prices differ from best executable prices
- Compare current market vs next market liquidity ramp
- Track price movement in the last 60s before expiry

## Phase 4: Fee-aware modeling
- For each hypothetical trade, compute:
  - gross cost
  - fee shares
  - payout if correct
  - loss if wrong
  - fee-adjusted EV
- Compare EV before and after fees

## Phase 5: Strategy prototypes
- Momentum near interval end
- Mean reversion after short spikes
- Spread/liquidity filters only
- No live execution until paper results are stable

## Phase 6: Bot hardening
- Add retries and timeout handling
- Add stale-data detection
- Add one-sided fill protection
- Add risk caps per market and per day
- Add logging for every decision

## Recommended output schema
```json
{
  "ts_utc": "2026-04-08T22:55:00Z",
  "coin": "btc",
  "interval": "15m",
  "slug": "btc-updown-15m-1773127800",
  "current_end_ts": 1773127800,
  "up_token": "...",
  "down_token": "...",
  "up_best_bid": 0.47,
  "up_best_ask": 0.49,
  "down_best_bid": 0.51,
  "down_best_ask": 0.53,
  "liquidity": 12345.67,
  "volume": 891011.12
}
```

## What to learn before live capital
- Resolution rules
- Execution mechanics
- Order placement and cancellation behavior
- Fill probability under low depth
- Real fee schedule from official docs
