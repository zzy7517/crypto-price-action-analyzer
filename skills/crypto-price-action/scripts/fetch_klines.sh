#!/bin/bash
# fetch_klines.sh - 从 Binance 永续合约 API 获取多时间框架市场数据
# 包含：K线(OHLCV)、多空比、主动买卖比、爆仓订单
# 纯 curl + awk + perl 实现，无外部依赖（macOS/Linux 自带）
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

KLINE_URL="https://fapi.binance.com/fapi/v1/klines"
DATA_URL="https://fapi.binance.com/futures/data"
FORCE_URL="https://fapi.binance.com/fapi/v1/forceOrders"

# K线时间框架: interval:limit
KLINE_TF="1d:200 4h:300 1h:400 15m:500 5m:600 1m:300"

# 衍生品数据周期: period:limit
DERIV_PERIODS="1d:30 4h:100 1h:200 15m:200 5m:200"

mkdir -p "$OUTDIR"

echo "=========================================="
echo " 交易对: $SYMBOL (Binance 永续合约)"
echo " 输出目录: $OUTDIR"
echo " 时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "=========================================="

# ====================================================
#  解析函数
# ====================================================

parse_klines() {
  # 解析 K线 JSON 数组格式: [[ts,"o","h","l","c","v",...],...]
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

parse_json_fields() {
  # 通用 JSON 对象数组解析器（适用于多空比 / Taker / 爆仓等）
  # 用法: echo "$json" | parse_json_fields "字段1,字段2,..." [时间戳字段] [时间格式]
  # 输出: timestamp,datetime,字段1值,字段2值,...
  local fields="$1"
  local ts_field="${2:-timestamp}"
  local ts_fmt="${3:-%Y-%m-%d %H:%M}"
  perl -MPOSIX -e '
    my @fields = split(",", $ARGV[0]);
    my $ts_field = $ARGV[1];
    my $ts_fmt = $ARGV[2];
    my $json = do { local $/; <STDIN> };
    while ($json =~ /\{([^}]+)\}/g) {
      my $obj = $1;
      my %f;
      while ($obj =~ /"(\w+)"\s*:\s*(?:"([^"]*)"|([\d.eE+-]+))/g) {
        $f{$1} = defined($2) ? $2 : $3;
      }
      next unless defined $f{$ts_field} && $f{$ts_field} =~ /^\d+$/;
      my $dt = POSIX::strftime($ts_fmt, localtime(int($f{$ts_field}/1000)));
      my @vals = ($f{$ts_field}, $dt);
      for my $field (@fields) {
        push @vals, ($f{$field} // "");
      }
      print join(",", @vals) . "\n";
    }
  ' -- "$fields" "$ts_field" "$ts_fmt"
}

# ====================================================
#  [1/4] K线数据 (OHLCV)
# ====================================================
echo ""
echo "--- [1/4] K线数据 (OHLCV) ---"

for tf in $KLINE_TF; do
  interval="${tf%%:*}"
  limit="${tf##*:}"
  outfile="$OUTDIR/${SYMBOL}_${interval}.csv"
  echo "  获取 $interval ($limit 根)..."

  url="${KLINE_URL}?symbol=${SYMBOL}&interval=${interval}&limit=${limit}"
  raw=$(curl -s --connect-timeout 10 --max-time 30 "$url")

  if echo "$raw" | grep -q '"code"'; then
    echo "    [错误] $interval: $raw"
    continue
  fi

  echo "timestamp,datetime,open,high,low,close,volume" > "$outfile"
  echo "$raw" | parse_klines >> "$outfile"

  count=$(($(wc -l < "$outfile") - 1))
  echo "    [完成] ${count} 根 → $outfile"
  sleep 0.3
done

# ====================================================
#  [2/4] 多空比 (Global Long/Short Ratio)
# ====================================================
echo ""
echo "--- [2/4] 多空比 (Long/Short Ratio) ---"

for dp in $DERIV_PERIODS; do
  period="${dp%%:*}"
  limit="${dp##*:}"
  outfile="$OUTDIR/${SYMBOL}_lsratio_${period}.csv"
  echo "  获取 L/S $period ($limit 条)..."

  url="${DATA_URL}/globalLongShortAccountRatio?symbol=${SYMBOL}&period=${period}&limit=${limit}"
  raw=$(curl -s --connect-timeout 10 --max-time 30 "$url")

  if echo "$raw" | grep -q '"code"'; then
    echo "    [错误] LS $period: $raw"
    continue
  fi

  echo "timestamp,datetime,long_short_ratio,long_account,short_account" > "$outfile"
  echo "$raw" | parse_json_fields "longShortRatio,longAccount,shortAccount" >> "$outfile"

  count=$(($(wc -l < "$outfile") - 1))
  echo "    [完成] ${count} 条 → $outfile"
  sleep 0.3
done

# ====================================================
#  [3/4] 主动买卖比 (Taker Buy/Sell Volume)
# ====================================================
echo ""
echo "--- [3/4] 主动买卖比 (Taker Buy/Sell) ---"

