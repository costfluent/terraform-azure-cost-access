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

  mock_data "azurerm_management_group" {
    defaults = {
      id               = "/providers/Microsoft.Management/managementGroups/mg-mock"
      tenant_scoped_id = "/tenants/00000000-0000-0000-0000-0000000000t1/providers/Microsoft.Management/managementGroups/mg-mock"
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000001"
}

run "none_set_assigns_on_the_subscription_alone" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.additional_subscriptions) == 0 && length(azurerm_role_assignment.management_groups) == 0
    error_message = "Without additional_subscription_ids or management_group_ids the module must assign nothing beyond subscription_id."
  }

  assert {
    condition     = sort(keys(azurerm_role_assignment.costfluent)) == tolist(["Carbon Optimization Reader", "Cost Management Reader"])
    error_message = "The subscription's assignments must keep their role-name keys, so an upgrade neither creates nor destroys them."
  }

  assert {
    condition     = output.assignment_scopes == tolist([data.azurerm_subscription.target.id])
    error_message = "assignment_scopes must name the subscription alone."
  }
}

run "each_additional_subscription_gets_every_role" {
  command = apply

  variables {
    additional_subscription_ids = ["00000000-0000-0000-0000-000000000002", "00000000-0000-0000-0000-000000000003"]
  }

  assert {
    condition = sort(keys(azurerm_role_assignment.additional_subscriptions)) == tolist([
      "00000000-0000-0000-0000-000000000002/Carbon Optimization Reader",
      "00000000-0000-0000-0000-000000000002/Cost Management Reader",
      "00000000-0000-0000-0000-000000000003/Carbon Optimization Reader",
      "00000000-0000-0000-0000-000000000003/Cost Management Reader",
    ])
    error_message = "Every additional subscription must get every role in role_definition_names, keyed <subscription>/<role>."
  }

  assert {
    condition = alltrue([
      for key, assignment in azurerm_role_assignment.additional_subscriptions :
      assignment.scope == data.azurerm_subscription.additional[split("/", key)[0]].id &&
      assignment.role_definition_name == split("/", key)[1] &&
      assignment.principal_id == azuread_service_principal.costfluent.object_id &&
      assignment.principal_type == "ServicePrincipal" &&
      assignment.skip_service_principal_aad_check == true &&
      strcontains(assignment.description, split("/", key)[0])
    ])
    error_message = "Each assignment must be on its own subscription, with its role, to Costfluent's service principal, and say which subscription it serves."
  }

  assert {
    condition     = length(azurerm_role_assignment.costfluent) == 2
    error_message = "The anchoring subscription must keep its own assignments."
  }

  assert {
    condition     = length(output.assignment_scopes) == 3
    error_message = "assignment_scopes must name the anchoring subscription and both additional ones."
  }
}

run "the_roles_follow_role_definition_names_on_every_scope" {
  command = plan

  variables {
    role_definition_names       = ["Cost Management Reader"]
    additional_subscription_ids = ["00000000-0000-0000-0000-000000000002"]
    management_group_ids        = ["mg-a"]
  }

  assert {
    condition = (
      sort(keys(azurerm_role_assignment.additional_subscriptions)) == tolist(["00000000-0000-0000-0000-000000000002/Cost Management Reader"]) &&
      sort(keys(azurerm_role_assignment.management_groups)) == tolist(["mg-a/Cost Management Reader"])
    )
    error_message = "A narrower role_definition_names must narrow every scope alike."
  }

  assert {
    condition     = azurerm_role_assignment.management_groups["mg-a/Cost Management Reader"].scope == data.azurerm_management_group.scope["mg-a"].id
    error_message = "A management group's scope must be the resource ID its data source read, not one composed from the input."
  }
}

run "a_management_group_is_assigned_at_its_own_scope" {
  command = apply

  variables {
    management_group_ids = ["mg-a"]
  }

  override_data {
    target = data.azurerm_management_group.scope
    values = {
      id               = "/providers/Microsoft.Management/managementGroups/mg-a"
      tenant_scoped_id = "/tenants/00000000-0000-0000-0000-0000000000t1/providers/Microsoft.Management/managementGroups/mg-a"
    }
  }

  assert {
    condition = (
      sort(keys(azurerm_role_assignment.management_groups)) == tolist(["mg-a/Carbon Optimization Reader", "mg-a/Cost Management Reader"]) &&
      alltrue([for assignment in azurerm_role_assignment.management_groups : assignment.scope == "/providers/Microsoft.Management/managementGroups/mg-a"])
    )
    error_message = "Each role must be assigned at the management group's own resource ID."
  }

  assert {
    condition = alltrue([
      for assignment in azurerm_role_assignment.management_groups :
      assignment.principal_id == azuread_service_principal.costfluent.object_id && strcontains(assignment.description, "mg-a")
    ])
    error_message = "Each management group assignment must go to Costfluent's service principal and name its group."
  }

  assert {
    condition     = output.assignment_scopes == sort(["/providers/Microsoft.Management/managementGroups/mg-a", data.azurerm_subscription.target.id])
    error_message = "assignment_scopes must name the subscription and the management group."
  }
}

