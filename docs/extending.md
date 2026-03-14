# Extending this setup

This repo provides a minimal, secure baseline. Here are documented extension points.

## Scope Reader to a resource group

The default assigns Reader at subscription scope. To restrict visibility:

```bash
az role assignment create \
  --assignee "$APP_ID" \
  --role "Reader" \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG_NAME"
```

## Add data-plane reader roles

The `Reader` role covers the ARM control plane. For data-plane access:

| Service | Data-plane role |
| --- | --- |
| Storage (blobs) | `Storage Blob Data Reader` |
| Cosmos DB | `Cosmos DB Built-in Data Reader` |
| Key Vault (secrets) | `Key Vault Secrets User` |

## Pin the Azure MCP Server version

Replace `@azure/mcp@latest` in `.copilot/mcp.json` with a pinned version:

```json
"args": ["-y", "@azure/mcp@0.5.2", "server", "start"]
```

## Reuse in an existing company-managed setup

If your company already provisions the Entra app, service principal, certificate credential, and read-only RBAC assignment, you can reuse only the local integration pieces from this repo.

Use the helper script to copy `safehouse/`, `.copilot/mcp.json`, and generate `.env.copilot-agent` in another project:

```bash
./scripts/adopt-company-managed-identity.sh /path/to/your/project <tenant-id> <client-id>
```

If the certificate PEM is not at the default path, pass it explicitly:

```bash
./scripts/adopt-company-managed-identity.sh /path/to/your/project <tenant-id> <client-id> /path/to/agent-cert.pem
```

This does not provision any Azure resources. It assumes the service principal and RBAC already exist.

## GitHub-hosted path (federated identity)

Add federated identity credentials to the Entra app registration:

```bash
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "github-copilot",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:environment:copilot",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

Then create a `copilot-setup-steps.yml` workflow using `azure/login@v2`.

## Write-capable role for trusted workflows

Create a separate service principal with a scoped custom role:

```bash
az role definition create --role-definition '{
  "Name": "CopilotLimitedWriter",
  "Actions": [
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/read"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/<sub-id>/resourceGroups/<rg-name>"]
}'
```

Never reuse the Reader service principal for write access.

## Network proxy for hostname filtering

macOS `sandbox-exec` cannot filter network by hostname. For hostname-level control:

1. Set `HTTPS_PROXY` in the shell wrapper
2. Allow only: `login.microsoftonline.com`, `management.azure.com`, `graph.microsoft.com`, `registry.npmjs.org`, `github.com`
3. Block all other outbound HTTPS

## Linux alternatives

Agent Safehouse is macOS-only. For Linux:

- **Firejail**: `firejail --noprofile --whitelist=. --read-only=$HOME/.config/copilot-agent copilot`
- **bubblewrap**: Fine-grained namespace isolation
- **Docker**: The approach used in the previous AWS version of this repo

## Audit trail

Enable Azure Activity Log monitoring:

1. Create a diagnostic setting to send Activity Logs to a Log Analytics workspace
2. Filter by the service principal's client ID
3. Alert on `AuthorizationFailed` patterns

## Multiple subscriptions

Assign Reader at the management group level:

```bash
az role assignment create \
  --assignee "$APP_ID" \
  --role "Reader" \
  --scope "/providers/Microsoft.Management/managementGroups/$MG_ID"
```

## Certificate rotation

To rotate the certificate:

1. Delete the old PEM: `rm ~/.config/copilot-agent/agent-cert.pem`
2. Force Terraform to regenerate the key and cert: `terraform -chdir=terraform apply -replace=tls_private_key.agent`
3. Clean up old credentials on the Entra side: `az ad app credential list --id $APP_ID`, then `az ad app credential delete --id $APP_ID --key-id <old-key-id>`
