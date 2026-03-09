# Architecture

This repository demonstrates a defense-in-depth pattern for giving GitHub Copilot controlled access to AWS. The design combines runtime isolation with short-lived, read-only cloud credentials.

## Layers

1. **Runtime isolation**: Copilot runs inside a Docker Sandbox rather than directly on the developer workstation.
2. **Credential scoping**: AWS access comes from an IAM role that only allows `ReadOnlyAccess`.
3. **Short-lived sessions**: Both local and hosted paths use STS-based temporary credentials.
4. **Trust pinning**: GitHub-hosted access is limited to a specific repository through OIDC trust conditions.

## Architecture diagram

```text
Developer workstation
  |
  +-- ~/.aws/config profile (recommended local path)
  |     -> AWS CLI auto-assumes the sandbox role
  |
  +-- vend-token.sh (explicit local path)
  |     -> aws sts assume-role
  |     -> temporary AWS_* environment variables
  |
  +-- scripts/run-sandbox.sh
        -> docker sandbox run copilot ...
        -> mounts ~/.aws read-only OR injects temporary env vars

GitHub-hosted path
  |
  +-- .github/workflows/copilot-setup-steps.yml
        -> GitHub OIDC token
        -> aws-actions/configure-aws-credentials
        -> STS AssumeRoleWithWebIdentity
        -> AWS_* available to the coding agent

AWS account
  |
  +-- aws_iam_openid_connect_provider.github_actions
  +-- aws_iam_role.copilot_sandbox_read_only
        -> trust: local principal + GitHub OIDC
        -> permissions: ReadOnlyAccess
        -> max session duration: configurable
```

## Local path details

### Recommended: profile-based access

`setup-profile.sh` writes a dedicated AWS CLI profile named `copilot-sandbox`. When the sandbox runs with `AWS_PROFILE=copilot-sandbox`, the AWS CLI automatically assumes the Terraform-provisioned role, caches credentials in `~/.aws/cli/cache`, and refreshes them when needed.

### Explicit: token vending

`vend-token.sh` exposes the STS call directly. It prints `export` statements for `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`, `AWS_DEFAULT_REGION`, and `AWS_REGION` so you can inject them into a short-lived sandbox session.

## Hosted path details

The hosted path uses `.github/workflows/copilot-setup-steps.yml`. GitHub Actions exchanges an OIDC token for AWS credentials by assuming the same IAM role. The trust policy pins that path to the configured GitHub org and repository.

## Existing GitHub OIDC providers

This repo keeps Terraform simple: `terraform/iam-oidc-github.tf` manages a single `aws_iam_openid_connect_provider.github_actions` resource. If your AWS account already has the GitHub provider, import it into state instead of creating a duplicate:

```bash
terraform -chdir=terraform import \
  aws_iam_openid_connect_provider.github_actions \
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```
