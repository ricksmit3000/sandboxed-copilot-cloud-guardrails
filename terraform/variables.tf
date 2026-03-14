variable "subscription_id" {
  description = "Azure subscription ID for the Reader role assignment"
  type        = string
}

variable "app_name" {
  description = "Display name for the Entra app registration and service principal"
  type        = string
  default     = "copilot-sandbox-reader"
}

variable "cert_validity_days" {
  description = "Certificate validity in days"
  type        = number
  default     = 365
}
