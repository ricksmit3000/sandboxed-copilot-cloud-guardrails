# Plan: `sandboxed-copilot-cloud-guardrails`

> Give your AI coding agent cloud access with guardrails — not the keys to the kingdom.

## 1. What this repo demonstrates

A reference implementation showing how to safely grant AI coding agents (GitHub Copilot) scoped, short-lived access to AWS — using Docker Sandboxes for OS-level isolation and Terraform-provisioned IAM roles for cloud-level guardrails.

Two execution paths and two local credential strategies are covered:

| Path | Agent runtime | Isolation layer | Cloud auth mechanism |
|------|--------------|-----------------|---------------------|
| **Local (profile)** | Copilot CLI in Docker Sandbox (microVM) | Docker Desktop sandbox | AWS CLI profile with `role_arn` → auto-assumes on every call, auto-refreshes |
| **Local (explicit)** | Copilot CLI in Docker Sandbox (microVM) | Docker Desktop sandbox | `vend-token.sh` → STS AssumeRole → env vars injected into sandbox |
| **GitHub-hosted** | Copilot coding agent (GitHub Actions) | GitHub's runner VM | `copilot-setup-steps.yml` → OIDC federation → STS AssumeRole |

All paths assume the **same Terraform-provisioned IAM role** — one set of guardrails, multiple execution contexts.

**Local credential strategy at a glance:**

| Strategy | Best for | Auto-refresh? | Setup effort | Transparency |
|----------|----------|---------------|--------------|-------------|
| **AWS profile** (recommended) | Daily use, live demos | Yes — AWS CLI handles it | One-time `setup-profile.sh` | Magic — you don't see the STS call |
| **vend-token.sh** (explicit) | Teaching, understanding the mechanics, environments where profile mounting doesn't work | No — creds expire, re-run script | None | Full visibility — you see every step |

---

## 2. Target audience

