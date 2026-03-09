#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WORKSPACE_PATH="$(pwd)"
PROFILE_NAME="copilot-sandbox"
AWS_REGION="${AWS_REGION:-eu-west-1}"
AWS_CONFIG_PATH="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"
DEFAULT_TEMPLATE="copilot-aws-sandbox:latest"
SANDBOX_TEMPLATE="${COPILOT_SANDBOX_TEMPLATE:-}"
USE_EXPLICIT=false
DURATION=900

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-sandbox.sh [--explicit] [--duration SECONDS] [--region REGION] [WORKSPACE]

Launches a Docker sandbox running the Copilot agent with AWS credentials.
- Default mode mounts ~/.aws read-only and sets AWS_PROFILE=copilot-sandbox.
- --explicit forces vend-token.sh and injects short-lived AWS_* environment variables.
USAGE
}

profile_exists() {
  [[ -f "${AWS_CONFIG_PATH}" ]] && grep -Fqx "[profile ${PROFILE_NAME}]" "${AWS_CONFIG_PATH}"
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

if ! command -v docker >/dev/null 2>&1; then
  echo "error: docker is required to launch the sandbox." >&2
  exit 1
fi

if [[ "${USE_EXPLICIT}" == false ]] && ! profile_exists; then
  echo "No ${PROFILE_NAME} profile found in ${AWS_CONFIG_PATH}; falling back to explicit token vending." >&2
  USE_EXPLICIT=true
fi

command=(docker sandbox run)
if template="$(resolve_template)"; [[ -n "${template}" ]]; then
  command+=(--template "${template}")
fi

if [[ "${USE_EXPLICIT}" == true ]]; then
  eval "$("${SCRIPT_DIR}/vend-token.sh" --duration "${DURATION}" --region "${AWS_REGION}")"
  command+=(-e "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}")
  command+=(-e "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}")
  command+=(-e "AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}")
  command+=(-e "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}")
  command+=(-e "AWS_REGION=${AWS_REGION}")
else
  command+=(-v "${HOME}/.aws:/home/agent/.aws:ro")
  command+=(-e "AWS_PROFILE=${PROFILE_NAME}")
  command+=(-e "AWS_DEFAULT_REGION=${AWS_REGION}")
  command+=(-e "AWS_REGION=${AWS_REGION}")
fi

command+=(copilot "${WORKSPACE_PATH}")

if [[ "${WORKSPACE_PATH}" == "${REPO_ROOT}" && -f "${REPO_ROOT}/sandbox/copilot-config.json" ]]; then
  command+=(-- --config sandbox/copilot-config.json --yolo)
else
  command+=(-- --yolo)
fi

printf 'Launching sandbox command:\n  '
printf '%q ' "${command[@]}"
printf '\n'

if [[ "${USE_EXPLICIT}" == true ]]; then
  echo "Reminder: explicit credentials expire after ${DURATION} seconds; rerun this script when the session expires." >&2
fi

exec "${command[@]}"
