data "aws_iam_policy_document" "copilot_sandbox_assume_role" {
  statement {
    sid     = "AllowLocalSandboxPrincipal"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [var.trusted_principal_arn]
    }
  }

  statement {
    sid     = "AllowGitHubActionsOidc"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.github_oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_provider_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${local.github_oidc_provider_host}:sub"
      values   = ["repo:${var.github_org}/${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "copilot_sandbox_read_only" {
  name                 = var.role_name
  description          = "Read-only AWS role for sandboxed GitHub Copilot sessions."
  assume_role_policy   = data.aws_iam_policy_document.copilot_sandbox_assume_role.json
  max_session_duration = var.session_duration

  depends_on = [aws_iam_openid_connect_provider.github_actions]
}

resource "aws_iam_role_policy_attachment" "read_only_access" {
  role       = aws_iam_role.copilot_sandbox_read_only.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/ReadOnlyAccess"
}
