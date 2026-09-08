module "costfluent" {
  source = "../.."

  subscription_id = var.subscription_id
}

output "credentials" {
  value     = module.costfluent.credentials
  sensitive = true
}

output "credentials_json" {
  value     = module.costfluent.credentials_json
  sensitive = true
}
