# Demo 2: Read VMs and networking (cross-resource read)

## Prompt

> Show me all virtual machines in this subscription. Include the VM size, OS type, location, and the network security group associated with each.

## Expected behavior

1. The agent queries VMs via the Azure MCP Server.
2. It cross-references with network security groups or network interfaces.
3. Results are presented in a structured summary.

## What to look for

- The agent queries across multiple resource types (VMs, NICs, NSGs).
- The Reader role grants visibility into compute, networking, and related metadata.
- The MCP Server handles multiple tool calls in sequence.

## Why it matters

This proves the Reader role provides useful visibility across Azure resource types. The agent can correlate data from different services to answer infrastructure questions — exactly what a cloud reader should do.
