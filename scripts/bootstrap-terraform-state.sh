#!/usr/bin/env bash
set -Eeuo pipefail
set +x

command -v az >/dev/null || { echo 'Azure CLI (az) is required.' >&2; exit 1; }
az account show >/dev/null || { echo 'Run az login and select the intended subscription first.' >&2; exit 1; }

subscription_id="$(az account show --query id -o tsv)"
location="${TFSTATE_LOCATION:-centralindia}"
resource_group="${TFSTATE_RESOURCE_GROUP:-rg-student-registration-tfstate}"
account="${TFSTATE_STORAGE_ACCOUNT:-sttf$(printf '%s' "$subscription_id" | sha256sum | cut -c1-16)}"
owner="${TFSTATE_OWNER:-$(az account show --query user.name -o tsv)}"
container="tfstate"
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="$project_root/terraform"

if [[ ! "$account" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo 'Storage account name must be 3-24 lowercase letters/digits. Set TFSTATE_STORAGE_ACCOUNT if needed.' >&2
  exit 1
fi

identity_type="$(az account show --query user.type -o tsv)"
identity_name="$(az account show --query user.name -o tsv)"
case "$identity_type" in
  user) principal_id="$(az ad signed-in-user show --query id -o tsv)"; principal_type="User" ;;
  servicePrincipal) principal_id="$(az ad sp show --id "$identity_name" --query id -o tsv)"; principal_type="ServicePrincipal" ;;
  *) echo "Unsupported Azure CLI identity type: $identity_type" >&2; exit 1 ;;
esac

az group create --name "$resource_group" --location "$location" \
  --tags Project=student-registration Environment=state "Owner=$owner" ManagedBy=bootstrap --output none
az storage account create \
  --name "$account" \
  --resource-group "$resource_group" \
  --location "$location" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --https-only true \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false \
  --tags Project=student-registration Environment=state "Owner=$owner" ManagedBy=bootstrap \
  --output none
account_id="$(az storage account show --name "$account" --resource-group "$resource_group" --query id -o tsv)"
az storage account blob-service-properties update \
  --account-name "$account" --resource-group "$resource_group" \
  --enable-versioning true --output none
az role assignment create \
  --assignee-object-id "$principal_id" \
  --assignee-principal-type "$principal_type" \
  --role 'Storage Blob Data Contributor' \
  --scope "$account_id" --output none

container_ready=false
for attempt in {1..12}; do
  if az storage container create --auth-mode login --account-name "$account" --name "$container" --public-access off --output none; then
    container_ready=true
    break
  fi
  sleep 10
done
[[ "$container_ready" == true ]] || { echo 'Could not create the private state container; check RBAC propagation.' >&2; exit 1; }

for environment in dev prod; do
  cat > "$tf_dir/backend-$environment.hcl" <<EOF
resource_group_name  = "$resource_group"
storage_account_name = "$account"
container_name       = "$container"
key                  = "student-registration/$environment.tfstate"
subscription_id      = "$subscription_id"
use_azuread_auth     = true
use_cli              = true
EOF
done

echo "Remote state is ready in $resource_group/$account/$container."
echo 'The current Entra principal has Blob Data Contributor on the state account.'
echo 'Next: terraform -chdir=terraform init -reconfigure -backend-config=backend-dev.hcl'
echo 'If this workspace already has an applied local state, migrate it once deliberately with -migrate-state before using the deploy script.'
