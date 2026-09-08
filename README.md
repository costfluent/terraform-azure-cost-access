# terraform-azure-cost-access

Grants [Costfluent](https://costfluent.io) read-only access to one Azure subscription's cost data.

The module registers a Microsoft Entra application, creates its service principal and client
secret, and assigns **Cost Management Reader** at subscription scope. It replaces the manual
`az ad sp create-for-rbac` + `az role assignment create` sequence, and outputs the four fields
Costfluent asks for.

## Requirements

- Terraform >= 1.5
- Permission to register an application in the Entra tenant (Application Developer or higher) and
  to assign roles on the subscription (Owner or User Access Administrator).
- A subscription on an **Enterprise Agreement** or **Microsoft Customer Agreement** billing
  account. Costfluent reads cost data through the Cost Details API, which Microsoft does not offer
  on the legacy pay-as-you-go program. `scripts/verify-access.sh` tells you which you have.

## Usage

```hcl
provider "azurerm" {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  features {}
}

provider "azuread" {}

module "costfluent" {
  source  = "costfluent/cost-access/azure"
  version = "~> 1.0"

  subscription_id = "00000000-0000-0000-0000-000000000000"
}

output "costfluent_credentials" {
  value     = module.costfluent.credentials_json
  sensitive = true
}
```

Then:

```bash
terraform apply

# Confirm Azure will actually serve cost data to these credentials.
terraform output -json credentials | ./scripts/verify-access.sh

# Copy them into Costfluent → Providers → Add provider → Microsoft Azure.
terraform output -raw credentials_json | pbcopy
```

Role assignments take a minute or two to propagate. A 403 immediately after apply is usually
propagation, not a misconfiguration — re-run the verify script before changing anything.

## One tenant

The application is registered in whichever tenant the `azuread` provider authenticates against,
while the role is assigned in the subscription's own tenant. When those differ, Terraform still
succeeds and collection later fails with an opaque access error, because Microsoft supports
cross-tenant Cost Management only partially. The module raises a warning at plan time when it sees
that mismatch rather than refusing, since a deliberate cross-tenant setup can work — but if you did
not intend one, point the `azuread` provider at the subscription's tenant before applying.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `subscription_id` | Subscription to collect cost data from. Canonical lower-case GUID. | `string` | required |
| `application_display_name` | Display name of the Entra application registration. | `string` | `"Costfluent Integration"` |
| `role_definition_names` | Built-in roles assigned at subscription scope. | `list(string)` | `["Cost Management Reader"]` |
| `secret_expiry_days` | Client secret lifetime, 1–730. | `number` | `365` |
| `owners` | Object IDs owning the app and service principal. Defaults to the caller. | `list(string)` | `[]` |
| `tags` | Directory tags on the app and service principal. | `list(string)` | `["costfluent", "cost-management", "terraform"]` |

## Outputs

| Name | Sensitive | Description |
|------|-----------|-------------|
| `credentials` | yes | Map of `tenant`, `appId`, `password`, `subscriptionId`. |
| `credentials_json` | yes | The same map as JSON, ready to paste into Costfluent. |
| `tenant_id` | no | Entra tenant the application lives in. |
| `client_id` | no | Application (client) ID. |
| `service_principal_object_id` | no | Object ID holding the role assignments. |
| `subscription_id` | no | Subscription the roles were assigned on. |
| `subscription_display_name` | no | That subscription's name, to confirm you targeted the right one. |
| `assigned_roles` | no | Roles actually assigned. |
| `secret_expires_at` | no | When the secret stops working. |

The credential field names are Costfluent's contract. Do not rename them on the way in.

## Permissions granted

`Cost Management Reader` at `/subscriptions/<subscription_id>` — read-only access to cost and
usage data, and nothing else. It grants no access to resource contents, configuration, or data
planes.

Add `"Reader"` to `role_definition_names` only if you want Costfluent to resolve resource metadata
as well; it grants read access to every resource in the subscription, which most customers do not
want and Costfluent does not require.

If cost details are refused with 403 after propagation, Microsoft may require
`Cost Management Contributor` on your agreement type. That role permits writing Cost Management
configuration (exports, budgets), so prefer it only when Reader demonstrably fails.

## Secret rotation

The client secret expires after `secret_expiry_days`. Terraform re-creates it on the first apply
after that date; feed the new value to Costfluent when it does. To rotate early:

```bash
terraform apply -replace='module.costfluent.azuread_service_principal_password.costfluent'
```

## Security

- Credential outputs are marked sensitive, so they stay out of CLI output and logs.
- The client secret is stored in Terraform state in plaintext. Keep state in an encrypted remote
  backend and never commit it.
- Removing the module with `terraform destroy` revokes Costfluent's access completely.

## License

MIT — see [LICENSE](LICENSE).
