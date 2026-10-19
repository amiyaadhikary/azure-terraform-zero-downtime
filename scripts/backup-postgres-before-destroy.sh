#!/usr/bin/env bash
set -Eeuo pipefail
set +x

environment="${1:-dev}"
[[ "$environment" == dev || "$environment" == prod ]] || { echo 'Usage: bash scripts/backup-postgres-before-destroy.sh [dev|prod]' >&2; exit 2; }
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="$root/terraform"
[[ -f "$tf_dir/backend-$environment.hcl" ]] || { echo 'Bootstrap and initialize remote state first.' >&2; exit 1; }
command -v az >/dev/null && command -v terraform >/dev/null || { echo 'Azure CLI and Terraform are required.' >&2; exit 1; }

tf_output() { terraform -chdir="$tf_dir" output -raw "$1"; }
resource_group="$(tf_output resource_group_name)"
vmss="$(tf_output vmss_name)"
storage="$(tf_output database_backup_storage_account_name)"
db_host="$(tf_output postgres_fqdn)"
db_name="$(tf_output postgres_database_name)"
db_user="$(tf_output database_app_login)"
instance_id="$(az vmss list-instances --resource-group "$resource_group" --name "$vmss" --query '[0].instanceId' -o tsv)"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo 'No VMSS instance is available to reach the private database.' >&2; exit 1; }
backup_name="postgres-${environment}-$(date -u +%Y%m%dT%H%M%SZ).dump"

az storage container create --auth-mode login --account-name "$storage" --name backups --public-access off --output none

read -r -d '' remote_script <<EOF || true
set -Eeuo pipefail
set +x
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq postgresql-client
db_token="\$(curl --fail --silent --show-error --retry 4 --header 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fossrdbms-aad.database.windows.net' | jq -er '.access_token')"
storage_token="\$(curl --fail --silent --show-error --retry 4 --header 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com' | jq -er '.access_token')"
dump_file="/var/tmp/${backup_name}"
trap 'unset db_token storage_token PGPASSWORD; rm -f "\$dump_file"' EXIT
PGPASSWORD="\$db_token" PGSSLMODE=require pg_dump --host '${db_host}' --username '${db_user}' --dbname '${db_name}' --format=custom --no-owner --no-acl --file "\$dump_file"
unset db_token PGPASSWORD
curl --fail --silent --show-error --retry 3 -X PUT --data-binary "@\$dump_file" \
  --header "Authorization: Bearer \$storage_token" \
  --header 'x-ms-blob-type: BlockBlob' \
  --header 'x-ms-version: 2023-11-03' \
  --header 'Content-Type: application/octet-stream' \
  'https://${storage}.blob.core.windows.net/backups/${backup_name}'
unset storage_token
echo 'PostgreSQL dump uploaded to the private backups container.'
EOF

echo "Creating database export from VMSS instance $instance_id and uploading it to the private backups container..."
az vmss run-command invoke \
  --resource-group "$resource_group" \
  --name "$vmss" \
  --instance-id "$instance_id" \
  --command-id RunShellScript \
  --scripts "$remote_script" \
  --output jsonc
echo "Backup blob: https://${storage}.blob.core.windows.net/backups/${backup_name}"
echo 'Verify the blob exists and test a restore before destroying the database.'
