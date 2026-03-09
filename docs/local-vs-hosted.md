# Local vs hosted

Use the same IAM role in both paths, but choose the execution environment that matches the workflow.

| Option | Best for | Strengths | Trade-offs |
| --- | --- | --- | --- |
| Local profile-based sandbox | Daily demos and iterative exploration | Auto-refreshing credentials, simple UX, reuses the AWS CLI credential chain | Requires mounting `~/.aws` into the sandbox |
| Local explicit token vending | Teaching the mechanics, locked-down environments | Makes STS visible, easy to reason about, short TTL by default | Requires re-vending credentials after expiry |
| GitHub-hosted coding agent | Assigned issues and hosted automation | No workstation dependency, no stored AWS secrets, repo-scoped OIDC trust | Requires repo/environment configuration and GitHub Actions support |

## Choose local profile mode when

- You want the lowest-friction demo.
- You already have a trusted source profile configured locally.
- You want AWS CLI auto-refresh to hide token expiry from the walkthrough.

## Choose explicit local mode when

- You need to show exactly how `sts:AssumeRole` works.
- You cannot mount `~/.aws` into the sandbox.
- You want expiring credentials to be part of the teaching moment.

## Choose the hosted path when

- You want Copilot coding agent to work from GitHub issues.
- You prefer repo-scoped OIDC over workstation-scoped credentials.
- You want the same guardrails without depending on a local Docker Desktop setup.
