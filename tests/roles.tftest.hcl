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

run "the_default_roles_read_cost_and_carbon_at_the_subscription" {
  command = apply

  assert {
    condition     = output.assigned_roles == tolist(["Carbon Optimization Reader", "Cost Management Reader"])
    error_message = "The default must assign exactly Cost Management Reader and Carbon Optimization Reader."
  }

  assert {
    condition = alltrue([
      for assignment in azurerm_role_assignment.costfluent :
      assignment.scope == "/subscriptions/00000000-0000-0000-0000-000000000001"
    ])
    error_message = "Every role must be assigned at the subscription, not wider."
  }
}
