# Demo 1: Read succeeds with S3

## Prompt

> List all S3 buckets in this account. For each bucket, check if versioning is enabled and report the results in a markdown table.

## Expected agent behavior

1. Run `aws s3api list-buckets`.
2. For each bucket, run `aws s3api get-bucket-versioning --bucket <name>`.
3. Summarize the results in a markdown table.

## Why it matters

This shows the happy path: the agent can inspect cloud resources, but only through read APIs.
