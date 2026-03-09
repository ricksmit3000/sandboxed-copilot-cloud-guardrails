# Demo 3: Write fails with AccessDenied

## Prompt

> Create a new S3 bucket called copilot-demo-test-bucket in eu-west-1.

## Expected agent behavior

1. Attempt `aws s3 mb s3://copilot-demo-test-bucket --region eu-west-1`.
2. Receive an `AccessDenied` error.
3. Explain that the sandbox role intentionally blocks write operations.

## Why it matters

This is the guardrail moment: even if the agent can execute commands, IAM still prevents mutation.
