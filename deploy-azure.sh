#!/usr/bin/env bash
# Deploy the app to the private VM Scale Set using Managed Identity and Entra DB auth.
set -Eeuo pipefail
set +x

env_name="${1:-dev}"
[[ "$env_name" == dev || "$env_name" == prod ]] || { echo "Usage: bash $0 [dev|prod]" >&2; exit 2; }
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tf_dir="$root/terraform"
if command -v cygpath >/dev/null 2>&1; then tf_chdir="$(cygpath -w "$tf_dir")"; else tf_chdir="$tf_dir"; fi
vars="$env_name.tfvars"
[[ -f "$tf_dir/$vars" ]] || { echo "Create terraform/$vars from its example first." >&2; exit 1; }
if [[ "${ALLOW_PUBLIC_HTTP_DEMO:-false}" != "true" ]]; then
  echo "This capstone core profile exposes an unauthenticated public HTTP demo. For synthetic-data demo use only, explicitly set ALLOW_PUBLIC_HTTP_DEMO=true after reviewing the security and cost warnings." >&2
  exit 1
fi
backend_config="$tf_dir/backend-$env_name.hcl"
[[ -f "$backend_config" ]] || { echo 'Bootstrap Azure remote state first: bash ./scripts/bootstrap-terraform-state.sh'; exit 1; }
for cmd in terraform az npm node curl ssh-keygen sha256sum; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }
done
command -v zip >/dev/null || [[ -x /c/Windows/System32/tar.exe ]] || { echo "Missing command: zip (or Windows tar.exe)" >&2; exit 1; }

if [[ -z "${TF_VAR_database_admin_principal_name:-}" ]]; then
  account_type="$(az account show --query user.type --output tsv | tr -d '\r')"
  account_name="$(az account show --query user.name --output tsv | tr -d '\r')"
  case "$account_type" in
    user)
      TF_VAR_database_admin_principal_name="$(az ad signed-in-user show --query userPrincipalName --output tsv | tr -d '\r')"
      TF_VAR_database_admin_principal_type="User"
      ;;
    servicePrincipal)
      TF_VAR_database_admin_principal_name="$(az ad sp show --id "$account_name" --query displayName --output tsv | tr -d '\r')"
      TF_VAR_database_admin_principal_type="ServicePrincipal"
      ;;
    *)
      echo "Could not map Azure CLI identity type '$account_type' to a PostgreSQL Entra administrator. Set TF_VAR_database_admin_principal_name and TF_VAR_database_admin_principal_type." >&2
      exit 1
      ;;
  esac
  [[ -n "$TF_VAR_database_admin_principal_name" && "$TF_VAR_database_admin_principal_name" != None ]] || {
    echo 'Could not read the current Entra principal name. Set TF_VAR_database_admin_principal_name manually.' >&2
    exit 1
  }
  export TF_VAR_database_admin_principal_name TF_VAR_database_admin_principal_type
fi

