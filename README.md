# sandboxed-copilot-cloud-guardrails

> Give your AI coding agent cloud access with guardrails - not the keys to the kingdom.

This repository demonstrates how to give GitHub Copilot short-lived, read-only AWS access without handing over broad, persistent credentials. It combines Docker Sandbox isolation with a Terraform-provisioned IAM role that both local sandboxes and GitHub-hosted coding agents can assume.

## What this repo demonstrates

Three execution paths share one AWS guardrail:

| Path | Agent runtime | Isolation layer | Cloud auth mechanism |
| --- | --- | --- | --- |
| Local (profile) | Copilot in Docker Sandbox | Docker Desktop sandbox | AWS CLI profile that auto-assumes the Terraform role |
| Local (explicit) | Copilot in Docker Sandbox | Docker Desktop sandbox | `vend-token.sh` issuing STS credentials as environment variables |
| GitHub-hosted | Copilot coding agent in GitHub Actions | GitHub-hosted runner | GitHub OIDC + `aws-actions/configure-aws-credentials` |

## Architecture

```text
Developer workstation
  |
  +-- ~/.aws/config
  |     [profile copilot-sandbox]
  |     role_arn = arn:aws:iam::<account>:role/CopilotSandboxReadOnly
  |     source_profile = default
  |
  +-- scripts/run-sandbox.sh
        -> docker sandbox run copilot ...
        -> mount ~/.aws read-only OR inject AWS_* env vars
        -> Copilot can call aws s3 ls / aws ec2 describe-*
        -> IAM denies write operations

GitHub-hosted path
  |
  +-- .github/workflows/copilot-setup-steps.yml
        -> GitHub OIDC token
        -> STS AssumeRoleWithWebIdentity
        -> AWS_* exposed to the coding agent job

AWS account
  |
  +-- GitHub OIDC provider
  +-- CopilotSandboxReadOnly IAM role
        -> trust: local principal + GitHub OIDC
        -> permissions: ReadOnlyAccess
        -> max session duration: configurable
```

## Prerequisites

- Docker Desktop with Docker Sandbox support
- GitHub Copilot access
- Terraform 1.5+
- AWS account and an IAM principal that can create roles and OIDC providers
- AWS CLI for local workflows
- `jq` for the explicit token-vending path

## Repository layout

```text
terraform/                  AWS provider, IAM role, OIDC provider, outputs, tfvars example
scripts/                    Local setup, token vending, and sandbox launch helpers
sandbox/                    Dockerfile for a custom sandbox image and Copilot config
.github/workflows/          Hosted setup and Terraform validation workflows
.github/copilot/agents/     Custom agent persona for read-only cloud discovery
.copilot/                   Local MCP placeholder configuration
examples/                   Demo prompts and expected outcomes
docs/                       Architecture, threat model, and extension notes
```

## Quick start: local profile path (recommended)

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars
terraform -chdir=terraform init
terraform -chdir=terraform apply
./scripts/setup-profile.sh
./scripts/run-sandbox.sh
```

Why this is the recommended path:

- The AWS CLI handles `AssumeRole` automatically.
- Temporary credentials are cached and refreshed for you.
- The sandbox never receives long-lived keys directly.

## Quick start: local explicit path

```bash
eval "$(./scripts/vend-token.sh)"
./scripts/run-sandbox.sh --explicit
```

Use this when you want to teach the mechanics of STS directly or when mounting `~/.aws` into the sandbox is not practical.

## Quick start: GitHub-hosted path

1. Apply the Terraform stack and capture the `role_arn` output.
2. In GitHub, create an environment named `copilot`.
3. Add an environment variable named `AWS_ROLE_ARN` with the Terraform output value.
4. Keep `.github/workflows/copilot-setup-steps.yml` on the default branch.
5. Assign an issue to Copilot coding agent.

## Building the optional custom sandbox image

The local runner script will automatically use `copilot-aws-sandbox:latest` when that image exists.

```bash
docker build -t copilot-aws-sandbox:latest sandbox
```

That image layers AWS CLI v2 and `jq` onto Docker's Copilot sandbox base image.

## Credential strategies

| Strategy | Best for | Auto-refresh | Trade-offs |
| --- | --- | --- | --- |
| AWS profile | Daily use and demos | Yes | Requires mounting `~/.aws` read-only into the sandbox |
| Explicit STS vending | Teaching and constrained environments | No | Credentials expire and must be re-vended |
| GitHub OIDC | Hosted issue workflows | Per workflow run | Requires Actions and repo environment setup |

## Demo walkthroughs

- [Demo 1: Read succeeds with S3](examples/01-read-s3.md)
- [Demo 2: Read succeeds across EC2 and security groups](examples/02-read-ec2.md)
- [Demo 3: Write fails with AccessDenied](examples/03-write-fails.md)
- [Demo 4: Explicit credentials expire](examples/04-creds-expire.md)

## Important implementation note: existing GitHub OIDC providers

This repo keeps Terraform simple. If your AWS account already has `token.actions.githubusercontent.com` configured, import it into Terraform state instead of creating a duplicate:

```bash
terraform -chdir=terraform import \
  aws_iam_openid_connect_provider.github_actions \
  arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
```

## Further reading

- [Architecture](docs/architecture.md)
- [Threat model](docs/threat-model.md)
- [Local vs hosted](docs/local-vs-hosted.md)
- [Extending the pattern](docs/extending.md)

## What is intentionally out of scope for v1

- A custom least-privilege IAM policy
- Multi-account role chaining
- CloudTrail session tagging and dashboards
- Non-AWS cloud providers

These are covered as extension points in `docs/extending.md`.
