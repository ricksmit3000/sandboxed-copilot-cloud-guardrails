# Threat model

This setup is designed to reduce the blast radius when an AI coding agent needs Azure visibility.

## What it protects against

### Accidental writes from the agent
The service principal has only the `Reader` role. Any mutation attempt — creating resources, modifying configurations, deleting anything — returns `AuthorizationFailed` from Azure RBAC. This is enforced server-side by Azure, not by the agent's prompt instructions.

### Sensitive file access on the workstation
Agent Safehouse's deny-first sandbox blocks access to `~/.azure/`, `~/.ssh/`, `~/.aws/`, and `~/.gnupg/` at the macOS kernel level. Even if the agent attempts to read SSH keys, Azure CLI tokens, or AWS credentials, the OS returns "Operation not permitted" before any file access occurs.

### Credential fallback to the developer's identity
Setting `AZURE_TOKEN_CREDENTIALS=EnvironmentCredential` restricts the Azure Identity SDK to only use the service principal credentials from environment variables. Without this, DefaultAzureCredential would fall through to `az login`, VS Code credentials, or interactive browser login — all of which use the developer's full permissions.

### Unbounded workstation access
The deny-first sandbox limits the agent's filesystem to the project directory (R/W), Copilot CLI state (R/W), the agent certificate (R/O), and system toolchains (R/O). Everything else is denied by default.

## What it does not protect against

- **Terraform state contains the private key**: the `tls_private_key` resource stores the private key in Terraform state in plaintext. Local state (the default) is a file on disk at `terraform/terraform.tfstate`. Treat this file like the PEM itself: do not commit it (already gitignored), and consider using encrypted remote state (e.g. Azure Blob Storage with a customer-managed key) in shared or team environments.
- **Certificate key compromise**: if the PEM file at `~/.config/copilot-agent/agent-cert.pem` is copied off the machine, an attacker can authenticate as the service principal until the certificate expires or is rotated.
- **Supply-chain attacks**: the `@azure/mcp` npm package is fetched via `npx` at runtime. A compromised package could exfiltrate data through allowed network connections.
- **sandbox-exec deprecation**: Apple has deprecated `sandbox-exec` but it still functions on current macOS versions. A future macOS release could remove it.
- **Network-level data exfiltration**: macOS `sandbox-exec` cannot filter network traffic by hostname. The sandbox allows all outbound TCP.
- **Broad Reader visibility**: the `Reader` role at subscription scope sees all resources across all resource groups.
- **Prompt injection widening permissions**: the agent could recommend that a human grant broader access, though the Reader role prevents the agent from executing permission changes itself.

## Residual risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Terraform state contains private key | High | Gitignored by default; use encrypted remote state in shared environments |
| Certificate expiry unnoticed | Medium | `validate.sh` checks expiry; warns at 30 days |
| Reader sees all subscription resources | Low | Scope to resource group (see `extending.md`) |
| `@azure/mcp@latest` is mutable | Medium | Pin version in production |
| sandbox-exec removed in future macOS | Low | Track Agent Safehouse releases |
| Network exfil via allowed TCP | Low | Add firewall rules or proxy |
