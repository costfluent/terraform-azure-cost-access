variable "subscription_id" {
  description = "Subscription the connection is anchored on; the azurerm provider authenticates against it."
  type        = string
}

variable "additional_subscription_ids" {
  description = "More subscriptions in the same tenant to collect."
  type        = set(string)
  default     = []
}

variable "management_group_ids" {
  description = "Management groups whose subscriptions to collect. Assigning there needs Owner or User Access Administrator on each."
  type        = set(string)
  default     = []
}
