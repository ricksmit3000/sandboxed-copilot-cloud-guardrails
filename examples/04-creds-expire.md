# Demo 4: Explicit credentials expire

## Setup

Launch the sandbox with explicit credentials and a short session:

```bash
./scripts/run-sandbox.sh --explicit --duration 900
```

## Prompt after expiry

> List S3 buckets again.

## Expected agent behavior

1. Try `aws s3api list-buckets`.
2. Receive an `ExpiredToken` error after the 15-minute TTL elapses.
3. Recommend re-running `./scripts/run-sandbox.sh --explicit --duration 900` or `eval "$(./scripts/vend-token.sh --duration 900)"`.

## Why it matters

This demo illustrates the upside of short-lived credentials and why the profile-based path is better for day-to-day work.
