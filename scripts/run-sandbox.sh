#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_PATH="$(pwd)"
PROFILE_NAME="copilot-sandbox"
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_CONFIG_PATH="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"
HOST_AWS_DIR="${HOME}/.aws"
DEFAULT_TEMPLATE="copilot-aws-sandbox:latest"
SANDBOX_TEMPLATE="${COPILOT_SANDBOX_TEMPLATE:-}"
SANDBOX_NAME="${COPILOT_SANDBOX_NAME:-}"
USE_EXPLICIT=false
DURATION=900

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-sandbox.sh [--explicit] [--duration SECONDS] [--region REGION] [WORKSPACE]

Launches a Docker sandbox running the Copilot agent with AWS credentials.
- Default mode stages ~/.aws into the sandbox and makes the read-only role the sandbox default profile.
- --explicit forces vend-token.sh and writes short-lived AWS credentials into the sandbox.
USAGE
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

profile_exists() {
  [[ -f "${AWS_CONFIG_PATH}" ]] && grep -Fqx "[profile ${PROFILE_NAME}]" "${AWS_CONFIG_PATH}"
}

sandbox_exists() {
  docker sandbox ls | awk 'NR > 1 { print $1 }' | grep -Fxq "${SANDBOX_NAME}"
}

resolve_template() {
  if [[ -n "${SANDBOX_TEMPLATE}" ]]; then
    printf '%s\n' "${SANDBOX_TEMPLATE}"
    return 0
  fi

  if command -v docker >/dev/null 2>&1 && docker image inspect "${DEFAULT_TEMPLATE}" >/dev/null 2>&1; then
    printf '%s\n' "${DEFAULT_TEMPLATE}"
  fi
}

resolve_sandbox_name() {
  local workspace_basename

  if [[ -n "${SANDBOX_NAME}" ]]; then
    printf '%s\n' "${SANDBOX_NAME}"
    return 0
  fi

  workspace_basename="$(basename "${WORKSPACE_PATH}")"
  workspace_basename="$(printf '%s' "${workspace_basename}" | tr -cs '[:alnum:]._+-' '-')"
  printf 'copilot-%s\n' "${workspace_basename}"
}

create_sandbox() {
  local template
  local command=(docker sandbox create --name "${SANDBOX_NAME}")

  if template="$(resolve_template)"; [[ -n "${template}" ]]; then
    command+=(--template "${template}")
  fi

  command+=(copilot "${WORKSPACE_PATH}")

  if [[ "${USE_EXPLICIT}" == false ]]; then
    command+=("${HOST_AWS_DIR}:ro")
  fi

  "${command[@]}"
}

ensure_sandbox() {
  if ! sandbox_exists; then
    create_sandbox
    return 0
  fi

  if [[ "${USE_EXPLICIT}" == false ]] && ! docker sandbox exec "${SANDBOX_NAME}" sh -lc "test -f $(printf '%q' "${HOST_AWS_DIR}/config")" >/dev/null 2>&1; then
    echo "Existing sandbox ${SANDBOX_NAME} is missing the mounted host AWS config; recreating it." >&2
    docker sandbox rm "${SANDBOX_NAME}" >/dev/null
    create_sandbox
  fi
}

