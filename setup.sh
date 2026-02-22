#!/bin/bash
# setup.sh - AI 5階層インフラ セットアップスクリプト
#
# Phase 1: ヘッドレス実行基盤 + launchd設定
# Phase 2: n8n インストール + 自動起動
#
# 使い方: ./setup.sh [phase1|phase2|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AI_SCRIPTS_DIR="${HOME}/ai-scripts"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"

echo "=== AI 5階層インフラ セットアップ ==="
echo ""

PHASE="${1:-all}"

# --- Phase 1: ヘッドレス実行基盤 ---
setup_phase1() {
  echo "[Phase 1] ヘッドレス実行基盤のセットアップ"
  echo ""

  # ai-scripts ディレクトリ確認
  if [[ -d "${AI_SCRIPTS_DIR}" ]]; then
    echo "  ✓ ~/ai-scripts/ は既に存在"
  else
    echo "  ERROR: ~/ai-scripts/ が見つかりません"
    echo "  先に run-claude.sh とテンプレートを配置してください"
    exit 1
  fi

  # run-claude.sh の実行権限
  if [[ -x "${AI_SCRIPTS_DIR}/run-claude.sh" ]]; then
    echo "  ✓ run-claude.sh は実行可能"
  else
    chmod +x "${AI_SCRIPTS_DIR}/run-claude.sh"
    echo "  ✓ run-claude.sh に実行権限を付与"
  fi

  # claude CLI の確認
  if command -v claude &>/dev/null; then
    echo "  ✓ Claude Code CLI: $(claude --version 2>/dev/null || echo 'installed')"
  else
    echo "  WARNING: claude コマンドが見つかりません"
    echo "  Claude Code CLI をインストールしてください"
  fi

  # テンプレート確認
  TEMPLATE_COUNT=$(ls "${AI_SCRIPTS_DIR}/templates/"*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  ✓ テンプレート: ${TEMPLATE_COUNT}個"

  # logs ディレクトリ
  mkdir -p "${AI_SCRIPTS_DIR}/logs"
  echo "  ✓ logs ディレクトリ準備完了"

  # カウンターファイル初期化
  if [[ ! -f "${AI_SCRIPTS_DIR}/counter.txt" ]]; then
    echo "$(date +%Y-%m-%d)" > "${AI_SCRIPTS_DIR}/counter.txt"
    echo "0" >> "${AI_SCRIPTS_DIR}/counter.txt"
    echo "  ✓ カウンターファイル初期化"
  else
    echo "  ✓ カウンターファイルは既に存在"
  fi

  # launchd 設定のコピー
  echo ""
  echo "  launchd 設定:"
  mkdir -p "${LAUNCH_AGENTS_DIR}"

  for plist in "${SCRIPT_DIR}/launchd/"*.plist; do
    PLIST_NAME="$(basename "${plist}")"
    if [[ -f "${LAUNCH_AGENTS_DIR}/${PLIST_NAME}" ]]; then
      echo "    ⚠ ${PLIST_NAME} は既に存在（スキップ）"
    else
      cp "${plist}" "${LAUNCH_AGENTS_DIR}/"
      echo "    ✓ ${PLIST_NAME} をコピー"
    fi
  done

  echo ""
  echo "[Phase 1] セットアップ完了"
  echo ""
  echo "次のステップ:"
  echo "  1. テスト実行: ~/ai-scripts/run-claude.sh \"テスト\""
  echo "  2. launchd登録: launchctl load ~/Library/LaunchAgents/com.ai.market-check.plist"
  echo ""
}

# --- Phase 2: n8n ---
setup_phase2() {
  echo "[Phase 2] n8n ゲートウェイのセットアップ"
  echo ""

  # Node.js 確認
  if command -v node &>/dev/null; then
    echo "  ✓ Node.js: $(node --version)"
  else
    echo "  ERROR: Node.js が見つかりません"
    echo "  brew install node でインストールしてください"
    exit 1
  fi

  # n8n インストール確認
  if command -v n8n &>/dev/null; then
    echo "  ✓ n8n は既にインストール済み"
  else
    echo "  n8n をインストール中..."
    npm install -g n8n
    echo "  ✓ n8n インストール完了"
  fi

  # n8n 起動テスト
  echo ""
  echo "  n8n の起動テスト（5秒後に停止）..."
  timeout 5 n8n start 2>/dev/null &
  sleep 3

  if curl -s http://localhost:5678 >/dev/null 2>&1; then
    echo "  ✓ n8n が localhost:5678 で応答"
  else
    echo "  ⚠ n8n の応答を確認できませんでした（後で手動確認してください）"
  fi

  # 既存ポートとの競合チェック
  echo ""
  echo "  ポート競合チェック:"
  for PORT in 5678; do
    if lsof -i ":${PORT}" >/dev/null 2>&1; then
      echo "    ⚠ ポート ${PORT} は使用中"
    else
      echo "    ✓ ポート ${PORT} は空き"
    fi
  done

  # launchd 設定
  if [[ -f "${LAUNCH_AGENTS_DIR}/com.n8n.server.plist" ]]; then
    echo "  ✓ n8n launchd設定は既にコピー済み"
  else
    cp "${SCRIPT_DIR}/launchd/com.n8n.server.plist" "${LAUNCH_AGENTS_DIR}/"
    echo "  ✓ n8n launchd設定をコピー"
  fi

  echo ""
  echo "[Phase 2] セットアップ完了"
  echo ""
  echo "次のステップ:"
  echo "  1. n8n起動: n8n start"
  echo "  2. ブラウザで http://localhost:5678 を開く"
  echo "  3. 初回セットアップ（ユーザー登録）を完了"
  echo "  4. Webhookワークフローを作成"
  echo "  5. 自動起動登録: launchctl load ~/Library/LaunchAgents/com.n8n.server.plist"
  echo ""
}

# --- 実行 ---
case "${PHASE}" in
  phase1|1)
    setup_phase1
    ;;
  phase2|2)
    setup_phase2
    ;;
  all)
    setup_phase1
    echo "========================================"
    echo ""
    setup_phase2
    ;;
  *)
    echo "使い方: ./setup.sh [phase1|phase2|all]"
    exit 1
    ;;
esac

echo "=== セットアップ完了 ==="
