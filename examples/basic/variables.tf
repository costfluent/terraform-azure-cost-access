variable "subscription_id" {
  description = "Subscription to connect to Costfluent."
  type        = string
}

variable "commitment_roles" {
  description = "Also assign Reservations Reader and Savings plan Reader for the whole tenant. Needs User Access Administrator at the tenant root."
  type        = bool
  default     = false
}
