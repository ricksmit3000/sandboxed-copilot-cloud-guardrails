# If your AWS account already has the GitHub OIDC provider configured, import it
# into this resource instead of creating a duplicate:
# terraform import aws_iam_openid_connect_provider.github_actions arn:aws:iam::<account-id>:oidc-provider/token.actions.githubusercontent.com
resource "aws_iam_openid_connect_provider" "github_actions" {
  url = local.github_oidc_provider_url

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = [
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
}
