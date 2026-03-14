# Local vs. hosted: why this repo is local-only (for now)

## Current scope

This repo demonstrates a **local-only** path: Copilot CLI running inside Agent Safehouse on a macOS workstation, authenticated as an Entra service principal with Reader access via the Azure MCP Server.

| Aspect | Local path (this repo) |
|--------|----------------------|
| Agent runtime | Copilot CLI |
| Isolation | Agent Safehouse (macOS sandbox-exec) |
| Cloud auth | Certificate-based Entra service principal |
| Tool surface | Azure MCP Server (`@azure/mcp`) |
| Target audience | Developers on macOS |

## Why not GitHub-hosted (yet)?

The Azure equivalent of a GitHub-hosted path is achievable using **federated identity credentials** on the Entra app registration, which allows GitHub Actions to exchange an OIDC token for an Azure access token without storing any secrets.

This is out of scope for v1 because:

1. **Agent Safehouse is macOS-only** — the GitHub-hosted runner is Linux, so a different sandboxing approach would be needed.
2. **The demo focus is workstation guardrails** — showing developers how to safely give a local AI agent cloud access.
3. **Federated credentials add complexity** — the Entra app registration, trust policy, and GitHub environment configuration are a separate tutorial.

## Adding the GitHub-hosted path

See `docs/extending.md` for step-by-step instructions on adding federated identity credentials for GitHub Actions OIDC.

## Platform limitations

| Platform | Safehouse support | Alternative |
|----------|------------------|------------|
| macOS | Native (sandbox-exec) | — |
| Linux | Not supported | Firejail, bubblewrap, Docker |
| Windows | Not supported | Windows Sandbox, WSL + Firejail |

For cross-platform teams, Docker-based isolation remains a viable alternative.
