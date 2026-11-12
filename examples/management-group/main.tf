# A whole estate through one connection: the roles on the anchoring subscription, on further
# subscriptions, and on management groups, whose subscriptions inherit them now and later.
module "costfluent" {
  source = "../.."

  subscription_id             = var.subscription_id
  additional_subscription_ids = var.additional_subscription_ids
  management_group_ids        = var.management_group_ids
}

output "credentials" {
  value     = module.costfluent.credentials
  sensitive = true
}

output "credentials_json" {
  value     = module.costfluent.credentials_json
  sensitive = true
}

output "assignment_scopes" {
  value = module.costfluent.assignment_scopes
}
