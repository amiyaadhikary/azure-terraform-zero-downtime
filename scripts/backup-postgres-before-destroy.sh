#!/usr/bin/env bash
set -Eeuo pipefail
set +x

environment="${1:-dev}"
[[ "$environment" == dev || "$environment" == prod ]] || { echo 'Usage: bash scripts/backup-postgres-before-destroy.sh [dev|prod]' >&2; exit 2; }
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="$root/terraform"
if command -v cygpath >/dev/null 2>&1; then tf_chdir="$(cygpath -w "$tf_dir")"; else tf_chdir="$tf_dir"; fi
[[ -f "$tf_dir/backend-$environment.hcl" ]] || { echo 'Bootstrap and initialize remote state first.' >&2; exit 1; }
command -v az >/dev/null && command -v terraform >/dev/null || { echo 'Azure CLI and Terraform are required.' >&2; exit 1; }

tf_output() { terraform -chdir="$tf_chdir" output -raw "$1" | tr -d '\r'; }
resource_group="$(tf_output resource_group_name)"
vmss="$(tf_output vmss_name)"
storage="$(tf_output database_backup_storage_account_name)"
db_host="$(tf_output postgres_fqdn)"
db_name="$(tf_output postgres_database_name)"
db_user="$(tf_output database_app_login)"
instance_id="$(az vmss list-instances --resource-group "$resource_group" --name "$vmss" --query '[0].instanceId' -o tsv | tr -d '\r')"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo 'No VMSS instance is available to reach the private database.' >&2; exit 1; }
backup_name="postgres-${environment}-$(date -u +%Y%m%dT%H%M%SZ).dump"

az storage container-rm create --resource-group "$resource_group" --storage-account "$storage" --name backups --output none 2>/dev/null || \
  az storage container create --auth-mode login --account-name "$storage" --name backups --public-access off --output none

read -r -d '' remote_script <<EOF || true
set -eu
set +x
db_token="\$(curl --fail --silent --show-error --retry 4 --header 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fossrdbms-aad.database.windows.net' | jq -er '.access_token')"
storage_token="\$(curl --fail --silent --show-error --retry 4 --header 'Metadata: true' 'http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https%3A%2F%2Fstorage.azure.com' | jq -er '.access_token')"
dump_file="/var/tmp/${backup_name}"
trap 'unset db_token storage_token PGPASSWORD; rm -f "\$dump_file"' EXIT
cd /opt/student-registration
DB_HOST='${db_host}' DB_NAME='${db_name}' DB_USER='${db_user}' DB_TOKEN="\$db_token" DUMP_FILE="\$dump_file" node -e '
const fs = require("fs");
const { Client } = require("pg");
(async () => {
  const client = new Client({
    host: process.env.DB_HOST,
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_TOKEN,
    port: 5432,
    ssl: { rejectUnauthorized: true },
  });
  await client.connect();
  const res = await client.query("SELECT * FROM students ORDER BY id");
  fs.writeFileSync(process.env.DUMP_FILE, JSON.stringify({ exported_at: new Date().toISOString(), students: res.rows }, null, 2));
  await client.end();
})();
'
unset db_token
curl --fail --silent --show-error --retry 3 -X PUT --data-binary "@\$dump_file" \
  --header "Authorization: Bearer \$storage_token" \
  --header 'x-ms-blob-type: BlockBlob' \
  --header 'x-ms-version: 2023-11-03' \
  --header 'Content-Type: application/json' \
  'https://${storage}.blob.core.windows.net/backups/${backup_name}'
unset storage_token
echo 'PostgreSQL backup uploaded to the private backups container.'
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
