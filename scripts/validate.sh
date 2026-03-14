#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────
# validate.sh — End-to-end validation for the sandboxed Copilot setup
#
# Runs six tests to verify the complete configuration:
#   1. Prerequisites installed
#   2. Certificate exists and is valid
#   3. Azure identity works (service principal login)
#   4. Reader role is assigned
#   5. Write operations are blocked
#   6. Safehouse blocks sensitive directories
#
# Usage:
#   ./scripts/validate.sh
#
# Prerequisites:
#   - terraform apply has been run in terraform/
#   - Agent Safehouse installed
# ──────────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Load credentials ─────────────────────────────────────────────────
ENV_FILE="${REPO_ROOT}/.env.copilot-agent"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

AZURE_CLIENT_CERTIFICATE_PATH="${AZURE_CLIENT_CERTIFICATE_PATH:-${HOME}/.config/copilot-agent/agent-cert.pem}"

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $*"; ((PASS++)); }
fail() { echo "  FAIL: $*"; ((FAIL++)); }
skip() { echo "  SKIP: $*"; ((SKIP++)); }

# ── Test 1: Prerequisites ────────────────────────────────────────────
echo ""
echo "Test 1: Prerequisites"
echo "─────────────────────"

for cmd in az openssl npx; do
  if command -v "$cmd" &>/dev/null; then
    pass "$cmd found"
  else
    fail "$cmd not found"
  fi
done

if command -v safehouse &>/dev/null; then
  pass "safehouse found"
else
  skip "safehouse not found (Safehouse tests will be skipped)"
fi

if command -v copilot &>/dev/null; then
  pass "copilot CLI found"
else
  skip "copilot CLI not found"
fi

# ── Test 2: Certificate ──────────────────────────────────────────────
echo ""
echo "Test 2: Certificate"
echo "────────────────────"

if [[ -f "$AZURE_CLIENT_CERTIFICATE_PATH" ]]; then
  pass "Certificate file exists at ${AZURE_CLIENT_CERTIFICATE_PATH}"

  if openssl x509 -in "$AZURE_CLIENT_CERTIFICATE_PATH" -noout 2>/dev/null; then
    pass "Certificate is a valid PEM"
  else
    fail "Certificate is not a valid PEM file"
  fi

  if openssl x509 -in "$AZURE_CLIENT_CERTIFICATE_PATH" -checkend 0 -noout 2>/dev/null; then
    EXPIRY=$(openssl x509 -in "$AZURE_CLIENT_CERTIFICATE_PATH" -enddate -noout | cut -d= -f2)
    pass "Certificate is not expired (expires: ${EXPIRY})"

    # Warn if expiring within 30 days
    if ! openssl x509 -in "$AZURE_CLIENT_CERTIFICATE_PATH" -checkend 2592000 -noout 2>/dev/null; then
      echo "  WARNING: Certificate expires within 30 days"
    fi
  else
    fail "Certificate is expired"
  fi
else
  fail "Certificate not found at ${AZURE_CLIENT_CERTIFICATE_PATH}"
fi

# ── Test 3: Azure identity ───────────────────────────────────────────
echo ""
echo "Test 3: Azure identity (service principal login)"
echo "─────────────────────────────────────────────────"

if [[ -z "${AZURE_TENANT_ID:-}" || -z "${AZURE_CLIENT_ID:-}" ]]; then
  fail "AZURE_TENANT_ID or AZURE_CLIENT_ID not set"
else
  if az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --certificate "$AZURE_CLIENT_CERTIFICATE_PATH" \
    --tenant "$AZURE_TENANT_ID" \
    --only-show-errors \
    -o none 2>/dev/null; then

    CALLER_ID=$(az account show --query user.name -o tsv 2>/dev/null)
    if [[ "$CALLER_ID" == "$AZURE_CLIENT_ID" ]]; then
      pass "Authenticated as service principal: ${CALLER_ID}"
    else
      fail "Authenticated but identity mismatch: expected ${AZURE_CLIENT_ID}, got ${CALLER_ID}"
    fi
  else
    fail "Service principal login failed"
  fi
fi

# ── Test 4: Reader role assigned ─────────────────────────────────────
echo ""
echo "Test 4: Reader role assignment"
echo "──────────────────────────────"

SUBSCRIPTION_ID=$(az account show --query id -o tsv 2>/dev/null || true)
if [[ -n "$SUBSCRIPTION_ID" ]]; then
  ROLE_COUNT=$(az role assignment list \
    --assignee "${AZURE_CLIENT_ID:-}" \
    --role "Reader" \
    --scope "/subscriptions/${SUBSCRIPTION_ID}" \
    --query "length([])" \
    -o tsv 2>/dev/null || echo "0")

  if [[ "$ROLE_COUNT" -gt 0 ]]; then
    pass "Reader role assigned at subscription scope"
  else
    fail "Reader role not found for service principal on subscription ${SUBSCRIPTION_ID}"
  fi
else
  fail "Could not determine subscription ID"
fi

# ── Test 5: Write is blocked ─────────────────────────────────────────
echo ""
echo "Test 5: Write operations blocked"
echo "─────────────────────────────────"

TEST_RG_NAME="copilot-validate-test-$$"
WRITE_OUTPUT=$(az group create \
  --name "$TEST_RG_NAME" \
  --location westeurope \
  2>&1 || true)

if echo "$WRITE_OUTPUT" | grep -qi "AuthorizationFailed\|does not have authorization\|Forbidden"; then
  pass "Resource group creation blocked (AuthorizationFailed)"
else
  fail "Write operation was NOT blocked. Output: ${WRITE_OUTPUT}"
  # Clean up if it was accidentally created
  az group delete --name "$TEST_RG_NAME" --yes --no-wait 2>/dev/null || true
fi

# ── Test 6: Safehouse blocks sensitive directories ───────────────────
echo ""
echo "Test 6: Safehouse filesystem isolation"
echo "───────────────────────────────────────"

if command -v safehouse &>/dev/null; then
  SAFEHOUSE_POLICY="${REPO_ROOT}/safehouse/local-overrides.sb"

  for SENSITIVE_DIR in ".ssh" ".azure" ".aws"; do
    TARGET="${HOME}/${SENSITIVE_DIR}"
    if [[ -d "$TARGET" ]]; then
      SANDBOX_OUTPUT=$(safehouse \
        --append-profile="$SAFEHOUSE_POLICY" \
        ls "$TARGET" 2>&1 || true)

      if echo "$SANDBOX_OUTPUT" | grep -qi "denied\|not permitted\|Operation not permitted"; then
        pass "Access to ~/${SENSITIVE_DIR} blocked by Safehouse"
      else
        fail "Safehouse did NOT block access to ~/${SENSITIVE_DIR}"
      fi
    else
      skip "~/${SENSITIVE_DIR} does not exist on this machine"
    fi
  done
else
  skip "Safehouse not installed — skipping filesystem isolation tests"
fi

# ── Log out of service principal session ─────────────────────────────
az logout 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ${PASS} passed, ${FAIL} failed, ${SKIP} skipped"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -gt 0 ]]; then
  exit 1
fi
