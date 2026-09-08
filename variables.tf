variable "subscription_id" {
  description = "The Azure subscription Costfluent collects cost data from. One subscription per connection."
  type        = string

  validation {
    # Costfluent stores the subscription as a canonical lower-case GUID and builds the Cost
    # Management scope string from it, so a braced or upper-case id would produce a scope that
    # never matches the one the collector asks for.
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", var.subscription_id))
    error_message = "Must be a canonical lower-case GUID, e.g. 00000000-0000-0000-0000-000000000000."
  }
}

variable "application_display_name" {
  description = "Display name of the Microsoft Entra application registration Costfluent authenticates as."
  type        = string
  default     = "Costfluent Integration"

  validation {
    condition     = length(trimspace(var.application_display_name)) > 0
    error_message = "Must not be empty."
  }
}

variable "role_definition_names" {
  description = <<-EOT
    Built-in roles assigned to the service principal at subscription scope.

    "Cost Management Reader" is what Microsoft documents for reading cost data at subscription
    scope, and is all Costfluent needs. Add "Reader" only if you also want Costfluent to resolve
    resource metadata, and note that it grants read access to every resource in the subscription.
  EOT
  type        = list(string)
  default     = ["Cost Management Reader"]

  validation {
    condition     = length(var.role_definition_names) > 0
    error_message = "At least one role is required; Costfluent cannot read cost data without one."
  }
}

variable "secret_expiry_days" {
  description = <<-EOT
    Lifetime of the client secret. The secret is re-created on the first apply after it expires,
    so re-run this module on that schedule and hand the new secret to Costfluent.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.secret_expiry_days >= 1 && var.secret_expiry_days <= 730
    error_message = "Must be between 1 and 730 days (Entra caps application secrets at two years)."
  }
}

variable "owners" {
  description = <<-EOT
    Object IDs of the directory principals that own the application and service principal.
    Defaults to the principal running Terraform, so the registration is never left ownerless.
  EOT
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Directory tags applied to the application and service principal."
  type        = list(string)
  default     = ["costfluent", "cost-management", "terraform"]
}
