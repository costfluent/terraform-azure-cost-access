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

run "a_secret_lifetime_of_730_days_is_accepted" {
  command = plan

  variables {
    secret_expiry_days = 730
  }

  assert {
    condition     = time_rotating.secret.rotation_days == 700
    error_message = "A 730-day secret is within Entra's two-year cap and must be accepted, rotating 30 days before it expires."
  }
}

run "a_secret_lifetime_of_one_day_is_accepted" {
  command = plan

  variables {
    secret_expiry_days = 1
  }

  assert {
    condition     = time_rotating.secret.rotation_days == 1
    error_message = "A one-day secret is the shortest lifetime the module allows and must be accepted."
  }
}

run "a_hex_subscription_id_a_single_role_and_a_display_name_are_accepted" {
  command = plan

  variables {
    subscription_id          = "0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d"
    application_display_name = "Acme Costfluent"
    role_definition_names    = ["Cost Management Reader"]
  }

  assert {
    condition = alltrue([
      azuread_application.costfluent.display_name == "Acme Costfluent",
      azuread_application.costfluent.description == "Read-only Azure Cost Management access for Costfluent, scoped to subscription 0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d.",
      output.subscription_id == "0a1b2c3d-4e5f-6a7b-8c9d-0e1f2a3b4c5d",
      length(azurerm_role_assignment.costfluent) == 1,
    ])
    error_message = "A lower-case GUID with hex letters, one role and a non-blank display name must be accepted as given."
  }
}

run "an_upper_case_subscription_id_is_refused" {
  command = plan

  variables {
    subscription_id = "0000000A-0000-0000-0000-000000000001"
  }

  expect_failures = [var.subscription_id]
}

run "a_braced_subscription_id_is_refused" {
  command = plan

  variables {
    subscription_id = "{00000000-0000-0000-0000-000000000001}"
  }

  expect_failures = [var.subscription_id]
}

run "a_blank_display_name_is_refused" {
  command = plan

  variables {
    application_display_name = "   "
  }

  expect_failures = [var.application_display_name]
}

run "an_empty_role_list_is_refused" {
  command = plan

  variables {
    role_definition_names = []
  }

  expect_failures = [var.role_definition_names]
}

run "a_secret_lifetime_over_730_days_is_refused" {
  command = plan

  variables {
    secret_expiry_days = 731
  }

  expect_failures = [var.secret_expiry_days]
}

run "a_secret_lifetime_of_zero_days_is_refused" {
  command = plan

  variables {
    secret_expiry_days = 0
  }

  expect_failures = [var.secret_expiry_days]
}
