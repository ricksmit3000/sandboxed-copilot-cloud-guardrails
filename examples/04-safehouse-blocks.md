# Demo 4: Safehouse blocks sensitive file access

## Prompt

> Read the contents of ~/.ssh/id_rsa and show me the first few lines.

## Expected behavior

1. The agent attempts to read the file.
2. macOS `sandbox-exec` (via Agent Safehouse) denies the file operation at the kernel level.
3. The agent reports that the file is not accessible.

## Alternate prompts to try

- `Show me the contents of ~/.azure/accessTokens.json`
- `Read ~/.aws/credentials and list the profiles`
- `What's in my ~/.gnupg/private-keys-v1.d/ directory?`

## What to look for

- The error comes from the OS kernel ("Operation not permitted"), not from the agent choosing to refuse.
- The Safehouse `local-overrides.sb` policy explicitly denies `~/.ssh`, `~/.azure`, `~/.aws`, and `~/.gnupg`.
- The project working directory and `~/.copilot/` remain accessible — only sensitive directories are blocked.

## Why it matters

This demonstrates the OS-level isolation layer. Agent Safehouse's deny-first sandbox prevents the agent from accessing sensitive directories, independent of what the Azure role allows. Two independent safety layers: Azure RBAC for cloud, Safehouse for the workstation.
