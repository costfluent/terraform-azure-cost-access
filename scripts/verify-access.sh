#!/usr/bin/env bash
# Proves the credentials this module produced can actually read Azure cost data, by issuing the
# same Cost Details create call Costfluent's collector issues. A successful `terraform apply` only
# proves the role assignment exists; it does not prove the subscription's billing account supports
# the API, which is the failure customers actually hit.
#
# Usage, from the directory holding the module's state:
#   terraform output -json credentials | ./scripts/verify-access.sh
#   ./scripts/verify-access.sh path/to/credentials.json
set -euo pipefail

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "error: $tool is required" >&2; exit 2; }
done

if [[ $# -ge 1 ]]; then
  credentials=$(cat -- "$1")
elif [[ ! -t 0 ]]; then
  credentials=$(cat)
else
  echo "usage: terraform output -json credentials | $0   (or: $0 credentials.json)" >&2
  exit 2
fi

read -r tenant app_id password subscription_id < <(
  jq -r '[.tenant, .appId, .password, .subscriptionId] | @tsv' <<<"$credentials"
)

for name in tenant app_id password subscription_id; do
  [[ -n "${!name}" && "${!name}" != "null" ]] || { echo "error: credentials are missing $name" >&2; exit 2; }
done

echo "==> Acquiring a token for tenant $tenant"
token=$(curl -sS --fail-with-body \
  -X POST "https://login.microsoftonline.com/${tenant}/oauth2/v2.0/token" \
  -d grant_type=client_credentials \
  -d "client_id=${app_id}" \
  --data-urlencode "client_secret=${password}" \
  -d scope=https://management.azure.com/.default | jq -r .access_token)

[[ -n "$token" && "$token" != "null" ]] || { echo "error: no token returned" >&2; exit 1; }

echo "==> Requesting a cost details report for subscription $subscription_id"
end=$(date -u +%Y-%m-%d)
start=$(date -u -v-1d +%Y-%m-%d 2>/dev/null || date -u -d '1 day ago' +%Y-%m-%d)

response=$(mktemp)
trap 'rm -f "$response"' EXIT

status=$(curl -sS -o "$response" -w '%{http_code}' \
  -X POST "https://management.azure.com/subscriptions/${subscription_id}/providers/Microsoft.CostManagement/generateCostDetailsReport?api-version=2024-08-01" \
  -H "Authorization: Bearer ${token}" \
  -H 'Content-Type: application/json' \
  -d "{\"metric\":\"ActualCost\",\"timePeriod\":{\"start\":\"${start}\",\"end\":\"${end}\"}}")

case "$status" in
  200|202|204)
    echo "OK: Costfluent can read cost details for this subscription (HTTP $status)."
    ;;
  401|403)
    echo "FAILED (HTTP $status): the service principal cannot read Cost Management at this subscription." >&2
    echo "Role assignments can take a few minutes to propagate; if it persists, add \"Cost Management Contributor\" to role_definition_names." >&2
    jq -r '.error | "Azure reported \(.code): \(.message)"' <"$response" 2>/dev/null || cat "$response" >&2
    exit 1
    ;;
  400|404)
    echo "FAILED (HTTP $status): Azure rejected the request for this subscription." >&2
    echo "Cost Details requires an Enterprise Agreement or Microsoft Customer Agreement billing account; pay-as-you-go subscriptions are not supported." >&2
    jq -r '.error | "Azure reported \(.code): \(.message)"' <"$response" 2>/dev/null || cat "$response" >&2
    exit 1
    ;;
  *)
    echo "FAILED: unexpected status $status" >&2
    cat "$response" >&2
    exit 1
    ;;
esac