- Platform / DevOps engineers evaluating how to let AI agents interact with cloud environments safely
- Solution Engineers demoing enterprise-grade agent workflows (hi, that's us)
- Teams already using Copilot CLI or coding agent who want to add cloud access without handing over admin credentials

---

## 3. Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     Developer Workstation                         │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  ~/.aws/config                                             │  │
│  │  [profile copilot-sandbox]                                 │  │
│  │  role_arn = ...CopilotSandboxReadOnly                      │  │
│  │  source_profile = default                                  │  │
│  │  duration_seconds = 3600                                   │  │
│  └──────────────────────┬─────────────────────────────────────┘  │
│                         │ mounted read-only into sandbox         │
│                         ▼                                        │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Docker Sandbox (microVM)                                  │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  Copilot CLI + AWS CLI                               │  │  │
│  │  │                                                      │  │  │
│  │  │  AWS_PROFILE=copilot-sandbox                         │  │  │
│  │  │  → CLI auto-calls sts:AssumeRole under the hood      │  │  │
│  │  │  → creds cached in ~/.aws/cli/cache                  │  │  │
│  │  │  → auto-refreshed when expired                       │  │  │
│  │  │                                                      │  │  │
│  │  │  Can: aws s3 ls ✓                                   │  │  │
│  │  │  Can: aws ec2 describe* ✓                           │  │  │
│  │  │  Cannot: aws s3 mb ✗                                │  │  │
│  │  │  Cannot: aws ec2 run* ✗                             │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                              │
                    STS AssumeRole (auto, up to 1h TTL)
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────┐
│                        AWS Account                               │
│                                                                  │
│  IAM Role: CopilotSandboxReadOnly                               │
│  ├── Trust: developer IAM user/role OR GitHub OIDC               │
│  ├── Permission: arn:aws:iam::aws:policy/ReadOnlyAccess          │
│  └── Max session: 3600s (1h) — configurable                     │
│                                                                  │
│  Resources (read-only targets):                                 │
│  ├── S3 buckets                                                 │
│  ├── EC2 instances                                              │
│  ├── CloudWatch metrics                                         │
│  └── ... (anything ReadOnlyAccess covers)                       │
└──────────────────────────────────────────────────────────────────┘
```

**Alternative local path — explicit token vending (for teaching / fallback):**

```
┌─────────────────────────────────────────────────────────────┐
│  Developer runs: eval $(./scripts/vend-token.sh)            │
│  → calls aws sts assume-role                                │
│  → parses JSON, exports AWS_ACCESS_KEY_ID etc.              │
│  → passes env vars into docker sandbox run -e ...           │
│  → credentials expire after TTL, must re-run script         │
└─────────────────────────────────────────────────────────────┘
```

This path is included so you can show customers exactly what STS AssumeRole does — every step visible, no magic. Useful for workshops and for environments where mounting `~/.aws` into the sandbox isn't practical.

**For the GitHub-hosted path** (Copilot coding agent), replace the left side with:

```
┌──────────────────────────────────────────────────┐
│  GitHub Actions Runner                           │
│  ┌────────────────────────────────────────────┐  │
│  │ copilot-setup-steps.yml                    │  │
│  │  → OIDC token from GitHub                  │  │
│  │  → aws-actions/configure-aws-credentials   │  │
│  │  → STS AssumeRoleWithWebIdentity           │  │
│  │  → exports AWS_* env vars                  │  │
│  └────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────┐  │
│  │ Copilot coding agent                       │  │
│  │  → reads AWS_* from environment            │  │
│  │  → uses AWS MCP server for cloud queries   │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

---

## 4. Repo structure

```
sandboxed-copilot-cloud-guardrails/
│
├── README.md                              # Landing page — problem, architecture, quickstart
│
├── terraform/
│   ├── main.tf                            # AWS provider config, backend (local state for demo)
│   ├── variables.tf                       # trusted_principal_arn, session_duration, region, github_org, github_repo
│   ├── iam-role.tf                        # The read-only IAM role + trust policy
│   ├── iam-oidc-github.tf                 # GitHub OIDC identity provider (for coding agent path)
│   ├── outputs.tf                         # role_arn, assume_role_command, oidc_provider_arn
│   └── terraform.tfvars.example           # Fill-in-the-blanks for user's own values
│
├── scripts/
│   ├── setup-profile.sh                   # One-time: writes [profile copilot-sandbox] to ~/.aws/config
│   ├── vend-token.sh                      # Explicit: STS AssumeRole → exports AWS_* env vars (teaching/fallback)
│   └── run-sandbox.sh                     # Launches sandbox — auto-detects profile or env var creds
│
├── sandbox/
│   ├── Dockerfile                         # Custom template: copilot base + awscli + jq
│   └── copilot-config.json                # Trusted folders for --yolo mode
│
├── .github/
│   ├── workflows/
│   │   ├── validate-terraform.yml         # CI: terraform fmt -check + validate + tflint
│   │   └── copilot-setup-steps.yml        # Coding agent: OIDC login + AWS creds
│   └── copilot/
│       └── agents/
│           └── cloud-reader.md            # Custom agent persona: "you have read-only AWS access"
│
├── .copilot/
│   └── mcp.json                           # MCP server config (for Copilot CLI local path)
│
├── examples/
│   ├── 01-read-s3.md                      # Demo: "List S3 buckets, check versioning"
│   ├── 02-read-ec2.md                     # Demo: "Describe EC2 instances + security groups"
│   ├── 03-write-fails.md                  # Demo: "Create S3 bucket" → AccessDenied (the aha moment)
│   └── 04-creds-expire.md                 # Demo: wait 15 min → creds expire → agent gets error
│
├── docs/
│   ├── architecture.md                    # Detailed explanation + diagrams
│   ├── threat-model.md                    # What this protects against, and what it doesn't
│   ├── local-vs-hosted.md                 # Decision guide: when to use which path
│   └── extending.md                       # Add write perms, other clouds, custom policies
│
└── LICENSE                                # MIT
```

---

## 5. Detailed file specifications

### 5.1 Terraform — `terraform/iam-role.tf`

Creates the IAM role `CopilotSandboxReadOnly` with a dual trust policy:

```hcl
# Trust policy allows BOTH:
# 1. A specific IAM user/role (for local sandbox path)
# 2. GitHub OIDC provider (for coding agent path)
#
# Permission: AWS-managed ReadOnlyAccess
# Max session duration: var.session_duration (default 3600 = 1h)
```

**Trust policy principals:**
- `arn:aws:iam::<account>:user/<developer>` — for the local `vend-token.sh` path
- `arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com` — for the GitHub Actions OIDC path

**Trust policy conditions (GitHub OIDC):**
- `StringEquals` on `token.actions.githubusercontent.com:aud` = `sts.amazonaws.com`
- `StringLike` on `token.actions.githubusercontent.com:sub` = `repo:<org>/<repo>:*`

This ensures only your specific repo's Actions can assume the role.

**Attached policy:** `arn:aws:iam::aws:policy/ReadOnlyAccess`

### 5.2 Terraform — `terraform/iam-oidc-github.tf`

Creates the GitHub OIDC identity provider in the AWS account. This is the one-time setup that enables GitHub Actions to exchange their OIDC token for AWS credentials without storing any secrets.

```hcl
# aws_iam_openid_connect_provider for token.actions.githubusercontent.com
# Thumbprint list from GitHub's well-known OIDC config
# Audience: sts.amazonaws.com
```

### 5.3 Terraform — `terraform/variables.tf`

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `aws_region` | string | `eu-west-1` | AWS region |
| `trusted_principal_arn` | string | — (required) | IAM user/role ARN allowed to assume the sandbox role (local path) |
| `github_org` | string | — (required) | GitHub org for OIDC trust condition |
| `github_repo` | string | — (required) | GitHub repo for OIDC trust condition |
| `session_duration` | number | `3600` | Max session duration in seconds (min 900, max 43200) |
| `role_name` | string | `CopilotSandboxReadOnly` | Name of the IAM role |

### 5.4 Terraform — `terraform/outputs.tf`

| Output | Value | Purpose |
|--------|-------|---------|
| `role_arn` | Role ARN | Used by both `vend-token.sh` and `copilot-setup-steps.yml` |
| `assume_role_command` | Complete `aws sts assume-role` CLI command | Copy-paste convenience |
| `oidc_provider_arn` | OIDC provider ARN | Reference for debugging |

### 5.5 Scripts — `scripts/setup-profile.sh` (recommended local path)

```bash
#!/usr/bin/env bash
# One-time setup: creates an AWS CLI profile that auto-assumes the sandbox role.
#
# Usage:
#   ./scripts/setup-profile.sh                              # reads role_arn from terraform output
#   ./scripts/setup-profile.sh --role-arn arn:aws:iam::..   # explicit ARN
#
# What it does:
#   1. Reads the role ARN from terraform output (or --role-arn flag)
#   2. Appends a [profile copilot-sandbox] block to ~/.aws/config
#   3. Prints next steps
#
# After running this once, you never need to manually vend tokens again.
```

**Appends to `~/.aws/config`:**

```ini
[profile copilot-sandbox]
role_arn = arn:aws:iam::123456789012:role/CopilotSandboxReadOnly
source_profile = default
role_session_name = copilot-sandbox
region = eu-west-1
duration_seconds = 3600
```

**How it works under the hood:** When any AWS CLI command uses `--profile copilot-sandbox` (or `AWS_PROFILE=copilot-sandbox`), the CLI automatically calls `sts:AssumeRole` using the credentials from the `default` profile, gets temporary credentials, caches them in `~/.aws/cli/cache`, and refreshes them transparently when they expire. The developer never sees the STS call — it just works.

**Safety details:**
- The script checks if `[profile copilot-sandbox]` already exists before appending (idempotent)
- The `source_profile = default` means it uses whatever credentials the developer already has configured — no new secrets stored
- `duration_seconds = 3600` means each cached session lasts up to 1 hour before the CLI re-assumes

### 5.6 Scripts — `scripts/vend-token.sh` (explicit path — for teaching and fallback)

```bash
#!/usr/bin/env bash
# Explicitly assumes the CopilotSandboxReadOnly role via STS.
# Outputs: eval-able export statements for AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
#
# PURPOSE: This script exists for two reasons:
#   1. Teaching — show customers exactly what STS AssumeRole does, step by step
#   2. Fallback — for environments where mounting ~/.aws into the sandbox isn't practical
#
# For daily use, prefer the profile-based approach (setup-profile.sh).
#
# Usage:
#   eval $(./scripts/vend-token.sh)
#   eval $(./scripts/vend-token.sh --duration 1800)   # 30 min
#   eval $(./scripts/vend-token.sh --role-arn arn:aws:iam::123:role/Custom)
#
# Prerequisites:
#   - aws CLI configured with credentials that can call sts:AssumeRole
#   - jq installed
#   - ROLE_ARN env var set (or pass --role-arn)
```

**Flow:**
1. Read role ARN from `ROLE_ARN` env var, `--role-arn` flag, or `terraform output -raw role_arn`
2. Generate session name: `copilot-sandbox-$(date +%s)`
3. Call `aws sts assume-role` with `--duration-seconds`
4. Parse JSON with `jq`
5. Print `export AWS_ACCESS_KEY_ID=...` etc. to stdout
6. Print expiration timestamp to stderr (visible to developer, not captured by `eval`)

### 5.7 Scripts — `scripts/run-sandbox.sh`

```bash
#!/usr/bin/env bash
# Launch a sandboxed Copilot with AWS cloud access.
# Auto-detects which credential strategy to use.
#
# Usage:
#   ./scripts/run-sandbox.sh                        # current directory
#   ./scripts/run-sandbox.sh ~/my-project           # specific workspace
#   ./scripts/run-sandbox.sh --explicit              # force vend-token.sh path
#   ./scripts/run-sandbox.sh --duration 1800        # custom duration (explicit path only)
```

**Flow:**
1. Check which credential strategy to use:
   - **Default (profile):** If `~/.aws/config` contains `[profile copilot-sandbox]`, mount `~/.aws` read-only and set `AWS_PROFILE`
   - **Explicit (env vars):** If `--explicit` flag is passed, or no profile found, run `vend-token.sh` first and inject env vars
2. Launch `docker sandbox run` with the appropriate flags:
   - Profile path: `-v ~/.aws:/home/agent/.aws:ro -e AWS_PROFILE=copilot-sandbox`
   - Explicit path: `-e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_DEFAULT_REGION`
3. Custom template flag if `sandbox/Dockerfile` has been built
4. Workspace path argument
5. If using explicit path, print expiration reminder

### 5.8 Sandbox — `sandbox/Dockerfile`

```dockerfile
FROM docker/sandbox-templates:copilot

USER root

# AWS CLI v2 for cloud interaction
RUN apt-get update && \
    apt-get install -y unzip curl jq && \
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

USER agent
```

Kept minimal — just adds AWS CLI v2 and jq on top of the Copilot base image.

### 5.9 GitHub Actions — `.github/workflows/copilot-setup-steps.yml`

This is the coding agent path. When Copilot coding agent picks up an issue, it runs this workflow to get AWS credentials before doing anything else.

```yaml
name: "Copilot Setup Steps"
on: workflow_dispatch

permissions:
  id-token: write    # Required for OIDC
  contents: read

jobs:
  copilot-setup-steps:
    runs-on: ubuntu-latest
    environment: copilot
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: eu-west-1
          role-session-name: copilot-coding-agent-${{ github.run_id }}
          role-duration-seconds: 900

      - name: Verify identity
        run: aws sts get-caller-identity

      - name: Install AWS CLI tools
        run: |
          # Already installed on ubuntu-latest, just verify
          aws --version
```

**Required repo configuration:**
- Environment named `copilot`
- Environment variable `AWS_ROLE_ARN` set to the Terraform output

### 5.10 Custom Agent — `.github/copilot/agents/cloud-reader.md`

```markdown
You are a cloud infrastructure reader. You have read-only access to an
AWS account via the AWS CLI. Your job is to answer questions about cloud
resources by running AWS CLI commands.

Rules:
- Only use read operations (describe, list, get)
- Never attempt to create, modify, or delete resources
- If asked to make changes, explain that you only have read-only access
- Always show the AWS CLI command you're running before showing results
- Summarize findings in a clear, structured format
```

This gives the coding agent a persona that reinforces the guardrails at the prompt level (defense in depth — IAM denies writes even if the agent ignores this instruction).

### 5.11 MCP Config — Repository settings (for coding agent path)

Added via GitHub UI under Settings → Copilot → Coding agent → MCP configuration:

```json
{
  "mcpServers": {
    "github-mcp-server": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/readonly",
      "tools": ["*"],
      "headers": {
        "X-MCP-Toolsets": "repos,issues,pull_requests"
      }
    }
  }
}
```

This gives the coding agent read-only access to the repo's own issues and PRs via MCP, separate from the AWS access. Documented but not strictly required for the AWS demo.

### 5.12 MCP Config — `.copilot/mcp.json` (for local CLI path)

```json
{
  "mcpServers": {}
}
```

Placeholder — the local path relies on `aws` CLI commands directly rather than an AWS MCP server. Documented as an extension point for teams that want to wire in the Azure MCP server or similar.

---

## 6. Demo scenarios

### Demo 1 — Read succeeds (S3)

**Prompt to agent:** *"List all S3 buckets in this account. For each bucket, check if versioning is enabled and report the results in a markdown table."*

**Expected behavior:** Agent runs `aws s3api list-buckets` → `aws s3api get-bucket-versioning` per bucket → produces a table. All read operations succeed.

### Demo 2 — Read succeeds (cross-service)

**Prompt:** *"Show me all running EC2 instances in eu-west-1. Include instance type, launch time, and the security group names attached to each."*

**Expected behavior:** Agent chains `aws ec2 describe-instances --filters "Name=instance-state-name,Values=running"` → parses security group IDs → `aws ec2 describe-security-groups` → produces a summary.

### Demo 3 — Write fails (the guardrail moment)

**Prompt:** *"Create a new S3 bucket called copilot-demo-test-bucket in eu-west-1."*

**Expected behavior:** Agent runs `aws s3 mb s3://copilot-demo-test-bucket --region eu-west-1` → gets `An error occurred (AccessDenied) when calling the CreateBucket operation`. Agent explains it only has read-only access.

**Why this matters:** Even though the agent is running in an isolated sandbox and *could* execute arbitrary commands, the IAM role prevents any mutation. Two independent safety layers.

### Demo 4 — Credentials expire (explicit path only)

**Setup:** Launch the sandbox using the explicit path: `./scripts/run-sandbox.sh --explicit --duration 900`

**Prompt:** (Wait 15 minutes, then ask) *"List S3 buckets again."*

**Expected behavior:** Agent runs `aws s3api list-buckets` → gets `ExpiredToken: The security token included in the request is expired`. Agent recognizes the issue and suggests re-running the token vending script.

**Why this matters:** Even if credentials are somehow exfiltrated from the sandbox, they're useless within minutes. This demo only works with the explicit path — the profile-based approach auto-refreshes, which is the point of recommending it for daily use.

**Teaching moment:** "This is why we recommend the profile approach for real work — it handles refresh for you. But if you're in a zero-trust environment where you can't mount `~/.aws`, the explicit path with short TTLs is your safety net."

---

## 7. README structure

The README is the showpiece — it needs to tell a story, not just list files.

1. **Hook** — "AI agents need cloud access. Giving them your admin credentials is a terrible idea. Here's the right way."
2. **Architecture diagram** — The three-layer visual from section 3
3. **Quick Start: Local path (profile)** — 5 commands from clone to running agent
   - `git clone` → `cd terraform && terraform apply` → `./scripts/setup-profile.sh` → `./scripts/run-sandbox.sh`
4. **Quick Start: Local path (explicit)** — For understanding the mechanics
   - `eval $(./scripts/vend-token.sh)` → `./scripts/run-sandbox.sh --explicit`
5. **Quick Start: GitHub-hosted path** — Fork, set variables, assign an issue to Copilot
6. **How It Works** — Brief explanation of each layer
7. **Credential Strategies** — When to use profile vs. explicit vs. OIDC, with a decision table
8. **Demo Walkthroughs** — Linked to `examples/*.md`
9. **Customization** — Change session duration, scope down permissions, add Azure
10. **Threat Model** — What this protects against (agent running arbitrary cloud commands, credential leakage, lateral movement) and what it doesn't (supply chain attacks in the sandbox image, social engineering of the developer)
11. **Prerequisites** — Docker Desktop 4.50+, Copilot license, AWS account, Terraform

---

## 8. What's explicitly NOT in scope (but documented as extension points)

| Extension | Where to document | Notes |
|-----------|-------------------|-------|
| Azure path (Managed Identity + az login) | `docs/extending.md` | Mirror the same pattern with `az login --identity` |
| Write-capable roles (for trusted workflows) | `docs/extending.md` | Show how to add a second role with scoped write access |
| Custom IAM policy (instead of ReadOnlyAccess) | `docs/extending.md` | Tighter scoping for production use |
| `credential_process` for custom identity brokers | `docs/extending.md` | For teams using Granted, aws-vault, or custom SSO — one-liner example |
| MCP server for AWS (remote) | `docs/extending.md` | When/if the Azure MCP server pattern gets an AWS equivalent |
| Multi-account setup | `docs/extending.md` | Cross-account AssumeRole chain |
| Audit trail / CloudTrail integration | `docs/extending.md` | Session tags → CloudTrail filter |

---

## 9. Open questions for your review

1. **Repo name** — `sandboxed-copilot-cloud-guardrails` is descriptive but long. Alternatives: `copilot-sandbox-aws-guardrails`, `agent-cloud-sandbox`, `docker-copilot-aws-demo`. Preference?

2. **Custom Docker template vs. default** — The `sandbox/Dockerfile` adds AWS CLI v2 to the Copilot base. We could skip this and have the agent install it at runtime (simpler repo, slower first run). Worth including the Dockerfile?

3. **GitHub OIDC provider creation** — The `iam-oidc-github.tf` creates the OIDC provider. If the user's account already has one (common if they use GitHub Actions + AWS), Terraform will fail. Should we add a `data` source + conditional, or document "skip this if you already have it" and keep the Terraform simple?

4. **Session duration** — With the profile-based approach, auto-refresh makes this less critical. I've defaulted to `3600s` (1 hour) in the profile config and the Terraform `max_session_duration`. The `vend-token.sh` script defaults to `900s` (15 min) since that's the explicit/teaching path where short TTL is the point. Does this split feel right?

5. **Scope of ReadOnlyAccess** — The AWS-managed `ReadOnlyAccess` policy is very broad (covers all services). For the demo this is fine and simple. But some folks might want to see a custom policy. Include as a commented-out alternative in `iam-role.tf`?

---

## 10. Suggested build order

If you greenlight this plan, here's how I'd sequence the build:

| Step | Files | Why this order |
|------|-------|----------------|
| 1 | `terraform/*` | Foundation — everything else depends on the role ARN |
| 2 | `scripts/setup-profile.sh` | Primary credential strategy — one-time setup |
| 3 | `scripts/vend-token.sh` | Explicit/teaching credential strategy |
| 4 | `scripts/run-sandbox.sh` | Ties credential strategies to sandbox launch |
| 5 | `sandbox/Dockerfile` + `copilot-config.json` | Custom template for AWS CLI |
| 6 | `.github/workflows/copilot-setup-steps.yml` | GitHub-hosted path |
| 7 | `.github/copilot/agents/cloud-reader.md` | Agent persona |
| 8 | `examples/*.md` | Demo scripts |
| 9 | `docs/*.md` | Architecture, threat model, extension guide |
| 10 | `README.md` | Written last — references everything above |
| 11 | `.github/workflows/validate-terraform.yml` | CI polish |
