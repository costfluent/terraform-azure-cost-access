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
    scope, and "Carbon Optimization Reader" what it documents for reading the subscription's
    carbon emissions; together they are all Costfluent needs. Drop "Carbon Optimization Reader" to
    leave the carbon footprint report empty for this subscription. Add "Reader" only if you also
    want Costfluent to resolve resource metadata, and note that it grants read access to every
    resource in the subscription.
  EOT
  type        = list(string)
  default     = ["Cost Management Reader", "Carbon Optimization Reader"]

  validation {
    condition     = length(var.role_definition_names) > 0
    error_message = "At least one role is required; Costfluent cannot read cost data without one."
  }
}

variable "commitment_roles" {
  description = <<-EOT
    Also assign "Reservations Reader" at /providers/Microsoft.Capacity and "Savings plan Reader" at
    /providers/Microsoft.BillingBenefits, so Costfluent lists the tenant's reservations and savings
    plans under Commitments. Both are read-only, and they read every reservation and savings plan in
    the tenant, not only this subscription's.

    Only a User Access Administrator at the tenant root can assign roles at these scopes: a Global
    Administrator who has elevated access (in the Azure portal, only Global Administrators can assign
    them). Apply with that access, or leave this false and Costfluent lists no Azure reservations or
    savings plans for this connection.
  EOT
  type        = bool
  default     = false
}

variable "secret_expiry_days" {
  description = <<-EOT
    Lifetime of the client secret. The first apply from secret_rotation_days_before_expiry days
    before it expires creates a new one, so re-run this module inside that window and hand the new
    secret to Costfluent.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.secret_expiry_days >= 1 && var.secret_expiry_days <= 730
    error_message = "Must be between 1 and 730 days (Entra caps application secrets at two years)."
  }
}

variable "secret_rotation_days_before_expiry" {
  description = <<-EOT
    How many days before the client secret expires an apply starts replacing it. An apply inside
    this window rotates the secret while the old one still works; an apply before it leaves the
    secret alone. Defaults to 30, or half of secret_expiry_days rounded down when that is shorter.
  EOT
  type        = number
  default     = null

  validation {
    condition     = var.secret_rotation_days_before_expiry == null ? true : (var.secret_rotation_days_before_expiry >= 1 && var.secret_rotation_days_before_expiry < var.secret_expiry_days)
    error_message = "Must be at least 1 and less than secret_expiry_days, so the secret is replaceable before it expires and not at creation."
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
