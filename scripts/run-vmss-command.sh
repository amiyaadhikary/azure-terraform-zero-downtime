#!/usr/bin/env bash
set -Eeuo pipefail
set +x

environment="${1:-dev}"
[[ "$environment" == dev || "$environment" == prod ]] || { echo 'Usage: bash scripts/run-vmss-command.sh [dev|prod] [shell-command]' >&2; exit 2; }
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tf_dir="$root/terraform"
if command -v cygpath >/dev/null 2>&1; then tf_chdir="$(cygpath -w "$tf_dir")"; else tf_chdir="$tf_dir"; fi
backend="$tf_dir/backend-$environment.hcl"
[[ -f "$backend" ]] || { echo 'Bootstrap and initialize remote state first.' >&2; exit 1; }
command -v az >/dev/null && command -v terraform >/dev/null || { echo 'Azure CLI and Terraform are required.' >&2; exit 1; }

tf_output() { terraform -chdir="$tf_chdir" output -raw "$1" | tr -d '\r'; }
resource_group="$(tf_output resource_group_name)"
vmss="$(tf_output vmss_name)"
instance_id="$(az vmss list-instances --resource-group "$resource_group" --name "$vmss" --query '[0].instanceId' -o tsv | tr -d '\r')"
[[ -n "$instance_id" && "$instance_id" != None ]] || { echo 'No VMSS instance is available.' >&2; exit 1; }
if [[ $# -ge 2 ]]; then
  remote_command="$2"
else
  remote_command='hostname; id; systemctl --no-pager --full status student-registration; curl --fail --silent http://127.0.0.1:5000/health'
fi

echo "Running control-plane command on VMSS instance $instance_id (no inbound SSH connection)."
az vmss run-command invoke \
  --resource-group "$resource_group" \
  --name "$vmss" \
  --instance-id "$instance_id" \
  --command-id RunShellScript \
  --scripts "$remote_command" \
  --output jsonc
