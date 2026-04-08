# Crypto Trading Skills

一个可持续扩展的加密交易研究 skill 仓库，聚合价格行为分析、市场结构研究、Polymarket 短周期市场监控等可复用工作流。

An extensible repository of reusable crypto trading and market-analysis skills, covering price action, market structure, and short-term Polymarket research.

## Skills

| Skill | Path | Scope |
| --- | --- | --- |
| Crypto Price Action | `skills/crypto-price-action/` | 多时间框架价格行为、Smart Money Concepts、衍生品辅助分析 |
| Polymarket Crypto Short-Term | `skills/polymarket-crypto-shortterm/` | Polymarket 5m/15m crypto up-or-down 市场研究、盘口与手续费建模 |

## Layout

```text
skills/
  crypto-price-action/
    SKILL.md
    scripts/
      fetch_klines.sh
  polymarket-crypto-shortterm/
    SKILL.md
    references/
      restored-monitor-script.py
      study-plan.md
```

## Notes

- 每个 skill 都尽量保持自包含：说明文档、脚本、参考资料放在同一个目录内。
- 适合继续扩展更多 market-analysis / trading-research skills。
- 如果后续继续增加内容，建议统一放到 `skills/<skill-name>/` 下面。
