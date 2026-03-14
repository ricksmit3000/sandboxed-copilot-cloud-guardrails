#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/adopt-company-managed-identity.sh TARGET_PROJECT_DIR TENANT_ID CLIENT_ID [CERTIFICATE_PATH]

Example:
  ./scripts/adopt-company-managed-identity.sh ~/dev/my-app 00000000-0000-0000-0000-000000000000 11111111-1111-1111-1111-111111111111

This copies the local integration files needed for a company-managed Azure identity setup:
  - safehouse/
  - .copilot/mcp.json
  - .env.copilot-agent

The Azure identity itself must already exist and must already have the correct RBAC role.
EOF
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
  usage >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET_DIR="$1"
TENANT_ID="$2"
CLIENT_ID="$3"
CERT_PATH="${4:-$HOME/.config/copilot-agent/agent-cert.pem}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "Error: target directory does not exist: $TARGET_DIR" >&2
  exit 1
fi

if [[ ! -d "${REPO_ROOT}/safehouse" ]]; then
  echo "Error: safehouse directory not found in repo" >&2
  exit 1
fi

if [[ ! -f "${REPO_ROOT}/.copilot/mcp.json" ]]; then
  echo "Error: .copilot/mcp.json not found in repo" >&2
  exit 1
fi

if [[ -e "${TARGET_DIR}/safehouse" ]]; then
  echo "Error: target already has safehouse/: ${TARGET_DIR}/safehouse" >&2
  exit 1
fi

if [[ -e "${TARGET_DIR}/.copilot/mcp.json" ]]; then
  echo "Error: target already has .copilot/mcp.json: ${TARGET_DIR}/.copilot/mcp.json" >&2
  exit 1
fi

if [[ -e "${TARGET_DIR}/.env.copilot-agent" ]]; then
  echo "Error: target already has .env.copilot-agent: ${TARGET_DIR}/.env.copilot-agent" >&2
  exit 1
fi

mkdir -p "${TARGET_DIR}/.copilot"
cp -R "${REPO_ROOT}/safehouse" "${TARGET_DIR}/safehouse"
cp "${REPO_ROOT}/.copilot/mcp.json" "${TARGET_DIR}/.copilot/mcp.json"

cat > "${TARGET_DIR}/.env.copilot-agent" <<EOF
export AZURE_TENANT_ID="${TENANT_ID}"
export AZURE_CLIENT_ID="${CLIENT_ID}"
export AZURE_CLIENT_CERTIFICATE_PATH="${CERT_PATH}"
EOF

chmod 600 "${TARGET_DIR}/.env.copilot-agent"

cat <<EOF
Adopted company-managed Azure identity setup into: ${TARGET_DIR}

Created:
  - ${TARGET_DIR}/safehouse
  - ${TARGET_DIR}/.copilot/mcp.json
  - ${TARGET_DIR}/.env.copilot-agent

Next steps in the target project:
  1. Confirm the certificate exists at: ${CERT_PATH}
  2. source safehouse/copilot-safehouse.sh
  3. copilot-safe
EOF