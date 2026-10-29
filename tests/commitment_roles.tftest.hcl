mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "00000000-0000-0000-0000-0000000000a1"
      tenant_id = "00000000-0000-0000-0000-0000000000t1"
    }
  }

  mock_resource "azuread_application" {
    defaults = {
      client_id = "00000000-0000-0000-0000-0000000000c1"
    }
  }

  mock_resource "azuread_service_principal" {
    defaults = {
      id        = "/servicePrincipals/00000000-0000-0000-0000-0000000000s1"
      object_id = "00000000-0000-0000-0000-0000000000s1"
    }
  }
}

mock_provider "azurerm" {
  mock_data "azurerm_subscription" {
    defaults = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000001"
      tenant_id = "00000000-0000-0000-0000-0000000000t1"
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000001"
}

run "the_commitment_roles_are_off_by_default" {
  command = apply

  assert {
    condition     = length(azurerm_role_assignment.commitments) == 0
    error_message = "Without commitment_roles the module must assign nothing beyond the subscription."
  }
}

run "commitment_roles_assigns_both_readers_at_their_provider_scopes" {
  command = apply

  variables {
    commitment_roles = true
  }

  assert {
    condition = (
      length(azurerm_role_assignment.commitments) == 2 &&
      azurerm_role_assignment.commitments["Reservations Reader"].scope == "/providers/Microsoft.Capacity" &&
      azurerm_role_assignment.commitments["Savings plan Reader"].scope == "/providers/Microsoft.BillingBenefits"
    )
    error_message = "commitment_roles must assign Reservations Reader at /providers/Microsoft.Capacity and Savings plan Reader at /providers/Microsoft.BillingBenefits, and nothing else."
  }

  assert {
    condition = alltrue([
      for assignment in azurerm_role_assignment.commitments :
      assignment.principal_id == "00000000-0000-0000-0000-0000000000s1" && assignment.principal_type == "ServicePrincipal"
    ])
    error_message = "The commitment roles must go to Costfluent's service principal alone."
  }

  assert {
    condition     = output.assigned_roles == tolist(["Carbon Optimization Reader", "Cost Management Reader"])
    error_message = "commitment_roles must not change the roles assigned at the subscription."
  }
}
