#!/bin/bash
# fetch_klines.sh - 从 Binance 永续合约 API 获取多时间框架 K 线数据
# 纯 curl + awk 实现，无任何外部依赖（macOS/Linux 自带）
#
# 用法: ./fetch_klines.sh BTCUSDT [输出目录]
# 示例: ./fetch_klines.sh BTCUSDT
#        ./fetch_klines.sh ETHUSDT /tmp/klines

set -euo pipefail

SYMBOL="${1:-}"
OUTDIR="${2:-/tmp/klines_data}"

if [ -z "$SYMBOL" ]; then
  echo "用法: $0 <交易对> [输出目录]"
  echo "示例: $0 BTCUSDT"
  exit 1
fi

# 统一转大写
SYMBOL=$(echo "$SYMBOL" | tr '[:lower:]' '[:upper:]')

# 如果没有 USDT 后缀，自动加上
if [[ "$SYMBOL" != *USDT ]]; then
  SYMBOL="${SYMBOL}USDT"
fi

BASE_URL="https://fapi.binance.com/fapi/v1/klines"

# 时间框架配置: interval:limit
TIMEFRAMES="1d:200 4h:300 1h:400 15m:500 5m:600 1m:300"

mkdir -p "$OUTDIR"

echo "=========================================="
echo " 交易对: $SYMBOL (Binance 永续合约)"
echo " 输出目录: $OUTDIR"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "=========================================="

parse_klines() {
  # 用 awk 解析 Binance JSON 数组，再用 perl 一次性添加可读时间
  # 输入: [[ts,"o","h","l","c","v",...],[...]]
  # 输出: timestamp,datetime,open,high,low,close,volume
  awk '
  BEGIN { RS="\\],?\\[?"; FS="," }
  {
    if (NF >= 6) {
      gsub(/[\[\]"]/,"",$1); gsub(/[\[\]"]/,"",$2); gsub(/[\[\]"]/,"",$3);
      gsub(/[\[\]"]/,"",$4); gsub(/[\[\]"]/,"",$5); gsub(/[\[\]"]/,"",$6);
      if ($1+0 > 0) {
        print $1","$2","$3","$4","$5","$6
      }
    }
  }' | perl -MPOSIX -F',' -lane '
    my $ts_sec = int($F[0] / 1000);
    my $dt = POSIX::strftime("%Y-%m-%d %H:%M", localtime($ts_sec));
    print "$F[0],$dt,$F[1],$F[2],$F[3],$F[4],$F[5]";
  '
}

for tf in $TIMEFRAMES; do
  interval="${tf%%:*}"
  limit="${tf##*:}"

  outfile="$OUTDIR/${SYMBOL}_${interval}.csv"
  echo "获取 $interval ($limit 根)..."

  url="${BASE_URL}?symbol=${SYMBOL}&interval=${interval}&limit=${limit}"
  raw=$(curl -s --connect-timeout 10 --max-time 30 "$url")

  # 检查是否返回错误
  if echo "$raw" | grep -q '"code"'; then
    echo "  [错误] $interval: $raw"
    continue
  fi

  # 写 CSV 头 + 解析数据
  echo "timestamp,datetime,open,high,low,close,volume" > "$outfile"
  echo "$raw" | parse_klines >> "$outfile"

  count=$(($(wc -l < "$outfile") - 1))
  echo "  [完成] $interval: ${count} 根 K 线 → $outfile"

  sleep 0.3
done

echo ""
echo "=========================================="
echo " 全部完成！数据文件："
echo "=========================================="
ls -lh "$OUTDIR"/${SYMBOL}_*.csv 2>/dev/null
echo ""
echo "CSV 格式: timestamp,datetime,open,high,low,close,volume"
echo ""

# 输出最新价格摘要
echo "--- 最新价格摘要 ---"
for tf in $TIMEFRAMES; do
  interval="${tf%%:*}"
  f="$OUTDIR/${SYMBOL}_${interval}.csv"
  if [ -f "$f" ]; then
    last_line=$(tail -1 "$f")
    dt=$(echo "$last_line" | cut -d',' -f2)
    close=$(echo "$last_line" | cut -d',' -f6)
    printf "  %-4s 最新收盘: %-12s (%s)\n" "$interval" "$close" "$dt"
  fi
done
