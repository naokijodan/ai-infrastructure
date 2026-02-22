#!/usr/bin/env bash
set -euo pipefail

SECRET_PATH="${HOME}/ai-scripts/.webhook-secret"

# If the secret already exists, do nothing
if [[ -f "${SECRET_PATH}" ]]; then
  echo "Secret already exists at ${SECRET_PATH}. Skipping."
  exit 0
fi

# Ensure target directory exists
mkdir -p "$(dirname "${SECRET_PATH}")"

# Check for openssl
if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: openssl is required but not found in PATH." >&2
  exit 1
fi

# Generate 32-byte hex HMAC secret and write with restrictive permissions
openssl rand -hex 32 > "${SECRET_PATH}"
chmod 600 "${SECRET_PATH}"

echo "HMAC secret generated at ${SECRET_PATH}"

