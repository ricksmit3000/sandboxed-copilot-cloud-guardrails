output "role_arn" {
  description = "IAM role ARN used by local scripts and the GitHub-hosted coding agent workflow."
  value       = aws_iam_role.copilot_sandbox_read_only.arn
}

output "assume_role_command" {
  description = "Copy-paste AWS CLI command showing how to assume the sandbox role manually."
  value       = "aws sts assume-role --role-arn ${aws_iam_role.copilot_sandbox_read_only.arn} --role-session-name ${local.assume_role_example_name} --duration-seconds ${local.assume_role_example_ttl}"
}

output "oidc_provider_arn" {
  description = "GitHub Actions OIDC provider ARN used in the trust policy."
  value       = aws_iam_openid_connect_provider.github_actions.arn
}
