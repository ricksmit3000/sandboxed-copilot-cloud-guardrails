#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ROLE_ARN="${ROLE_ARN:-}"
DURATION=900
AWS_REGION="${AWS_REGION:-eu-west-1}"
SESSION_NAME="copilot-sandbox-$(date +%s)"

usage() {
  cat <<'USAGE'
Usage:
  eval "$(./scripts/vend-token.sh [--role-arn ARN] [--duration SECONDS] [--region REGION])"

Assumes the sandbox role explicitly and prints shell exports for AWS_ACCESS_KEY_ID,
AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_DEFAULT_REGION, and AWS_REGION.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

resolve_role_arn() {
  if [[ -n "${ROLE_ARN}" ]]; then
    printf '%s\n' "${ROLE_ARN}"
    return 0
  fi

  if command -v terraform >/dev/null 2>&1; then
    terraform -chdir="${REPO_ROOT}/terraform" output -raw role_arn
    return 0
  fi

  echo "error: unable to determine role ARN automatically; pass --role-arn or set ROLE_ARN." >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --session-name)
      SESSION_NAME="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! [[ "${DURATION}" =~ ^[0-9]+$ ]]; then
  echo "error: --duration must be an integer number of seconds." >&2
  exit 1
fi

if (( DURATION < 900 || DURATION > 43200 )); then
  echo "error: --duration must be between 900 and 43200 seconds." >&2
  exit 1
fi

require_command aws
require_command jq
ROLE_ARN="$(resolve_role_arn)"

response="$(aws sts assume-role \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "${SESSION_NAME}" \
  --duration-seconds "${DURATION}" \
  --output json)"

access_key_id="$(jq -r '.Credentials.AccessKeyId' <<<"${response}")"
secret_access_key="$(jq -r '.Credentials.SecretAccessKey' <<<"${response}")"
session_token="$(jq -r '.Credentials.SessionToken' <<<"${response}")"
expiration="$(jq -r '.Credentials.Expiration' <<<"${response}")"

printf 'export AWS_ACCESS_KEY_ID=%q\n' "${access_key_id}"
printf 'export AWS_SECRET_ACCESS_KEY=%q\n' "${secret_access_key}"
printf 'export AWS_SESSION_TOKEN=%q\n' "${session_token}"
printf 'export AWS_DEFAULT_REGION=%q\n' "${AWS_REGION}"
printf 'export AWS_REGION=%q\n' "${AWS_REGION}"

echo "Assumed ${ROLE_ARN} until ${expiration}." >&2
