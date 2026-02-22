#!/usr/bin/env bash
set -euo pipefail

# HMAC署名付きWebhookテストスクリプト
# - SECRET を ~/ai-scripts/.webhook-secret から読み込む
# - デフォルトテンプレート: market-check
# - デフォルトworkflow-id: Wbc9jJFq15HgqnGa
# - 引数:
#     --template <name>    テンプレート名を変更
#     --workflow, -w <id>  workflow-id を明示指定
#     <positional>         最初の位置引数を workflow-id として扱う
#     --url <base>         ベースURLを上書き (既定: http://localhost:5678)
#     -h, --help           使い方を表示

TEMPLATE="market-check"
WORKFLOW_ID_DEFAULT="Wbc9jJFq15HgqnGa"
WORKFLOW_ID="$WORKFLOW_ID_DEFAULT"
SECRET_FILE="${HOME}/ai-scripts/.webhook-secret"
BASE_URL="http://localhost:5678"

usage() {
  cat <<USAGE
使い方: $(basename "$0") [--template NAME] [--workflow|-w ID] [--url URL] [WORKFLOW_ID]

オプション:
  --template NAME     送信するテンプレート名 (既定: market-check)
  --workflow, -w ID   workflow-id を明示指定 (位置引数より優先)
  --url URL           ベースURLを上書き (既定: http://localhost:5678)
  -h, --help          このヘルプを表示

位置引数:
  WORKFLOW_ID         送信先の workflow-id。未指定時は既定値を使用

例:
  $(basename "$0")                              # 既定テンプレ + 既定 workflow-id
  $(basename "$0") --template resale-research    # テンプレ変更
  $(basename "$0") -w Wxxxxxxxx --template ai-discussion
  $(basename "$0") Wxxxxxxxx                     # 位置引数で workflow-id 指定
USAGE
}

WORKFLOW_ID_SET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      [[ $# -ge 2 ]] || { echo "Error: --template に値が必要です" >&2; exit 1; }
      TEMPLATE="$2"; shift 2;;
    --workflow|-w)
      [[ $# -ge 2 ]] || { echo "Error: --workflow に値が必要です" >&2; exit 1; }
      WORKFLOW_ID="$2"; WORKFLOW_ID_SET=1; shift 2;;
    --url)
      [[ $# -ge 2 ]] || { echo "Error: --url に値が必要です" >&2; exit 1; }
      BASE_URL="$2"; shift 2;;
    -h|--help)
      usage; exit 0;;
    *)
      if [[ $WORKFLOW_ID_SET -eq 0 ]]; then
        WORKFLOW_ID="$1"; WORKFLOW_ID_SET=1; shift
      else
        echo "Unknown argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
done

if [[ ! -f "$SECRET_FILE" ]]; then
  echo "秘密鍵ファイルが見つかりません: $SECRET_FILE" >&2
  echo "~/ai-scripts/.webhook-secret にHMAC秘密鍵を配置してください。" >&2
  exit 1
fi

# 秘密鍵を読み込み (改行除去)
SECRET=$(tr -d '\r\n' < "$SECRET_FILE")
if [[ -z "$SECRET" ]]; then
  echo "秘密鍵が空です: $SECRET_FILE" >&2
  exit 1
fi

# JSONボディを構築
BODY=$(printf '{"template": "%s"}' "$TEMPLATE")

# HMAC-SHA256 を計算 (hex)
HMAC=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

URL="${BASE_URL%/}/webhook/${WORKFLOW_ID}/webhook/claude-exec-secure"

echo "== Webhook Test =="
echo "Workflow ID : $WORKFLOW_ID"
echo "Template    : $TEMPLATE"
echo "Body        : $BODY"
echo "HMAC        : $HMAC"
echo "URL         : $URL"
echo "----------------------------------------"

# 送信
set -x
curl -sS -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "X-HMAC-Signature: $HMAC" \
  --data "$BODY" \
  --max-time 120 \
  -w "\nHTTP %{http_code}\n"
set +x

