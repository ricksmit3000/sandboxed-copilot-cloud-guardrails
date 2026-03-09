# Extending the demo

The repository intentionally starts with a simple, read-only AWS pattern. Here are the most common extension points.

## Swap `ReadOnlyAccess` for a custom policy

Replace the managed policy attachment in `terraform/iam-role.tf` with an inline or customer-managed policy when you want tighter service coverage.

## Add a write-capable role for trusted workflows

Keep the read-only role for general agent access, and provision a second role with narrowly scoped write permissions for approved automation paths.

## Support multiple AWS accounts

Use a hub-and-spoke pattern where the local or hosted identity assumes an entry role, then chains into environment-specific roles.

## Use an external identity broker

If your team uses `aws-vault`, Granted, or another SSO wrapper, adapt `setup-profile.sh` or `vend-token.sh` to rely on `credential_process` rather than a static `source_profile`.

## Add audit trail context

Use session tags on `AssumeRole` and build CloudTrail dashboards or Athena queries that identify agent-originated sessions.

## Extend to other clouds

The same structure works for Azure or GCP: isolate the runtime, vend short-lived cloud credentials, and make the default role read-only.
