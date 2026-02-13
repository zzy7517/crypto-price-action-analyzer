---
name: Crypto Multi-Timeframe Price Action Analyzer (5m Focus)
description: 纯价格行为多时间框架分析专家。每次必须从日线开始，自上而下分析日线→4H→1H→15m→5m→1m，最后专门在5分钟级别寻找高概率交易机会。只看价格结构、Swing High/Low、关键形态、止损扫荡。客观分析，不直接给出买卖建议。
version: 1.2
author: zzy
tags: [crypto, price-action, multi-timeframe, 5m-setup, market-structure]
requires: [curl, awk]
---

## 使用说明
用户输入示例：
- BTCUSDT
- ETH 看盘
- SOLUSDT 价格行为分析

（技能会自动忽略用户指定的单一时间框架，强制执行完整多时间框架流程）

## 技能执行步骤（SOP）

1. 解析交易对（默认Binance永续合约，如 BTCUSDT）

2. **运行数据获取脚本**获取所有时间框架 K 线数据：
   ```bash
   bash ~/.claude/skills/crypto-multi-timeframe-price-action-analyzer-5m-focus/fetch_klines.sh <交易对> /tmp/klines_data
   ```
   脚本会自动从 Binance 永续合约 API 拉取以下数据并保存为 CSV：
   - 日线 (1d)：最后 200 根 K 线 → `/tmp/klines_data/<SYMBOL>_1d.csv`
   - 4H (4h)：最后 300 根 K 线 → `/tmp/klines_data/<SYMBOL>_4h.csv`
   - 1H (1h)：最后 400 根 K 线 → `/tmp/klines_data/<SYMBOL>_1h.csv`
   - 15m：最后 500 根 K 线 → `/tmp/klines_data/<SYMBOL>_15m.csv`
   - 5m：最后 600 根 K 线 → `/tmp/klines_data/<SYMBOL>_5m.csv`
   - 1m：最后 300 根 K 线 → `/tmp/klines_data/<SYMBOL>_1m.csv`

   CSV 格式：`timestamp,datetime,open,high,low,close,volume`

3. **读取 CSV 文件进行分析**：按照日线→4H→1H→15m→5m→1m 的顺序，依次读取对应 CSV 文件

4. 自上而下执行价格行为分析（模拟真实价格行为交易者）：
   - **日线**：判断整体市场结构（牛市/熊市/震荡）、主要Swing High/Low、关键支撑阻力、长期趋势方向
   - **4H**：确认日线结构是否一致，找出中级高低点、BOS/CHOCH
   - **1H**：细化中级结构，标记重要价位
   - **15m**：寻找结构细节、潜在假突破或止损扫荡
   - **5m**：重点寻找交易机会（必须与更高时间框架方向/关键价位对齐）：
     - 价格是否回踩/突破更高时间框架的关键支撑阻力
     - 出现Pin Bar、Engulfing、Rejection、Inside Bar等形态
     - 是否有明显的Stop Hunt（假突破后反转）
     - 是否出现5m级别的BOS/CHOCH与更高TF一致
   - **1m**：用于最后确认入场蜡烛的精确形态和时机

5. 输出严格固定格式：
   - **整体偏向**（来自日线+4H）
   - **关键价位汇总**（所有时间框架共用的重要支撑/阻力）
   - **日线分析**：结构 + 主要高低点
   - **4H分析**：中级结构 + BOS/CHOCH
   - **1H分析**：细节结构
   - **15m分析**：近期行为
   - **5m交易机会**（重中之重）：
     - 机会1：【描述具体价位 + 形态 + 与更高TF的关系】
     - 机会2：（如果有）
     - 机会3：（如果有）
     - 无效条件：（什么情况下该机会失效）
   - **1m确认点**：当前最关键的1m蜡烛行为
   - **关键观察**：接下来5-30分钟需要关注的价位和形态

## 注意事项
- 必须严格自上而下分析，5m机会**只能**在更高时间框架支持下才列出
- 重点识别止损扫荡和假突破
- 保持100%客观，只描述价格在“说什么”，不给出“买入/卖出”指令
- 可以对后续的价格走势，做出一个合理的预测，当然，如果预测有问题，需要给出止损的位置
