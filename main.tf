# Grants Costfluent read-only access to the cost data of one Azure subscription, of any more
# subscriptions and management groups you list, and, when commitment_roles is set, to the tenant's
# reservations and savings plans.
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

data "azurerm_subscription" "additional" {
  for_each = var.additional_subscription_ids

  subscription_id = each.key
}

data "azurerm_management_group" "scope" {
  for_each = var.management_group_ids

  name = each.key
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

  assert {
    condition = length(local.subscriptions_in_another_tenant) == 0
    error_message = join("", [
      "Subscriptions ${join(", ", local.subscriptions_in_another_tenant)} belong to another tenant than ",
      "${data.azuread_client_config.current.tenant_id}, where the application would be registered. ",
      "Connect each tenant with its own module call.",
    ])
  }

  assert {
    condition = length(local.management_groups_in_another_tenant) == 0
    error_message = join("", [
      "Management groups ${join(", ", local.management_groups_in_another_tenant)} are read through the azurerm provider's tenant, ",
      "not ${data.azuread_client_config.current.tenant_id}, where the application would be registered. ",
      "Point both providers at one tenant.",
    ])
  }
}

locals {
  application_tenant = lower(data.azuread_client_config.current.tenant_id)

  subscriptions_in_another_tenant = sort([
    for id, subscription in data.azurerm_subscription.additional : id
    if lower(subscription.tenant_id) != local.application_tenant
  ])

  # The data source has no tenant_id; its tenant_scoped_id reads
  # /tenants/<tenant>/providers/Microsoft.Management/managementGroups/<name>, built from the azurerm
  # provider's tenant. A value of another shape yields "" and fails the check rather than erroring.
  management_groups_in_another_tenant = sort([
    for id, group in data.azurerm_management_group.scope : id
    if lower(try(regex("^/tenants/([^/]+)/providers/Microsoft.Management/managementGroups/", group.tenant_scoped_id)[0], "")) != local.application_tenant
  ])
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

# The same roles on each further subscription, keyed <subscription>/<role>. Keys come from the
# inputs, never from data-source attributes, so they are known at plan; and subscription_id keeps
# its own resource above, whose role-name keys an upgrade must not change.
resource "azurerm_role_assignment" "additional_subscriptions" {
  for_each = { for pair in setproduct(var.additional_subscription_ids, toset(var.role_definition_names)) : "${pair[0]}/${pair[1]}" => { scope = pair[0], role = pair[1] } }

  scope                = data.azurerm_subscription.additional[each.value.scope].id
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.costfluent.object_id
  principal_type       = "ServicePrincipal"
  description          = "Read-only Azure Cost Management access for Costfluent, scoped to subscription ${each.value.scope}."

  # As above: the principal is created in the same graph.
  skip_service_principal_aad_check = true
}

# The same roles on each management group, inherited by every subscription under it, keyed
# <group>/<role>.
resource "azurerm_role_assignment" "management_groups" {
  for_each = { for pair in setproduct(var.management_group_ids, toset(var.role_definition_names)) : "${pair[0]}/${pair[1]}" => { scope = pair[0], role = pair[1] } }

  scope                = data.azurerm_management_group.scope[each.value.scope].id
  role_definition_name = each.value.role
  principal_id         = azuread_service_principal.costfluent.object_id
  principal_type       = "ServicePrincipal"
  description          = "Read-only Azure Cost Management access for Costfluent, scoped to management group ${each.value.scope} and the subscriptions under it."

  # As above: the principal is created in the same graph.
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
