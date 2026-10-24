# terraform-azure-cost-access

Grants [Costfluent](https://costfluent.com) read-only access to one Azure subscription's cost data.

The module registers a Microsoft Entra application, creates its service principal and client
secret, and assigns **Cost Management Reader** and **Carbon Optimization Reader** at subscription
scope. It replaces the manual `az ad sp create-for-rbac` + `az role assignment create` sequence,
and outputs the three fields Costfluent asks for: `tenant`, `appId` and `password`.

## Requirements

- Terraform >= 1.13
- Permission to register an application in the Entra tenant (Application Developer or higher) and
  to assign roles on the subscription (Owner or User Access Administrator).
- A subscription on an **Enterprise Agreement** or **Microsoft Customer Agreement** billing
  account. Costfluent reads cost data through the Cost Details API, which Microsoft does not offer
  on the legacy pay-as-you-go program. Costfluent's **Test Connection** tells you which you have.

## Usage

```hcl
provider "azurerm" {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  features {}
}

provider "azuread" {}

module "costfluent" {
  source  = "costfluent/cost-access/azure"
  version = "~> 0.2"

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
terraform output -raw costfluent_credentials
```

In Costfluent, open **Settings**, then **Integrations**, and select **Azure**. On the **Connect**
tab, select **Add Account** and enter `tenant`, `appId` and `password` in **Azure AD tenant ID**,
**Service principal app ID** and **Service principal password**, then select **Test Connection**.
That check is the one that matters: it issues a real Cost Details request with these credentials,
so it proves Azure will actually serve your cost data. A successful `terraform apply` only proves
the role assignment exists.

Role assignments take a minute or two to propagate. A 403 immediately after apply is usually
propagation, not a misconfiguration: wait and run **Test Connection** again before changing
anything.

## One tenant

The application is registered in whichever tenant the `azuread` provider authenticates against,
while the role is assigned in the subscription's own tenant. When those differ, Terraform still
succeeds and collection later fails with an opaque access error, because Microsoft supports
cross-tenant Cost Management only partially. The module raises a warning at plan time when it sees
that mismatch rather than refusing, since a deliberate cross-tenant setup can work. If you did not
intend one, point the `azuread` provider at the subscription's tenant before applying.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `subscription_id` | Subscription to collect cost data from. Canonical lower-case GUID. | `string` | required |
| `application_display_name` | Display name of the Entra application registration. | `string` | `"Costfluent Integration"` |
| `role_definition_names` | Built-in roles assigned at subscription scope. | `list(string)` | `["Cost Management Reader", "Carbon Optimization Reader"]` |
| `secret_expiry_days` | Client secret lifetime, 1–730. | `number` | `365` |
| `secret_rotation_days_before_expiry` | Days before expiry from which an apply replaces the secret, at least 1 and less than `secret_expiry_days`. | `number` | 30, or half of `secret_expiry_days` when shorter |
| `owners` | Object IDs owning the app and service principal. Defaults to the caller. | `list(string)` | `[]` |
| `tags` | Directory tags on the app and service principal. | `list(string)` | `["costfluent", "cost-management", "terraform"]` |

## Outputs

| Name | Sensitive | Description |
|------|-----------|-------------|
| `credentials` | yes | Map of `tenant`, `appId`, `password`. |
| `credentials_json` | yes | The same map as JSON, ready to paste into Costfluent. |
| `tenant_id` | no | Entra tenant the application lives in. |
| `client_id` | no | Application (client) ID. |
| `service_principal_object_id` | no | Object ID holding the role assignments. |
| `subscription_id` | no | Subscription the roles were assigned on. |
| `subscription_display_name` | no | That subscription's name, to confirm you targeted the right one. |
| `assigned_roles` | no | Roles actually assigned. |
| `secret_expires_at` | no | When the secret stops working. |
| `secret_rotates_at` | no | From when an apply replaces the secret. |

The credential field names are Costfluent's contract. Do not rename them on the way in.

## Permissions granted

`Cost Management Reader` at `/subscriptions/<subscription_id>`: read-only access to cost and
usage data, and nothing else. It grants no access to resource contents, configuration, or data
planes.

`Carbon Optimization Reader` at the same scope: read-only access to the subscription's
provider-reported carbon emissions (`Microsoft.Carbon/carbonEmissionReports/read` and `/action`),
for Costfluent's carbon footprint report, and nothing else. Leave it out of
`role_definition_names` and that report stays empty for this subscription.

Add `"Reader"` to `role_definition_names` only if you want Costfluent to resolve resource metadata
as well; it grants read access to every resource in the subscription, which most customers do not
want and Costfluent does not require.

If cost details are refused with 403 after propagation, Microsoft may require
`Cost Management Contributor` on your agreement type. That role permits writing Cost Management
configuration (exports, budgets), so prefer it only when Reader demonstrably fails.

## Secret rotation

The client secret expires `secret_expiry_days` after it is created, at the instant the
`secret_expires_at` output shows. From `secret_rotation_days_before_expiry` days before that, at the
instant `secret_rotates_at` shows, the next apply replaces it: the old secret is deleted and the new
one is valid for another `secret_expiry_days`. An apply before `secret_rotates_at` leaves the secret
alone. Schedule an apply inside that window and give Costfluent the new value:

```bash
terraform apply
terraform output -raw costfluent_credentials
```

If no apply runs before `secret_expires_at`, Costfluent cannot collect from that instant until the
next apply and the new value arrive. To rotate at any other time, replace the timer:
`terraform apply -replace='module.costfluent.time_rotating.secret'`. Replacing the secret resource
itself (`azuread_service_principal_password.costfluent`) issues a new value with the old expiry date.

Upgrading from a version without `secret_rotation_days_before_expiry` replaces the secret once, on
the first apply, so update the password in Costfluent after that apply.

## Security

- Credential outputs are marked sensitive, so they stay out of CLI output and logs.
- The client secret is stored in Terraform state in plaintext. Keep state in an encrypted remote
  backend and never commit it.
- Removing the module with `terraform destroy` revokes Costfluent's access completely.

## License

MIT — see [LICENSE](LICENSE).