for dp in $DERIV_PERIODS; do
  period="${dp%%:*}"
  limit="${dp##*:}"
  outfile="$OUTDIR/${SYMBOL}_taker_${period}.csv"
  echo "  获取 Taker $period ($limit 条)..."

  url="${DATA_URL}/takerlongshortRatio?symbol=${SYMBOL}&period=${period}&limit=${limit}"
  raw=$(curl -s --connect-timeout 10 --max-time 30 "$url")

  if echo "$raw" | grep -q '"code"'; then
    echo "    [错误] Taker $period: $raw"
    continue
  fi

  echo "timestamp,datetime,buy_sell_ratio,buy_vol,sell_vol" > "$outfile"
  echo "$raw" | parse_json_fields "buySellRatio,buyVol,sellVol" >> "$outfile"

  count=$(($(wc -l < "$outfile") - 1))
  echo "    [完成] ${count} 条 → $outfile"
  sleep 0.3
done

# ====================================================
#  [4/4] 爆仓订单 (Liquidation Orders)
# ====================================================
echo ""
echo "--- [4/4] 爆仓订单 ---"

liq_outfile="$OUTDIR/${SYMBOL}_liquidations.csv"
echo "  获取最近爆仓订单..."

liq_raw=$(curl -s --connect-timeout 10 --max-time 30 \
  "${FORCE_URL}?symbol=${SYMBOL}&limit=1000" 2>/dev/null || echo "[]")

if echo "$liq_raw" | grep -q '"code"'; then
  echo "    [跳过] 爆仓接口不可用（可能需要API密钥或IP白名单）"
else
  echo "timestamp,datetime,side,price,avg_price,quantity,quote_qty" > "$liq_outfile"
  echo "$liq_raw" | parse_json_fields "side,price,avgPrice,executedQty,cumQuote" "time" "%Y-%m-%d %H:%M:%S" >> "$liq_outfile"

  count=$(($(wc -l < "$liq_outfile") - 1))
  if [ "$count" -gt 0 ]; then
    echo "    [完成] ${count} 条 → $liq_outfile"
  else
    echo "    [无数据] 暂无最近爆仓记录"
  fi
fi

# ====================================================
#  完成摘要
# ====================================================
echo ""
echo "=========================================="
echo " 全部完成！数据文件："
echo "=========================================="
ls -lh "$OUTDIR"/${SYMBOL}_*.csv 2>/dev/null

echo ""
echo "CSV 格式说明:"
echo "  K线:       timestamp,datetime,open,high,low,close,volume"
echo "  多空比:    timestamp,datetime,long_short_ratio,long_account,short_account"
echo "  主动买卖:  timestamp,datetime,buy_sell_ratio,buy_vol,sell_vol"
echo "  爆仓订单:  timestamp,datetime,side,price,avg_price,quantity,quote_qty"
echo ""

# --- 最新价格摘要 ---
echo "--- 最新价格摘要 ---"
for tf in $KLINE_TF; do
  interval="${tf%%:*}"
  f="$OUTDIR/${SYMBOL}_${interval}.csv"
  if [ -f "$f" ]; then
    last_line=$(tail -1 "$f")
    dt=$(echo "$last_line" | cut -d',' -f2)
    close=$(echo "$last_line" | cut -d',' -f6)
    printf "  %-4s 最新收盘: %-12s (%s)\n" "$interval" "$close" "$dt"
  fi
done

# --- 最新衍生品数据摘要 ---
echo ""
echo "--- 最新衍生品数据摘要 ---"

# LS Ratio
ls_file="$OUTDIR/${SYMBOL}_lsratio_5m.csv"
if [ -f "$ls_file" ] && [ "$(wc -l < "$ls_file")" -gt 1 ]; then
  last=$(tail -1 "$ls_file")
  ratio=$(echo "$last" | cut -d',' -f3)
  long_pct=$(echo "$last" | cut -d',' -f4)
  short_pct=$(echo "$last" | cut -d',' -f5)
  dt=$(echo "$last" | cut -d',' -f2)
  printf "  多空比:    %-15s (多 %s / 空 %s) [%s]\n" "$ratio" "$long_pct" "$short_pct" "$dt"
fi

# Taker
tk_file="$OUTDIR/${SYMBOL}_taker_5m.csv"
if [ -f "$tk_file" ] && [ "$(wc -l < "$tk_file")" -gt 1 ]; then
  last=$(tail -1 "$tk_file")
  ratio=$(echo "$last" | cut -d',' -f3)
  bvol=$(echo "$last" | cut -d',' -f4)
  svol=$(echo "$last" | cut -d',' -f5)
  dt=$(echo "$last" | cut -d',' -f2)
  printf "  主动买卖:  %-15s (买 %s / 卖 %s) [%s]\n" "$ratio" "$bvol" "$svol" "$dt"
fi

# Liquidation summary
if [ -f "$liq_outfile" ] && [ "$(wc -l < "$liq_outfile")" -gt 1 ]; then
  liq_count=$(($(wc -l < "$liq_outfile") - 1))
  # SELL = 多头被清算(被迫卖出), BUY = 空头被清算(被迫买入)
  sell_count=$(grep -c ",SELL," "$liq_outfile" 2>/dev/null || echo "0")
  buy_count=$(grep -c ",BUY," "$liq_outfile" 2>/dev/null || echo "0")
  printf "  爆仓:      %d 条 (多头爆仓 %s / 空头爆仓 %s)\n" "$liq_count" "$sell_count" "$buy_count"
fi