temp_dir="$(mktemp -d)"
db_token=""
cleanup() {
  unset DB_BOOTSTRAP_TOKEN db_token TF_VAR_vm_admin_ssh_public_key
  rm -f "$tf_dir/.deploy-$env_name.tfplan"
  rm -rf "$temp_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ -z "${TF_VAR_vm_admin_ssh_public_key:-}" ]]; then
  ssh-keygen -q -t ed25519 -N '' -C student-registration-bootstrap -f "$temp_dir/vmss-bootstrap"
  export TF_VAR_vm_admin_ssh_public_key="$(<"$temp_dir/vmss-bootstrap.pub")"
fi

stage="$temp_dir/release"
mkdir -p "$stage"
cp "$root/app/backend/package.json" "$root/app/backend/package-lock.json" "$stage/"
cp -R "$root/app/backend/src" "$root/app/backend/database" "$stage/"
npm --prefix "$root/app/backend" ci --omit=dev
npm --prefix "$root/app/frontend" ci
VITE_API_URL="" npm --prefix "$root/app/frontend" run build
mkdir -p "$stage/public"
cp -R "$root/app/frontend/dist/." "$stage/public/"
if command -v zip >/dev/null 2>&1; then
  (cd "$stage" && zip -qr "$temp_dir/release.zip" .)
else
  (cd "$stage" && /c/Windows/System32/tar.exe -a -cf "$(cygpath -w "$temp_dir/release.zip")" *)
fi
release_id="$(cd "$stage" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-16)"
export TF_VAR_api_release_version="$release_id"

# Each environment has its own remote state key. Reconfigure the backend rather
# than migrating the previously selected environment's state into this key.
terraform -chdir="$tf_chdir" init -reconfigure -backend-config="$(basename "$backend_config")"
terraform -chdir="$tf_chdir" fmt -check -recursive
terraform -chdir="$tf_chdir" validate
terraform -chdir="$tf_chdir" plan -var-file="$vars" -out=".deploy-$env_name.tfplan"
printf '\nApply this infrastructure plan? Type YES: '
read -r confirmation
[[ "$confirmation" == YES ]] || { echo 'Cancelled before terraform apply.' >&2; exit 1; }
terraform -chdir="$tf_chdir" apply ".deploy-$env_name.tfplan"

output() { terraform -chdir="$tf_chdir" output -raw "$1" | tr -d '\r'; }
storage="$(output storage_account_name)"
backup_storage="$(output database_backup_storage_account_name)"
release_container="$(output release_container_name)"
gateway="$(output api_url)"
db_host="$(output postgres_fqdn)"
db_name="$(output postgres_database_name)"
db_admin="$(output database_admin_principal_name)"
db_app="$(output database_app_login)"
vmss_identity="$(output vmss_principal_id)"
resource_group="$(output resource_group_name)"
vmss_name="$(output vmss_name)"

publish_ready=false
for attempt in {1..60}; do
  if az storage container create --auth-mode login --account-name "$storage" --name "$release_container" --public-access off --output none \
    && az storage container create --auth-mode login --account-name "$backup_storage" --name backups --public-access off --output none \
    && az storage blob upload --auth-mode login --account-name "$storage" --container-name "$release_container" --name "api-$release_id.zip" --file "$temp_dir/release.zip" --overwrite --output none; then
    publish_ready=true
    break
  fi
  sleep 10
done
[[ "$publish_ready" == true ]] || { echo 'Could not upload the frontend or API release. Check the Storage role assignment and retry.' >&2; exit 1; }

# Set up tables as the Entra admin and map the VMSS identity to a least-privilege
# PostgreSQL role from inside the private VMSS subnet (PostgreSQL has public access disabled).
instance_id="$(az vmss list-instances --resource-group "$resource_group" --name "$vmss_name" --query '[0].instanceId' -o tsv | tr -d '\r')"
db_token="$(az account get-access-token --resource https://ossrdbms-aad.database.windows.net --query accessToken --output tsv | tr -d '\r')"
bootstrap_cmd="set -eu; for wait_try in \$(seq 1 60); do if [ -f /opt/student-registration/database/bootstrap-managed-identity.js ] && [ -d /opt/student-registration/node_modules/pg ]; then break; fi; sleep 10; done; cd /opt/student-registration && DB_HOST='${db_host}' DB_NAME='${db_name}' DB_BOOTSTRAP_USER='${db_admin}' DB_BOOTSTRAP_TOKEN='${db_token}' DB_APP_USER='${db_app}' DB_APP_OBJECT_ID='${vmss_identity}' DB_SSL=true node /opt/student-registration/database/bootstrap-managed-identity.js && systemctl restart student-registration.service"
az vmss run-command invoke \
  --resource-group "$resource_group" \
  --name "$vmss_name" \
  --instance-id "$instance_id" \
  --command-id RunShellScript \
  --scripts "$bootstrap_cmd" \
  --output none
unset db_token bootstrap_cmd

ready=false
for attempt in {1..90}; do
  if curl --fail --silent --max-time 10 "$gateway/health" >/dev/null; then ready=true; break; fi
  sleep 20
done
[[ "$ready" == true ]] || { echo 'App health check failed. Inspect VMSS cloud-init and application logs.' >&2; exit 1; }
printf '\nDeployment is ready.\nApp: %s\nHealth: %s/health\n' "$gateway" "$gateway"
