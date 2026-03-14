output "tenant_id" {
  description = "Azure tenant ID (AZURE_TENANT_ID)"
  value       = data.azurerm_subscription.current.tenant_id
}

output "client_id" {
  description = "Service principal client ID (AZURE_CLIENT_ID)"
  value       = azuread_application.agent.client_id
}

output "certificate_path" {
  description = "Local path to the combined cert+key PEM file (AZURE_CLIENT_CERTIFICATE_PATH)"
  value       = local_sensitive_file.agent_cert_pem.filename
}

output "certificate_expiry" {
  description = "Certificate expiry (RFC3339)"
  value       = tls_self_signed_cert.agent.validity_end_time
}

output "env_file_path" {
  description = "Path to the generated .env.copilot-agent file"
  value       = local_sensitive_file.env_file.filename
}
