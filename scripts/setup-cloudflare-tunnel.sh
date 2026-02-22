#!/usr/bin/env bash

# Cloudflare Tunnel 初期設定スクリプト
#
# 使い方:
#   DOMAIN_NAME=example.com scripts/setup-cloudflare-tunnel.sh
#
# 環境変数:
#   - DOMAIN_NAME: 必須。例) example.com
#   - TUNNEL_NAME: 任意。デフォルト "ai-infra"
#   - PORT:        任意。デフォルト 5678 (ローカルのサービスポート)
#
# 本スクリプトが行うこと:
#   1) cloudflared の認証確認 (~/.cloudflared/cert.pem)
#   2) 未認証なら cloudflared tunnel login を実行（ブラウザで認証）
#   3) トンネル作成（存在すればスキップ）: cloudflared tunnel create ai-infra
#   4) 設定ファイル (~/.cloudflared/config.yml) 生成
#      - tunnel: ai-infra
#      - credentials-file: ~/.cloudflared/<tunnel-id>.json
#      - ingress:
#        - hostname: ai-infra.${DOMAIN_NAME} → http://localhost:${PORT}
#        - service: http_status:404
#   5) DNS 設定: cloudflared tunnel route dns ai-infra ai-infra.${DOMAIN_NAME}
#   6) launchd の plist 作成・登録: ~/Library/LaunchAgents/com.cloudflare.tunnel.plist
#      - 実行コマンド: cloudflared tunnel run ai-infra
#      - KeepAlive: true
#      - ログ: ~/ai-scripts/logs/cloudflared.log
#   7) 最後に接続テスト（ingress 設定の検証）
#
# 事前要件:
#   - macOS + launchd
#   - cloudflared がインストール済み（brew install cloudflared 等）

set -euo pipefail

info()  { printf "[INFO] %s\n" "$*"; }
warn()  { printf "[WARN] %s\n" "$*"; }
error() { printf "[ERROR] %s\n" "$*" 1>&2; }
die()   { error "$*"; exit 1; }

# ===== 入力/環境変数 =====
DOMAIN_NAME="${DOMAIN_NAME:-}"
TUNNEL_NAME="${TUNNEL_NAME:-ai-infra}"
PORT="${PORT:-5678}"

# ===== 前提チェック =====
command -v cloudflared >/dev/null 2>&1 || die "cloudflared が見つかりません。インストールしてください。"

[ -n "$DOMAIN_NAME" ] || die "DOMAIN_NAME が未設定です。例: DOMAIN_NAME=example.com"

CONFIG_DIR="$HOME/.cloudflared"
CONFIG_FILE="$CONFIG_DIR/config.yml"
mkdir -p "$CONFIG_DIR"

# 1) 認証チェック
CERT_FILE="$CONFIG_DIR/cert.pem"
if [ ! -f "$CERT_FILE" ]; then
  info "Cloudflare 認証が見つかりません。ブラウザで認証します..."
  cloudflared tunnel login || die "cloudflared tunnel login に失敗しました。"
  [ -f "$CERT_FILE" ] || die "認証ファイルが作成されませんでした: $CERT_FILE"
else
  info "認証済みを確認しました: $CERT_FILE"
fi

# 3) トンネルの作成（冪等）
if cloudflared tunnel info "$TUNNEL_NAME" >/dev/null 2>&1; then
  info "トンネル '$TUNNEL_NAME' は既に存在します。作成をスキップします。"
else
  info "トンネル '$TUNNEL_NAME' を作成します..."
  cloudflared tunnel create "$TUNNEL_NAME" || die "トンネル作成に失敗しました。"
fi

# トンネル ID の取得
TUNNEL_ID="$(cloudflared tunnel info "$TUNNEL_NAME" 2>/dev/null | awk -F': *' '/^ID:/ {print $2; exit}')"
if [ -z "$TUNNEL_ID" ]; then
  # フォールバック: list の 2列目(ID)を使用
  TUNNEL_ID="$(cloudflared tunnel list 2>/dev/null | awk -v name="$TUNNEL_NAME" '$1==name {print $2; exit}')"
