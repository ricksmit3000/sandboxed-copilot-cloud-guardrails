#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE_NAME="copilot-sandbox"
SOURCE_PROFILE="default"
AWS_REGION="${AWS_REGION:-eu-west-1}"
SESSION_DURATION=3600
ROLE_ARN="${ROLE_ARN:-}"
AWS_CONFIG_PATH="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/setup-profile.sh [--role-arn ARN] [--region REGION] [--duration SECONDS]

Creates the [profile copilot-sandbox] entry used by the recommended local flow.
If --role-arn is omitted, the script reads terraform output from ./terraform.
USAGE
}

resolve_role_arn() {
  if [[ -n "${ROLE_ARN}" ]]; then
    printf '%s\n' "${ROLE_ARN}"
    return 0
  fi

  if ! command -v terraform >/dev/null 2>&1; then
    echo "error: terraform is required to discover role_arn automatically; pass --role-arn instead." >&2
    return 1
  fi

  terraform -chdir="${REPO_ROOT}/terraform" output -raw role_arn
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --duration)
      SESSION_DURATION="$2"
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

if ! [[ "${SESSION_DURATION}" =~ ^[0-9]+$ ]]; then
  echo "error: --duration must be an integer number of seconds." >&2
  exit 1
fi

ROLE_ARN="$(resolve_role_arn)"
PROFILE_HEADER="[profile ${PROFILE_NAME}]"

mkdir -p "$(dirname "${AWS_CONFIG_PATH}")"
touch "${AWS_CONFIG_PATH}"

if grep -Fqx "${PROFILE_HEADER}" "${AWS_CONFIG_PATH}"; then
  echo "Profile ${PROFILE_NAME} already exists in ${AWS_CONFIG_PATH}; leaving it unchanged." >&2
  exit 0
fi

cat >> "${AWS_CONFIG_PATH}" <<EOF_PROFILE

${PROFILE_HEADER}
role_arn = ${ROLE_ARN}
source_profile = ${SOURCE_PROFILE}
role_session_name = copilot-sandbox
region = ${AWS_REGION}
duration_seconds = ${SESSION_DURATION}
EOF_PROFILE

echo "Added ${PROFILE_NAME} to ${AWS_CONFIG_PATH}." >&2
echo "Next steps:" >&2
echo "  export AWS_PROFILE=${PROFILE_NAME}" >&2
echo "  aws sts get-caller-identity" >&2
echo "  ./scripts/run-sandbox.sh" >&2
