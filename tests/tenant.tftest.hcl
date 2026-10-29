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

run "the_application_signs_in_only_its_own_tenant" {
  command = apply

  assert {
    condition     = azuread_application.costfluent.sign_in_audience == "AzureADMyOrg"
    error_message = "The application holds a live secret, so it must not be consentable into any other tenant."
  }

  assert {
    condition     = azuread_application.costfluent.prevent_duplicate_names == true
    error_message = "A second registration under the same name must fail the apply, not sit beside the first."
  }
}

run "the_caller_owns_the_application_by_default" {
  command = apply

  variables {
    owners = []
  }

  assert {
    condition     = azuread_application.costfluent.owners == toset(["00000000-0000-0000-0000-0000000000a1"])
    error_message = "With no owners given, the principal running Terraform must own the application."
  }

  assert {
    condition     = azuread_service_principal.costfluent.owners == toset(["00000000-0000-0000-0000-0000000000a1"])
    error_message = "With no owners given, the principal running Terraform must own the service principal."
  }
}

run "the_given_owners_replace_the_caller" {
  command = apply

  variables {
    owners = ["00000000-0000-0000-0000-0000000000b1", "00000000-0000-0000-0000-0000000000b2"]
  }

  assert {
    condition     = azuread_application.costfluent.owners == toset(["00000000-0000-0000-0000-0000000000b1", "00000000-0000-0000-0000-0000000000b2"])
    error_message = "The application must be owned by exactly the owners given."
  }

  assert {
    condition     = azuread_service_principal.costfluent.owners == toset(["00000000-0000-0000-0000-0000000000b1", "00000000-0000-0000-0000-0000000000b2"])
    error_message = "The service principal must be owned by exactly the owners given."
  }
}

run "a_subscription_in_another_tenant_fails_the_check" {
  command = plan

  override_data {
    target = data.azurerm_subscription.target
    values = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000001"
      tenant_id = "00000000-0000-0000-0000-0000000000t2"
    }
  }

  expect_failures = [check.single_tenant]
}

run "the_tenant_check_ignores_the_case_of_the_subscription_tenant" {
  command = plan

  override_data {
    target = data.azurerm_subscription.target
    values = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000001"
      tenant_id = "00000000-0000-0000-0000-0000000000T1"
    }
  }
}

run "the_tenant_check_ignores_the_case_of_the_provider_tenant" {
  command = plan

  override_data {
    target = data.azuread_client_config.current
    values = {
      object_id = "00000000-0000-0000-0000-0000000000a1"
      tenant_id = "00000000-0000-0000-0000-0000000000T1"
    }
  }
}
