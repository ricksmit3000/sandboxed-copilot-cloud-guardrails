# Demo 1: List resource groups (read succeeds)

## Prompt

> List all resource groups in this subscription. For each, show the location and any tags.

## Expected behavior

1. The agent uses the Azure MCP Server's resource group listing tool.
2. The Reader role allows full visibility into resource group metadata.
3. Results are presented in a structured markdown table.

## What to look for

- The agent authenticates as the service principal (not your user identity).
- The response includes resource group names, locations, and tags.
- No errors — this is the happy-path read operation.

## Why it matters

This demonstrates that the sandboxed Copilot CLI can query Azure resources through the MCP Server, authenticated via a certificate-based service principal with Reader access. The agent never touches your personal Azure credentials.
