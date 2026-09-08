# Grants Costfluent read-only access to one Azure subscription's cost data.
#
# Costfluent collects through the Cost Details API
# (POST {scope}/providers/Microsoft.CostManagement/generateCostDetailsReport), which Microsoft
# offers only to Enterprise Agreement and Microsoft Customer Agreement billing accounts. A
# subscription on the legacy pay-as-you-go program cannot be connected at all, and this module
# cannot detect that from Terraform — scripts/verify-access.sh proves it after apply.

data "azuread_client_config" "current" {}

data "azurerm_subscription" "target" {
  subscription_id = var.subscription_id
}

locals {
  # An ownerless app registration is nobody's to rotate or delete, so the caller owns it by default.
  owners = length(var.owners) > 0 ? var.owners : [data.azuread_client_config.current.object_id]

  purpose = "Read-only Azure Cost Management access for Costfluent, scoped to subscription ${var.subscription_id}."
}

# The application is registered in whichever tenant the azuread provider is pointed at, while the
# role is assigned in the subscription's own tenant. When those differ the apply still succeeds and
# collection then fails with an opaque "access denied" — Microsoft supports cross-tenant Cost
# Management only partially. Catching it at plan time is the difference between a clear message and
# a support conversation.
check "single_tenant" {
  assert {
    condition = lower(data.azurerm_subscription.target.tenant_id) == lower(data.azuread_client_config.current.tenant_id)
    error_message = join("", [
      "Subscription ${var.subscription_id} belongs to tenant ${data.azurerm_subscription.target.tenant_id}, ",
      "but the application would be registered in tenant ${data.azuread_client_config.current.tenant_id}. ",
      "Point the azuread provider at the subscription's tenant.",
    ])
  }
}

resource "azuread_application" "costfluent" {
  display_name = var.application_display_name
  description  = local.purpose
  notes        = "Managed by terraform-azure-cost-access. Do not edit by hand."
  owners       = local.owners
  tags         = var.tags

  # Single-tenant: the credential is only ever used against this directory.
  sign_in_audience = "AzureADMyOrg"

  # A second registration under the same name is how a half-finished manual setup and this module
  # end up fighting over one integration. Fail instead, and let the operator import or rename.
  prevent_duplicate_names = true
}

resource "azuread_service_principal" "costfluent" {
  client_id   = azuread_application.costfluent.client_id
  description = local.purpose
  notes       = "Managed by terraform-azure-cost-access. Do not edit by hand."
  owners      = local.owners
  tags        = var.tags
}

# Drives the secret's lifetime from state rather than from wall-clock time at plan. Using
# timeadd(timestamp(), ...) here would re-plan the credential on every single run.
resource "time_rotating" "secret" {
  rotation_days = var.secret_expiry_days
}

resource "azuread_service_principal_password" "costfluent" {
  service_principal_id = azuread_service_principal.costfluent.id
  display_name         = "costfluent-terraform"
  end_date             = time_rotating.secret.rotation_rfc3339

  rotate_when_changed = {
    rotation = time_rotating.secret.id
  }
}

resource "azurerm_role_assignment" "costfluent" {
  for_each = toset(var.role_definition_names)

  scope                = data.azurerm_subscription.target.id
  role_definition_name = each.value
  principal_id         = azuread_service_principal.costfluent.object_id
  principal_type       = "ServicePrincipal"
  description          = local.purpose

  # A freshly created service principal has not replicated across Entra yet, so the ARM-side
  # existence check fails intermittently on a first apply. The principal is created above in the
  # same graph, so the check adds nothing but flakiness.
  skip_service_principal_aad_check = true
}
