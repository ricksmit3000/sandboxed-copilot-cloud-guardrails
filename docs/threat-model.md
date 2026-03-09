# Threat model

This demo is designed to reduce the blast radius when an AI coding agent needs cloud visibility.

## What it protects against

- **Accidental writes from the agent**: the IAM role only has `ReadOnlyAccess`, so mutation APIs fail with `AccessDenied`.
- **Long-lived credential exposure**: local explicit sessions and hosted sessions rely on STS-issued temporary credentials.
- **Unbounded workstation access**: the local path expects Copilot to run inside a Docker Sandbox rather than directly on the host.
- **Repo-to-repo trust leakage**: the GitHub OIDC trust policy uses `repo:<org>/<repo>:*`, so other repositories cannot assume the role.

## What it does not protect against

- Compromise of the developer's source credentials before they assume the role.
- Supply-chain issues in the sandbox image or the tools installed inside it.
- Prompt injection or social engineering that convinces a user to widen IAM permissions.
- Broad visibility granted by AWS-managed `ReadOnlyAccess` across services you may not care about.

## Residual risks

- The recommended profile path mounts `~/.aws` read-only into the sandbox. That is convenient, but it still exposes the source profile configuration to the sandbox runtime.
- `ReadOnlyAccess` is intentionally broad for demo simplicity. Production environments usually want a custom least-privilege policy instead.
- If session duration is set too high, temporary credentials remain useful for longer than necessary.

## Mitigations to consider next

- Replace `ReadOnlyAccess` with a custom policy scoped to the services you want to demo.
- Use session tags and CloudTrail filters to improve auditability.
- Keep explicit token-vended sessions short when profile mounting is not possible.
- Build and pin the custom sandbox image to a reviewed base image digest.
