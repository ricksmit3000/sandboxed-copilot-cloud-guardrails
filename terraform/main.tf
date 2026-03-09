terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  github_oidc_provider_host = "token.actions.githubusercontent.com"
  github_oidc_provider_url  = "https://${local.github_oidc_provider_host}"
  github_oidc_provider_arn  = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${local.github_oidc_provider_host}"
  assume_role_example_name  = "copilot-sandbox-manual"
  assume_role_example_ttl   = min(var.session_duration, 900)
}