run "the_tenant_root_group_is_accepted" {
  command = plan

  variables {
    management_group_ids = ["00000000-0000-0000-0000-0000000000t1", "Contoso_(EU).Finance-1"]
  }

  assert {
    condition     = length(azurerm_role_assignment.management_groups) == 4
    error_message = "The tenant root group, named by the tenant ID, and a name using every allowed character must be accepted."
  }
}

run "an_additional_subscription_in_another_tenant_fails_the_check" {
  command = plan

  variables {
    additional_subscription_ids = ["00000000-0000-0000-0000-000000000002"]
  }

  override_data {
    target = data.azurerm_subscription.additional
    values = {
      id        = "/subscriptions/00000000-0000-0000-0000-000000000002"
      tenant_id = "00000000-0000-0000-0000-0000000000t2"
    }
  }

  expect_failures = [check.single_tenant]
}

run "a_management_group_in_another_tenant_fails_the_check" {
  command = plan

  variables {
    management_group_ids = ["mg-a"]
  }

  override_data {
    target = data.azurerm_management_group.scope
    values = {
      id               = "/providers/Microsoft.Management/managementGroups/mg-a"
      tenant_scoped_id = "/tenants/00000000-0000-0000-0000-0000000000t2/providers/Microsoft.Management/managementGroups/mg-a"
    }
  }

  expect_failures = [check.single_tenant]
}

run "a_management_group_without_a_tenant_fails_the_check" {
  command = plan

  variables {
    management_group_ids = ["mg-a"]
  }

  override_data {
    target = data.azurerm_management_group.scope
    values = {
      id               = "/providers/Microsoft.Management/managementGroups/mg-a"
      tenant_scoped_id = "mg-a"
    }
  }

  expect_failures = [check.single_tenant]
}

run "the_tenant_check_ignores_the_case_of_a_management_group_tenant" {
  command = plan

  variables {
    management_group_ids = ["mg-a"]
  }

  override_data {
    target = data.azurerm_management_group.scope
    values = {
      id               = "/providers/Microsoft.Management/managementGroups/mg-a"
      tenant_scoped_id = "/tenants/00000000-0000-0000-0000-0000000000T1/providers/Microsoft.Management/managementGroups/mg-a"
    }
  }

  assert {
    condition     = length(azurerm_role_assignment.management_groups) == 2
    error_message = "A tenant ID differing only in case is the same tenant."
  }
}

run "an_upper_case_additional_subscription_is_refused" {
  command = plan

  variables {
    additional_subscription_ids = ["0A1B2C3D-4E5F-6A7B-8C9D-0E1F2A3B4C5D"]
  }

  expect_failures = [var.additional_subscription_ids]
}

run "the_anchoring_subscription_repeated_is_refused" {
  command = plan

  variables {
    additional_subscription_ids = ["00000000-0000-0000-0000-000000000001"]
  }

  expect_failures = [var.additional_subscription_ids]
}

run "a_management_group_resource_id_is_refused" {
  command = plan

  variables {
    management_group_ids = ["/providers/Microsoft.Management/managementGroups/mg-a"]
  }

  expect_failures = [var.management_group_ids]
}

run "a_management_group_ending_in_a_period_is_refused" {
  command = plan

  variables {
    management_group_ids = ["mg-a."]
  }

  expect_failures = [var.management_group_ids]
}

run "a_management_group_starting_with_a_hyphen_is_refused" {
  command = plan

  variables {
    management_group_ids = ["-mg-a"]
  }

  expect_failures = [var.management_group_ids]
}

run "a_management_group_over_90_characters_is_refused" {
  command = plan

  variables {
    management_group_ids = [join("", [for i in range(91) : "a"])]
  }

  expect_failures = [var.management_group_ids]
}

run "a_management_group_of_90_characters_is_accepted" {
  command = plan

  variables {
    management_group_ids = [join("", [for i in range(90) : "a"])]
  }

  assert {
    condition     = length(azurerm_role_assignment.management_groups) == 2
    error_message = "A 90-character management group ID is within Azure's limit and must be accepted."
  }
}
