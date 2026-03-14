#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# copilot-safehouse.sh — Launch Copilot CLI inside Agent Safehouse
#
# Source this file in your .zshrc to get the `copilot-safe` function,
# or run it directly as a script.
#
# Usage:
#   source safehouse/copilot-safehouse.sh   # defines copilot-safe()
#   copilot-safe                            # interactive session
#   copilot-safe -p "list resource groups"  # one-shot prompt
#
# Escape hatch (unsandboxed):
#   command copilot                         # bypasses the wrapper
#
# Prerequisites:
#   - Agent Safehouse installed (brew install eugene1g/safehouse/agent-safehouse)
#   - Copilot CLI installed
#   - .env.copilot-agent file (created by: terraform -chdir=terraform apply)
#     OR AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_CERTIFICATE_PATH set
# ──────────────────────────────────────────────────────────────────────

# Resolve paths relative to this script
_SAFEHOUSE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SAFEHOUSE_REPO_ROOT="$(cd "${_SAFEHOUSE_SCRIPT_DIR}/.." && pwd)"
_SAFEHOUSE_POLICY="${_SAFEHOUSE_SCRIPT_DIR}/local-overrides.sb"

# ── Load credentials ─────────────────────────────────────────────────
# Source .env.copilot-agent if it exists and env vars are not already set
_SAFEHOUSE_ENV_FILE="${_SAFEHOUSE_REPO_ROOT}/.env.copilot-agent"
if [[ -z "${AZURE_TENANT_ID:-}" && -f "$_SAFEHOUSE_ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$_SAFEHOUSE_ENV_FILE"
fi

# Default certificate path
export AZURE_CLIENT_CERTIFICATE_PATH="${AZURE_CLIENT_CERTIFICATE_PATH:-${HOME}/.config/copilot-agent/agent-cert.pem}"

# Force EnvironmentCredential only — prevent fallback to az login, interactive
# browser, managed identity, or any other credential type in the chain.
export AZURE_TOKEN_CREDENTIALS="EnvironmentCredential"

# ── copilot-safe function ────────────────────────────────────────────
copilot-safe() {
  # Validate prerequisites
  if ! command -v safehouse &>/dev/null; then
    echo "Error: Agent Safehouse not found. Install with:" >&2
    echo "  brew install eugene1g/safehouse/agent-safehouse" >&2
    return 1
  fi

  if ! command -v copilot &>/dev/null; then
    echo "Error: Copilot CLI not found." >&2
    return 1
  fi

  if [[ -z "${AZURE_TENANT_ID:-}" ]]; then
    echo "Error: AZURE_TENANT_ID not set. Run: terraform -chdir=terraform apply" >&2
    return 1
  fi

  if [[ -z "${AZURE_CLIENT_ID:-}" ]]; then
    echo "Error: AZURE_CLIENT_ID not set. Run: terraform -chdir=terraform apply" >&2
    return 1
  fi

  if [[ ! -f "${AZURE_CLIENT_CERTIFICATE_PATH}" ]]; then
    echo "Error: Certificate not found at ${AZURE_CLIENT_CERTIFICATE_PATH}" >&2
    echo "Run: terraform -chdir=terraform apply" >&2
    return 1
  fi

  safehouse \
    --add-dirs="$HOME/.copilot" \
    --add-dirs-ro="$HOME/.config/copilot-agent" \
    --add-dirs-ro="$HOME/.config/gh" \
    --append-profile="${_SAFEHOUSE_POLICY}" \
    copilot --dangerously-skip-permissions "$@"
}
