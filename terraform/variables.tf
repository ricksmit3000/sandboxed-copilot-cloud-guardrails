variable "aws_region" {
  description = "AWS region for provider operations and example commands."
  type        = string
  default     = "eu-west-1"
}

variable "trusted_principal_arn" {
  description = "IAM principal ARN allowed to assume the sandbox role from a local developer environment."
  type        = string

  validation {
    condition     = can(regex("^arn:", var.trusted_principal_arn))
    error_message = "trusted_principal_arn must be a valid ARN."
  }
}

variable "github_org" {
  description = "GitHub organization allowed to assume the role via GitHub Actions OIDC."
  type        = string

  validation {
    condition     = length(trim(var.github_org, " ")) > 0
    error_message = "github_org must not be empty."
  }
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the role via GitHub Actions OIDC."
  type        = string

  validation {
    condition     = length(trim(var.github_repo, " ")) > 0
    error_message = "github_repo must not be empty."
  }
}

variable "session_duration" {
  description = "Maximum session duration, in seconds, for assumed role credentials."
  type        = number
  default     = 3600

  validation {
    condition     = var.session_duration >= 900 && var.session_duration <= 43200
    error_message = "session_duration must be between 900 and 43200 seconds."
  }
}

variable "role_name" {
  description = "Name of the IAM role used by local sandboxes and GitHub-hosted agents."
  type        = string
  default     = "CopilotSandboxReadOnly"

  validation {
    condition     = length(trim(var.role_name, " ")) > 0
    error_message = "role_name must not be empty."
  }
}
