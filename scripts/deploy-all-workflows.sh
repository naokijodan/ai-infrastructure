#!/usr/bin/env bash

set -uo pipefail

# Config
BASE_URL=${N8N_BASE_URL:-"http://localhost:5678/rest"}
API_KEY=${N8N_KEY:-}
WORKDIR="n8n-workflows"

if [[ -z "$API_KEY" ]]; then
  echo "[ERROR] N8N_KEY is not set. Export N8N_KEY and retry." >&2
  exit 1
fi

if [[ ! -d "$WORKDIR" ]]; then
  echo "[ERROR] Directory '$WORKDIR' not found." >&2
  exit 1
fi

have_jq=0
if command -v jq >/dev/null 2>&1; then
  have_jq=1
fi

extract_name() {
  local file="$1"
  if [[ $have_jq -eq 1 ]]; then
    jq -r .name "$file"
  else
    python3 - "$file" <<'PY'
import json,sys
with open(sys.argv[1], 'r') as f:
    print(json.load(f).get('name',''))
PY
  fi
}

extract_id_by_name() {
  local json="$1" name="$2"
  if [[ $have_jq -eq 1 ]]; then
    echo "$json" | jq -r --arg n "$name" '.data[] | select(.name==$n) | .id' | head -n1
  else
    python3 - "$name" <<'PY'
import json,sys
name=sys.argv[1]
data=json.loads(sys.stdin.read())
for w in data.get('data',[]):
    if w.get('name')==name:
        print(w.get('id',''))
        break
PY
  fi
}

created=0
skipped=0
activated=0

for f in "$WORKDIR"/*.json; do
  [[ -e "$f" ]] || continue
  name="$(extract_name "$f")"
  if [[ -z "$name" || "$name" == "null" ]]; then
    echo "[WARN] Could not read name from $f; skipping." >&2
    ((skipped++))
    continue
  fi

  echo "\n[INFO] Processing: $name ($f)"

  # Check if exists
  list_json=$(curl -sS -H "X-N8N-API-KEY: $API_KEY" "$BASE_URL/workflows?limit=9999") || {
    echo "[ERROR] Failed to list workflows" >&2; exit 1; }
  wid=$(extract_id_by_name "$list_json" "$name")

  if [[ -n "$wid" ]]; then
    echo "[INFO] Workflow exists (id=$wid); skipping create."
    ((skipped++))
  else
    echo "[INFO] Creating workflow..."
    create_resp=$(curl -sS -X POST "$BASE_URL/workflows" \
      -H "X-N8N-API-KEY: $API_KEY" \
      -H "Content-Type: application/json" \
      --data-binary @"$f")
    # Try to extract id
    if [[ $have_jq -eq 1 ]]; then
      wid=$(echo "$create_resp" | jq -r '.id // .data.id // empty')
    else
      wid=$(python3 - <<'PY'
import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get('id') or (d.get('data') or {}).get('id') or '')
except Exception:
    print('')
PY
<<<"$create_resp")
    fi
    if [[ -z "$wid" ]]; then
      echo "[ERROR] Failed to create workflow or parse id. Response:" >&2
      echo "$create_resp" >&2
      exit 1
    fi
    echo "[INFO] Created with id=$wid"
    ((created++))
  fi

  echo "[INFO] Activating workflow id=$wid ..."
  activate_resp=$(curl -sS -X PATCH "$BASE_URL/workflows/$wid" \
    -H "X-N8N-API-KEY: $API_KEY" \
    -H "Content-Type: application/json" \
    --data '{"active": true}') || {
      echo "[ERROR] Activation request failed for id=$wid" >&2; exit 1; }
  echo "[INFO] Activated"
  ((activated++))
done

echo "\n===== Deployment Summary ====="
echo "Created:   $created"
echo "Skipped:   $skipped"
echo "Activated: $activated"

exit 0

