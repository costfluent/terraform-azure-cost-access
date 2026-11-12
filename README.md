# terraform-azure-cost-access

Grants [Costfluent](https://costfluent.com) read-only access to the cost data of one Azure
subscription, of more subscriptions in the same tenant, or of whole management groups, through one
connection.

The module registers a Microsoft Entra application, creates its service principal and client
secret, and assigns **Cost Management Reader** and **Carbon Optimization Reader** on the
subscription and on every further subscription and management group you list. With `commitment_roles`, it also assigns **Reservations Reader** and **Savings plan Reader**
for the tenant, so Costfluent lists your reservations and savings plans. It replaces the manual
`az ad sp create-for-rbac` + `az role assignment create` sequence, and outputs the three fields
Costfluent asks for: `tenant`, `appId` and `password`.

## Requirements

- Terraform >= 1.9 or OpenTofu >= 1.12, with the providers azuread >= 3.7.0, < 4.0.0, azurerm
  >= 5.0.0, < 6.0.0 and time >= 0.9.1, < 1.0.0.
- Permission to register an application in the Entra tenant (Application Developer or higher) and
  to assign roles on the subscription (Owner or User Access Administrator).
- For `commitment_roles` only: User Access Administrator at the tenant root, which a Global
  Administrator gets by
  [elevating access](https://learn.microsoft.com/en-us/azure/role-based-access-control/elevate-access-global-admin).
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
  version = "~> 0.5"

  subscription_id = "00000000-0000-0000-0000-000000000000"

  # Optional: true also lets Costfluent list the tenant's reservations and savings plans. Applying
  # it needs User Access Administrator at the tenant root (see Permissions granted).
  commitment_roles = false
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

## Several subscriptions

One connection can collect a whole estate. List further subscriptions in
`additional_subscription_ids`, or name management groups in `management_group_ids` so every
subscription under them, including ones created later, inherits the roles:

```hcl
provider "azurerm" {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  features {}
}

provider "azuread" {}

module "costfluent" {
  source  = "costfluent/cost-access/azure"
  version = "~> 0.5"

  subscription_id             = "00000000-0000-0000-0000-000000000000"
  additional_subscription_ids = ["11111111-1111-1111-1111-111111111111"]
  management_group_ids        = ["finance"]
}
```

`subscription_id` stays the subscription the connection is anchored on. When you connect,
Costfluent lists every subscription the service principal can read and keeps each one that serves
cost data; it has about 90 seconds to check them, so in a large estate some are left for its daily
health check, which adds them without a new connection. A subscription another Costfluent
connection already collects stays with that connection. Assigning at a management group needs
Owner or User Access Administrator on it, and the tenant root group's ID is the tenant ID.
`assignment_scopes` lists every scope the roles were assigned on.

## One tenant

The application is registered in whichever tenant the `azuread` provider authenticates against,
while the roles are assigned in each subscription's own tenant, and management groups are read
through the `azurerm` provider's tenant. When those differ, Terraform still
succeeds and collection later fails with an opaque access error, because Microsoft supports
cross-tenant Cost Management only partially. The module raises a warning at plan time when it sees
that mismatch, for `subscription_id`, every additional subscription and every management group,
rather than refusing, since a deliberate cross-tenant setup can work. If you did not intend one,
point both providers at the subscriptions' tenant before applying, and connect each tenant with its
own module call.

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `subscription_id` | Subscription the connection is anchored on. Canonical lower-case GUID. | `string` | required |
| `additional_subscription_ids` | More subscriptions in the same tenant to assign the roles on. | `set(string)` | `[]` |
| `management_group_ids` | Management group IDs to assign the roles on, inherited by every subscription under them. | `set(string)` | `[]` |
| `application_display_name` | Display name of the Entra application registration. | `string` | `"Costfluent Integration"` |
| `role_definition_names` | Built-in roles assigned on every subscription and management group. | `list(string)` | `["Cost Management Reader", "Carbon Optimization Reader"]` |
| `commitment_roles` | Also assign Reservations Reader at `/providers/Microsoft.Capacity` and Savings plan Reader at `/providers/Microsoft.BillingBenefits`, for the tenant's reservations and savings plans. Needs User Access Administrator at the tenant root. | `bool` | `false` |
| `secret_expiry_days` | Client secret lifetime, 2–730. | `number` | `365` |
| `secret_rotation_days_before_expiry` | Days before expiry from which an apply replaces the secret, at least 1 and less than `secret_expiry_days`. | `number` | `null`: 30, or half of `secret_expiry_days` when shorter |
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
| `subscription_id` | no | Subscription the connection is anchored on. |
| `subscription_display_name` | no | That subscription's name, to confirm you targeted the right one. |
| `assigned_roles` | no | Roles assigned on every scope in `assignment_scopes`. |
| `assignment_scopes` | no | Resource IDs of every subscription and management group the roles are assigned on. |
| `secret_expires_at` | no | When the secret stops working. |
| `secret_rotates_at` | no | From when an apply replaces the secret. |

The credential field names are Costfluent's contract. Do not rename them on the way in.

## Permissions granted

`Cost Management Reader` at `/subscriptions/<subscription_id>`, at each subscription in
`additional_subscription_ids` and at each management group in `management_group_ids`: read-only
access to cost and usage data. It grants no access to resource contents, configuration, or data
planes. Microsoft's role also carries `Microsoft.Support/*`, which can open and read support
requests and which Costfluent never calls; at a management group it reaches every subscription
under the group.

`Carbon Optimization Reader` at the same scope: read-only access to the subscription's
provider-reported carbon emissions (`Microsoft.Carbon/carbonEmissionReports/read` and `/action`),
for Costfluent's carbon footprint report, and nothing else. Leave it out of
`role_definition_names` and that report stays empty for this subscription.

`Reservations Reader` at `/providers/Microsoft.Capacity` and `Savings plan Reader` at
`/providers/Microsoft.BillingBenefits`, only when `commitment_roles` is `true`: read-only access to
every reservation and savings plan in the tenant, not only this subscription's, for Costfluent's
**Commitments** list. Neither can buy, change or cancel one. Microsoft grants these roles only at
these tenant-level scopes, and only a User Access Administrator at the tenant root can assign them
there; in the Azure portal, only Global Administrators can. Left `false`, Costfluent lists no Azure
reservations or savings plans for this connection, and everything else works as before.

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
