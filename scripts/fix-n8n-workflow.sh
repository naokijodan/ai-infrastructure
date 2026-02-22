#!/usr/bin/env bash
set -euo pipefail

# This script updates the n8n workflow `mzHX9kY2kOHROtA2`, replacing the
# Execute Command node with a Code node as specified.

KEY_FILE="$HOME/ai-scripts/.n8n-api-key"
WORKFLOW_ID="mzHX9kY2kOHROtA2"
API_URL="http://localhost:5678/api/v1/workflows/${WORKFLOW_ID}"

# Node IDs (fixed by requirement)
WEBHOOK_NODE_ID="d43c1688-cb5d-46b8-916e-26a49cbf5b0a"
EXECUTE_NODE_ID="74371254-70f2-4b91-83f1-864d8c871fe1"
RESPOND_NODE_ID="e643d56f-4b1f-4487-88f1-5c62f2d1e964"

# Dependencies check
if ! command -v curl >/dev/null 2>&1; then
  echo "Error: curl is required." >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Error: API key file not found at $KEY_FILE" >&2
  exit 1
fi
N8N_KEY="$(tr -d '\n' < "$KEY_FILE")"

# Fetch current workflow
WORKFLOW_JSON="$(
  curl -s -H "X-N8N-API-KEY: $N8N_KEY" "$API_URL"
)"

if [[ -z "$WORKFLOW_JSON" ]]; then
  echo "Error: Failed to fetch workflow JSON." >&2
  exit 1
fi

# Extract existing node names for the given IDs to keep them intact in connections
WEBHOOK_NAME="$(jq -r --arg id "$WEBHOOK_NODE_ID" '(.nodes[] | select(.id==$id) | .name) // empty' <<< "$WORKFLOW_JSON")"
RESPOND_NAME="$(jq -r --arg id "$RESPOND_NODE_ID" '(.nodes[] | select(.id==$id) | .name) // empty' <<< "$WORKFLOW_JSON")"
EXECUTE_PRESENT_COUNT="$(jq -r --arg id "$EXECUTE_NODE_ID" '[.nodes[] | select(.id==$id)] | length' <<< "$WORKFLOW_JSON")"

if [[ -z "$WEBHOOK_NAME" ]]; then
  echo "Error: Webhook node with ID $WEBHOOK_NODE_ID not found." >&2
  exit 1
fi
if [[ -z "$RESPOND_NAME" ]]; then
  echo "Error: Respond to Webhook node with ID $RESPOND_NODE_ID not found." >&2
  exit 1
fi
if [[ "$EXECUTE_PRESENT_COUNT" == "0" ]]; then
  echo "Error: Execute Claude node with ID $EXECUTE_NODE_ID not found." >&2
  exit 1
fi

# The desired jsCode for the Code node
read -r -d '' JS_CODE <<'EOF' || true
const { execSync } = require('child_process');
const template = $input.first().json.body.template || 'market-check';
const cmd = '/Users/naokijodan/ai-scripts/run-claude.sh --template ' + template;
try {
  const result = execSync(cmd, { timeout: 300000, encoding: 'utf-8' });
  return [{ json: { success: true, output: result } }];
} catch(e) {
  return [{ json: { success: false, error: e.message } }];
}
EOF

# Update the workflow JSON per requirements
UPDATED_JSON="$(
  jq \
    --arg jsCode "$JS_CODE" \
    --arg execId "$EXECUTE_NODE_ID" \
    --arg execName "Execute Claude" \
    --arg webhookName "$WEBHOOK_NAME" \
    --arg respondName "$RESPOND_NAME" \
    --argjson pos '[500,300]' \
    '
    .settings = ((.settings // {}) + {executionOrder:"v1", callerPolicy:"workflowsFromSameOwner"})
    | .nodes = (
        .nodes
        | map(
            if .id == $execId then
              {
                parameters: {
                  jsCode: $jsCode,
                  language: "javaScript",
                  mode: "runOnceForAllItems"
                },
                id: $execId,
                name: $execName,
                type: "n8n-nodes-base.code",
                typeVersion: 2,
                position: $pos
              }
            else
              .
            end
          )
      )
    | .connections = {
        ($webhookName): {
          "main": [[ { "node": $execName, "type": "main", "index": 0 } ]]
        },
        ($execName): {
          "main": [[ { "node": $respondName, "type": "main", "index": 0 } ]]
        }
      }
    | del(.id, .createdAt, .updatedAt, .versionId, .activeVersionId, .versionCounter, .triggerCount, .shared, .tags, .activeVersion, .meta, .pinData, .staticData, .isArchived, .description, .active)
    ' <<< "$WORKFLOW_JSON"
)"

# PUT the updated workflow back to n8n and print the result
RESULT="$(
  curl -s -X PUT \
    -H "Content-Type: application/json" \
    -H "X-N8N-API-KEY: $N8N_KEY" \
    -d "$UPDATED_JSON" \
    "$API_URL"
)"

echo "$RESULT"
echo "Success: Updated workflow $WORKFLOW_ID and replaced Execute Claude node with Code node."