fi
[ -n "$TUNNEL_ID" ] || die "トンネル ID を特定できませんでした。"

CRED_FILE="$CONFIG_DIR/$TUNNEL_ID.json"
[ -f "$CRED_FILE" ] || die "認証クレデンシャルが見つかりません: $CRED_FILE"

# 4) 設定ファイル生成
HOSTNAME="ai-infra.$DOMAIN_NAME"
cat > "$CONFIG_FILE" <<YAML
tunnel: $TUNNEL_NAME
credentials-file: $CRED_FILE
ingress:
  - hostname: $HOSTNAME
    service: http://localhost:$PORT
  - service: http_status:404
YAML
info "設定ファイルを生成しました: $CONFIG_FILE"

# 5) DNS 設定（冪等対応）
info "DNS を設定します: $HOSTNAME → トンネル '$TUNNEL_NAME'"
DNS_TMP_LOG="$(mktemp)"
set +e
cloudflared tunnel route dns "$TUNNEL_NAME" "$HOSTNAME" >"$DNS_TMP_LOG" 2>&1
DNS_RC=$?
set -e
if [ $DNS_RC -eq 0 ]; then
  info "DNS レコードを作成しました。"
else
  if grep -qi "already exists\|existe déjà\|bereits vorhanden\|ya existe" "$DNS_TMP_LOG"; then
    info "DNS レコードは既に存在します。スキップします。"
  else
    error "DNS 設定に失敗しました。出力:\n$(cat "$DNS_TMP_LOG")"
    rm -f "$DNS_TMP_LOG"
    exit 1
  fi
fi
rm -f "$DNS_TMP_LOG"

# 7) launchd plist 生成
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.cloudflare.tunnel.plist"
LOG_DIR="$HOME/ai-scripts/logs"
mkdir -p "$PLIST_DIR" "$LOG_DIR"

CLOUDFLARED_BIN="$(command -v cloudflared)"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.cloudflare.tunnel</string>
  <key>ProgramArguments</key>
  <array>
    <string>$CLOUDFLARED_BIN</string>
    <string>tunnel</string>
    <string>run</string>
    <string>$TUNNEL_NAME</string>
  </array>
  <key>KeepAlive</key>
  <true/>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/cloudflared.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/cloudflared.log</string>
  <key>WorkingDirectory</key>
  <string>$HOME</string>
</dict>
</plist>
PLIST
info "launchd plist を作成しました: $PLIST_PATH"

# 8) launchctl へ登録（冪等対応）
LAUNCH_ID="gui/$(id -u)"
AGENT_LABEL="com.cloudflare.tunnel"
AGENT_PATH="$LAUNCH_ID/$AGENT_LABEL"

if launchctl print "$AGENT_PATH" >/dev/null 2>&1; then
  info "LaunchAgent は既にロードされています。再起動します。"
  set +e
  launchctl kickstart -k "$AGENT_PATH" >/dev/null 2>&1
  set -e
else
  info "LaunchAgent を bootstrap します。"
  set +e
  launchctl bootstrap "$LAUNCH_ID" "$PLIST_PATH" >/dev/null 2>&1
  BOOT_RC=$?
  set -e
  if [ $BOOT_RC -ne 0 ]; then
    warn "bootstrap に失敗しました。enable/kickstart を試みます。"
    set +e
    launchctl enable "$AGENT_PATH" >/dev/null 2>&1
    launchctl kickstart -k "$AGENT_PATH" >/dev/null 2>&1
    set -e
  fi
fi

# 11) 接続テスト（ingress 検証）
info "ingress 設定を検証します..."
if cloudflared tunnel ingress validate --config "$CONFIG_FILE"; then
  info "ingress 設定の検証に成功しました。"
else
  die "ingress 設定の検証に失敗しました。"
fi

info "セットアップが完了しました。"
printf "- ローカル確認: curl http://localhost:%s\n" "$PORT"
printf "- 公開URL: https://%s (DNS 反映まで時間がかかる場合があります)\n" "$HOSTNAME"

