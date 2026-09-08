# The credential field names are the contract Costfluent validates against
# (ProviderDefinitions.Azure.RequiredCredentialFields in the Costfluent backend). Renaming one here
# breaks every connection made with this module; scripts/check-integration-contract.py asserts it.
locals {
  credentials = {
    tenant         = data.azuread_client_config.current.tenant_id
    appId          = azuread_application.costfluent.client_id
    password       = azuread_service_principal_password.costfluent.value
    subscriptionId = var.subscription_id
  }
}

output "credentials" {
  description = "Credential fields for the Costfluent Azure connection."
  sensitive   = true
  value       = local.credentials
}

output "credentials_json" {
  description = "The same credentials as a JSON object, ready to paste into Costfluent."
  sensitive   = true
  value       = jsonencode(local.credentials)
}

output "tenant_id" {
  description = "Microsoft Entra tenant the application was registered in."
  value       = data.azuread_client_config.current.tenant_id
}

output "client_id" {
  description = "Application (client) ID of the registration Costfluent authenticates as."
  value       = azuread_application.costfluent.client_id
}

output "service_principal_object_id" {
  description = "Object ID of the service principal holding the role assignments."
  value       = azuread_service_principal.costfluent.object_id
}

output "subscription_id" {
  description = "Subscription the role assignments were made on."
  value       = var.subscription_id
}

output "subscription_display_name" {
  description = "Display name of that subscription, to confirm the right one was targeted."
  value       = data.azurerm_subscription.target.display_name
}

output "assigned_roles" {
  description = "Roles assigned to the service principal at subscription scope."
  value       = sort(keys(azurerm_role_assignment.costfluent))
}

output "secret_expires_at" {
  description = "RFC3339 instant the client secret stops working. Re-apply before it to rotate."
  value       = azuread_service_principal_password.costfluent.end_date
}
