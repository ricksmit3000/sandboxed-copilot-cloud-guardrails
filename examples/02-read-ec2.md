# Demo 2: Read succeeds across EC2 and security groups

## Prompt

> Show me all running EC2 instances in eu-west-1. Include instance type, launch time, and the security group names attached to each.

## Expected agent behavior

1. Run `aws ec2 describe-instances --filters Name=instance-state-name,Values=running`.
2. Extract security group IDs from the instance metadata.
3. Run `aws ec2 describe-security-groups` to resolve group names.
4. Present the results in a concise summary or table.

## Why it matters

The demo proves the role is useful enough for real investigation work while still remaining read-only.
