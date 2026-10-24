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

run "the_default_secret_rotates_thirty_days_before_it_expires" {
  command = apply

  assert {
    condition     = timeadd(time_rotating.secret.rfc3339, "${365 * 24}h") == azuread_service_principal_password.costfluent.end_date
    error_message = "The secret must stay valid for secret_expiry_days from the timer's base time."
  }

  assert {
    condition     = timeadd(time_rotating.secret.rotation_rfc3339, "${30 * 24}h") == azuread_service_principal_password.costfluent.end_date
    error_message = "An apply must rotate the secret 30 days before it stops working, not at that instant."
  }

  assert {
    condition     = output.secret_expires_at == azuread_service_principal_password.costfluent.end_date
    error_message = "secret_expires_at must stay the instant the secret stops working."
  }

  assert {
    condition     = output.secret_rotates_at == time_rotating.secret.rotation_rfc3339
    error_message = "secret_rotates_at must be the instant from which an apply replaces the secret."
  }
}

run "a_short_lifetime_rotates_one_day_after_creation_at_the_longest_lead" {
  command = apply

  variables {
    secret_expiry_days                 = 2
    secret_rotation_days_before_expiry = 1
  }

  assert {
    condition     = timeadd(time_rotating.secret.rfc3339, "24h") == time_rotating.secret.rotation_rfc3339
    error_message = "The timer must rotate one day after creation."
  }

  assert {
    condition     = timeadd(time_rotating.secret.rfc3339, "48h") == azuread_service_principal_password.costfluent.end_date
    error_message = "The secret must stay valid for two days."
  }
}

run "a_lifetime_under_sixty_days_rotates_at_half_its_length_by_default" {
  command = apply

  variables {
    secret_expiry_days = 30
  }

  assert {
    condition     = timeadd(time_rotating.secret.rotation_rfc3339, "${15 * 24}h") == azuread_service_principal_password.costfluent.end_date
    error_message = "With no lead given, a 30-day secret must rotate 15 days before it expires."
  }
}

run "a_lead_as_long_as_the_lifetime_is_refused" {
  command = plan

  variables {
    secret_expiry_days                 = 30
    secret_rotation_days_before_expiry = 30
  }

  expect_failures = [var.secret_rotation_days_before_expiry]
}

run "a_lead_below_one_day_is_refused" {
  command = plan

  variables {
    secret_rotation_days_before_expiry = 0
  }

  expect_failures = [var.secret_rotation_days_before_expiry]
}
