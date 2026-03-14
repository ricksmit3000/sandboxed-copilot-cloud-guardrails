# ── Certificate generation ─────────────────────────────────────────────
resource "tls_private_key" "agent" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "agent" {
  private_key_pem = tls_private_key.agent.private_key_pem

  subject {
    common_name = var.app_name
  }

  validity_period_hours = var.cert_validity_days * 24

  allowed_uses = [
    "client_auth",
    "digital_signature",
  ]
}

# ── Entra app registration ─────────────────────────────────────────────
resource "azuread_application" "agent" {
  display_name = var.app_name
}

resource "azuread_service_principal" "agent" {
  client_id = azuread_application.agent.client_id
}

# Upload the public certificate to the app registration.
# The private key never leaves Terraform state + the local PEM file.
resource "azuread_application_certificate" "agent" {
  application_id = azuread_application.agent.id
  type           = "AsymmetricX509Cert"
  value          = tls_self_signed_cert.agent.cert_pem
  end_date       = tls_self_signed_cert.agent.validity_end_time
}