prepare_profile_mode() {
  local profile_role_arn
  local profile_source_profile
  local profile_session_name
  local profile_duration

  require_command aws

  profile_role_arn="$(aws configure get "profile.${PROFILE_NAME}.role_arn")"
  profile_source_profile="$(aws configure get "profile.${PROFILE_NAME}.source_profile")"
  profile_session_name="$(aws configure get "profile.${PROFILE_NAME}.role_session_name")"
  profile_duration="$(aws configure get "profile.${PROFILE_NAME}.duration_seconds")"

  if [[ -z "${profile_role_arn}" || -z "${profile_source_profile}" ]]; then
    echo "error: profile ${PROFILE_NAME} is missing role_arn or source_profile in ${AWS_CONFIG_PATH}." >&2
    exit 1
  fi

  if [[ -z "${profile_session_name}" ]]; then
    profile_session_name="copilot-sandbox"
  fi

  if [[ -z "${profile_duration}" ]]; then
    profile_duration="3600"
  fi

  docker sandbox exec \
    --env HOST_AWS_DIR="${HOST_AWS_DIR}" \
    --env PROFILE_ROLE_ARN="${profile_role_arn}" \
    --env PROFILE_SOURCE_PROFILE="${profile_source_profile}" \
    --env PROFILE_SESSION_NAME="${profile_session_name}" \
    --env PROFILE_DURATION="${profile_duration}" \
    --env AWS_REGION="${AWS_REGION}" \
    "${SANDBOX_NAME}" \
    sh -lc '
      set -euo pipefail
      rm -rf "$HOME/.aws"
      mkdir -p "$HOME/.aws"
      cp -R "$HOST_AWS_DIR"/. "$HOME/.aws"/
      awk '\''BEGIN { skip = 0 } /^\[default\]$/ { skip = 1; next } /^\[/ { if (skip) { skip = 0 } } !skip { print }'\'' "$HOME/.aws/config" > "$HOME/.aws/config.tmp"
      cat >> "$HOME/.aws/config.tmp" <<EOF

[default]
role_arn = $PROFILE_ROLE_ARN
source_profile = $PROFILE_SOURCE_PROFILE
role_session_name = $PROFILE_SESSION_NAME
region = $AWS_REGION
duration_seconds = $PROFILE_DURATION
EOF
      mv "$HOME/.aws/config.tmp" "$HOME/.aws/config"
      chmod 700 "$HOME/.aws"
      find "$HOME/.aws" -type d -exec chmod 700 {} +
      find "$HOME/.aws" -type f -exec chmod 600 {} +
    '
}

prepare_explicit_mode() {
  eval "$(${SCRIPT_DIR}/vend-token.sh --duration "${DURATION}" --region "${AWS_REGION}")"

  docker sandbox exec \
    --env AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" \
    --env AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    --env AWS_SESSION_TOKEN="${AWS_SESSION_TOKEN}" \
    --env AWS_REGION="${AWS_REGION}" \
    "${SANDBOX_NAME}" \
    sh -lc '
      set -euo pipefail
      mkdir -p "$HOME/.aws"
      cat > "$HOME/.aws/credentials" <<EOF
[default]
aws_access_key_id = $AWS_ACCESS_KEY_ID
aws_secret_access_key = $AWS_SECRET_ACCESS_KEY
aws_session_token = $AWS_SESSION_TOKEN
EOF
      cat > "$HOME/.aws/config" <<EOF
[default]
region = $AWS_REGION
EOF
      chmod 700 "$HOME/.aws"
      chmod 600 "$HOME/.aws/credentials" "$HOME/.aws/config"
    '
}

ensure_aws_cli_in_sandbox() {
  local template

  if docker sandbox exec "${SANDBOX_NAME}" sh -lc 'command -v aws >/dev/null 2>&1'; then
    return 0
  fi

  template="$(resolve_template)"
  if [[ -n "${template}" ]]; then
    echo "Existing sandbox ${SANDBOX_NAME} is missing the AWS CLI; recreating it with template ${template}." >&2
    docker sandbox rm "${SANDBOX_NAME}" >/dev/null
    create_sandbox

    if docker sandbox exec "${SANDBOX_NAME}" sh -lc 'command -v aws >/dev/null 2>&1'; then
      return 0
    fi
  fi

  echo "error: the sandbox image does not include the AWS CLI." >&2
  echo "Build the custom template first: docker build -t ${DEFAULT_TEMPLATE} sandbox" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --explicit)
      USE_EXPLICIT=true
      shift
      ;;
    --duration)
      DURATION="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "${WORKSPACE_PATH_OVERRIDE:-}" && "$1" != --* ]]; then
        WORKSPACE_PATH_OVERRIDE="$1"
        shift
      else
        echo "error: unknown argument: $1" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

if [[ -n "${WORKSPACE_PATH_OVERRIDE:-}" ]]; then
  WORKSPACE_PATH="${WORKSPACE_PATH_OVERRIDE}"
fi

WORKSPACE_PATH="$(cd "${WORKSPACE_PATH}" && pwd)"
SANDBOX_NAME="$(resolve_sandbox_name)"

require_command docker

if [[ "${USE_EXPLICIT}" == false ]] && ! profile_exists; then
  echo "No ${PROFILE_NAME} profile found in ${AWS_CONFIG_PATH}; falling back to explicit token vending." >&2
  USE_EXPLICIT=true
fi

ensure_sandbox

if [[ "${USE_EXPLICIT}" == true ]]; then
  prepare_explicit_mode
else
  prepare_profile_mode
fi

ensure_aws_cli_in_sandbox

command=(docker sandbox run "${SANDBOX_NAME}" -- --yolo)

printf 'Launching sandbox command:\n  '
printf '%q ' "${command[@]}"
printf '\n'

if [[ "${USE_EXPLICIT}" == true ]]; then
  echo "Reminder: explicit credentials expire after ${DURATION} seconds; rerun this script when the session expires." >&2
fi

exec "${command[@]}"
