resource "azurerm_role_assignment" "agent_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azuread_service_principal.agent.object_id
}
