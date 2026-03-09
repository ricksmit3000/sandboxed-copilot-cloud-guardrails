#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE_NAME="copilot-sandbox"
SOURCE_PROFILE="${SOURCE_PROFILE:-}"
AWS_REGION="${AWS_REGION:-eu-west-1}"
SESSION_DURATION=3600
ROLE_ARN="${ROLE_ARN:-}"
AWS_CONFIG_PATH="${AWS_CONFIG_FILE:-${HOME}/.aws/config}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/setup-profile.sh [--role-arn ARN] [--source-profile NAME] [--region REGION] [--duration SECONDS]

Creates the [profile copilot-sandbox] entry used by the recommended local flow.
If --role-arn is omitted, the script reads terraform output from ./terraform.
If --source-profile is omitted, the script prefers AWS_PROFILE, then default, then a single existing non-target profile.
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

resolve_source_profile() {
  local configured_profiles=()

  if [[ -n "${SOURCE_PROFILE}" ]]; then
    printf '%s\n' "${SOURCE_PROFILE}"
    return 0
  fi

  if [[ -n "${AWS_PROFILE:-}" ]]; then
    printf '%s\n' "${AWS_PROFILE}"
    return 0
  fi

  if command -v aws >/dev/null 2>&1; then
    mapfile -t configured_profiles < <(aws configure list-profiles 2>/dev/null | grep -Fxv "${PROFILE_NAME}" || true)
  fi

  if printf '%s\n' "${configured_profiles[@]}" | grep -Fxq "default"; then
    printf '%s\n' "default"
    return 0
  fi

  if [[ "${#configured_profiles[@]}" -eq 1 ]]; then
    printf '%s\n' "${configured_profiles[0]}"
    return 0
  fi

  echo "error: could not determine a source profile; pass --source-profile explicitly." >&2
  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role-arn)
      ROLE_ARN="$2"
      shift 2
      ;;
    --source-profile)
      SOURCE_PROFILE="$2"
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
SOURCE_PROFILE="$(resolve_source_profile)"
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
