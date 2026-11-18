#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if (( $# > 1 )) || [[ "${1:-}" != "" && "${1:-}" != "--password-stdin" ]]; then
  echo "Usage: bash scripts/nodes/test-load-balancer.sh [--password-stdin]" >&2
  exit 1
fi

client_ip="$(
  terraform -chdir="$project_dir/terraform" \
    output -raw test_client_public_ip
)"

nlb_host="$(
  terraform -chdir="$project_dir/terraform" \
    output -raw database_endpoint
)"

ssh_options=(
  -i "$project_dir/terraform/database-key.pem"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

# Startup checks must not consume the password sent through SSH stdin.
remote_command="sudo -n timeout 300 cloud-init status --wait </dev/null &&
  python3 /opt/lab2-client/test_database.py '$nlb_host'"

if [[ "${1:-}" == "--password-stdin" ]]; then
  exec ssh -T "${ssh_options[@]}" "ubuntu@$client_ip" \
    "$remote_command --password-stdin"
else
  exec ssh -t "${ssh_options[@]}" "ubuntu@$client_ip" "$remote_command"
fi
