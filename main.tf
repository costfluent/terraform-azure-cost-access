# Grants Costfluent read-only access to one Azure subscription's cost data and, when
# commitment_roles is set, to the tenant's reservations and savings plans.
#
# Costfluent collects through the Cost Details API
# (POST {scope}/providers/Microsoft.CostManagement/generateCostDetailsReport), which Microsoft
# offers only to Enterprise Agreement and Microsoft Customer Agreement billing accounts. A
# subscription on the legacy pay-as-you-go program cannot be connected at all, and Terraform cannot
# detect that: Costfluent's own connection test is what proves it, by making the call.

data "azuread_client_config" "current" {}

data "azurerm_subscription" "target" {
  subscription_id = var.subscription_id
}

locals {
  # An ownerless app registration is nobody's to rotate or delete, so the caller owns it by default.
  owners = length(var.owners) > 0 ? var.owners : [data.azuread_client_config.current.object_id]

  secret_rotation_days_before_expiry = coalesce(
    var.secret_rotation_days_before_expiry,
    min(30, floor(var.secret_expiry_days / 2)),
  )

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
# timeadd(timestamp(), ...) here would re-plan the credential on every single run. The timer comes
# due before the secret expires, so an apply inside that window replaces the secret while the old
# one still works; a timer due at the expiry instant itself would always leave a gap.
resource "time_rotating" "secret" {
  rotation_days = var.secret_expiry_days - local.secret_rotation_days_before_expiry
}

resource "azuread_service_principal_password" "costfluent" {
  service_principal_id = azuread_service_principal.costfluent.id
  display_name         = "costfluent-terraform"
  end_date             = timeadd(time_rotating.secret.rfc3339, "${var.secret_expiry_days * 24}h")

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

locals {
  # Microsoft grants these readers only at their resource provider's tenant-level scope, never on a
  # subscription, and only a User Access Administrator at the tenant root can assign them there.
  commitment_roles = {
    "Reservations Reader" = "/providers/Microsoft.Capacity"
    "Savings plan Reader" = "/providers/Microsoft.BillingBenefits"
  }
}

# Read-only, but for the whole tenant: every reservation and savings plan in it, which Costfluent
# lists under Commitments. Opt-in, because applying it needs elevated access most callers lack.
resource "azurerm_role_assignment" "commitments" {
  for_each = var.commitment_roles ? local.commitment_roles : {}

  scope                = each.value
  role_definition_name = each.key
  principal_id         = azuread_service_principal.costfluent.object_id
  principal_type       = "ServicePrincipal"
  description          = "Read-only access for Costfluent to this tenant's reservations and savings plans, for the connection of subscription ${var.subscription_id}."

  # As above: the principal is created in the same graph.
  skip_service_principal_aad_check = true
}
