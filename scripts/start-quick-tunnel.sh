#!/usr/bin/env bash

# Cloudflare Quick Tunnel（trycloudflare.com）で n8n を外部公開するスクリプト
#
# 使い方:
#   - フォアグラウンド実行（URLを検出して表示、ログも出力）
#       scripts/start-quick-tunnel.sh
#
#   - バックグラウンド実行（デーモン化、PID保存、URL/ログ保存）
#       scripts/start-quick-tunnel.sh --daemon
#
#   - 停止（PIDファイルからプロセスを kill）
#       scripts/start-quick-tunnel.sh --stop
#
#   - ステータス（現在のURL表示とプロセス確認）
#       scripts/start-quick-tunnel.sh --status
#
# 注意: Quick Tunnel は再起動すると公開URLが変わります。

set -euo pipefail

info()  { printf "[INFO] %s\n" "$*"; }
warn()  { printf "[WARN] %s\n" "$*"; }
error() { printf "[ERROR] %s\n" "$*" 1>&2; }
die()   { error "$*"; exit 1; }

command -v cloudflared >/dev/null 2>&1 || die "cloudflared が見つかりません。インストールしてください (brew install cloudflared 等)。"

BASE_DIR="$HOME/ai-scripts"
LOG_DIR="$BASE_DIR/logs"
URL_FILE="$BASE_DIR/.tunnel-url"
PID_FILE="$BASE_DIR/.tunnel-pid"
LOG_FILE="$LOG_DIR/cloudflared.log"

PORT="5678"
TARGET_URL="http://localhost:${PORT}"

mkdir -p "$BASE_DIR" "$LOG_DIR"

extract_url_from_file() {
  # ログ/出力から trycloudflare のURLを抽出
  # 例: https://xxxx.trycloudflare.com
  local file="$1"
  grep -Eo 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$file" | head -n 1 || true
}

save_url() {
  local url="$1"
  if [ -n "$url" ]; then
    printf "%s\n" "$url" >"$URL_FILE"
    info "公開URL: $url"
  fi
}

poll_url_from_log() {
  # ログからURLを待ち受けて保存・表示する（最大60秒）
  local timeout_sec="${1:-60}"
  local i
  for i in $(seq 1 "$timeout_sec"); do
    if [ -f "$LOG_FILE" ]; then
      local url
      url="$(extract_url_from_file "$LOG_FILE")"
      if [ -n "$url" ]; then
        save_url "$url"
        return 0
      fi
    fi
    sleep 1
  done
  warn "公開URLを検出できませんでした。ログを確認してください: $LOG_FILE"
  return 1
}

is_running() {
  # PIDファイルのプロセスが生存しているか
  [ -f "$PID_FILE" ] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [ -n "$pid" ] || return 1
  if kill -0 "$pid" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

start_daemon() {
  if is_running; then
    info "既に起動しています。PID: $(cat "$PID_FILE")"
    [ -f "$URL_FILE" ] && info "現在の公開URL: $(cat "$URL_FILE")"
    exit 0
  fi

  info "Quick Tunnel をバックグラウンド起動します（nohup）..."
  : >"$LOG_FILE"  # ログを初期化
  nohup cloudflared tunnel --url "$TARGET_URL" >>"$LOG_FILE" 2>&1 &
  local pid=$!
  printf "%s\n" "$pid" >"$PID_FILE"
  info "PID を保存しました: $PID_FILE ($(cat "$PID_FILE"))"

  # URL抽出を待機
  if poll_url_from_log 60; then
    info "起動完了。ログ: $LOG_FILE"
  else
    warn "URL検出に失敗しましたが、プロセスは起動している可能性があります。ログをご確認ください。"
  fi
}

start_foreground() {
  if is_running; then
    warn "バックグラウンド実行中のインスタンスが検出されました（PID: $(cat "$PID_FILE")）。"
    warn "フォアグラウンド起動の前に '--stop' を実行することを推奨します。"
  fi

  info "Quick Tunnel をフォアグラウンド起動します... (Ctrl+Cで停止)"
  info "ログ: $LOG_FILE"

  # URL検出をバックグラウンドでポーリング
  poll_url_from_log 60 &
  local poll_pid=$!
  trap 'kill "$poll_pid" >/dev/null 2>&1 || true' EXIT INT TERM

  # cloudflared を実行しつつログへ tee
  # cloudflared の出力をそのまま表示し、同時にログへ書き込み
  # 終了時、URLファイルは残ります（新規URL検出時に上書き）
  cloudflared tunnel --url "$TARGET_URL" 2>&1 | tee -a "$LOG_FILE"
}

do_stop() {
  if ! [ -f "$PID_FILE" ]; then
    warn "PIDファイルがありません: $PID_FILE"
    [ -f "$URL_FILE" ] && rm -f "$URL_FILE"
    exit 0
  fi
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [ -z "$pid" ]; then
    warn "PIDファイルが空です。削除します。"
    rm -f "$PID_FILE"
    [ -f "$URL_FILE" ] && rm -f "$URL_FILE"
    exit 0
  fi
  if kill -0 "$pid" >/dev/null 2>&1; then
    info "プロセスを停止します: PID $pid"
    kill "$pid" || true
    sleep 1
    if kill -0 "$pid" >/dev/null 2>&1; then
      warn "強制終了します: PID $pid"
      kill -9 "$pid" || true
    fi
  else
    warn "PID $pid のプロセスは存在しません。"
  fi
  rm -f "$PID_FILE"
  [ -f "$URL_FILE" ] && rm -f "$URL_FILE"
  info "停止しました。"
}

do_status() {
  local running="no"
  if is_running; then
    running="yes"
  fi
  info "プロセス稼働: $running"
  if [ -f "$PID_FILE" ]; then
    info "PID: $(cat "$PID_FILE")"
  fi
  if [ -f "$URL_FILE" ]; then
    info "現在の公開URL: $(cat "$URL_FILE")"
  else
    info "公開URL: (未検出)"
  fi
  info "ログ: $LOG_FILE"
}

case "${1:-}" in
  --daemon)
    start_daemon
    ;;
  --stop)
    do_stop
    ;;
  --status)
    do_status
    ;;
  "" )
    start_foreground
    ;;
  *)
    cat <<USAGE
使い方:
  scripts/start-quick-tunnel.sh            # フォアグラウンド実行
  scripts/start-quick-tunnel.sh --daemon   # バックグラウンド実行（nohup/PID保存）
  scripts/start-quick-tunnel.sh --stop     # 停止（PIDから kill）
  scripts/start-quick-tunnel.sh --status   # ステータス（URL/プロセス確認）

メモ: Quick Tunnel は再起動ごとに公開URLが変わります。
USAGE
    exit 1
    ;;
esac

