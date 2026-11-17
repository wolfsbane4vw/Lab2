#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

client_ip="$(
  terraform -chdir="$project_dir/terraform" \
    output -raw test_client_public_ip
)"

nlb_host="$(
  terraform -chdir="$project_dir/terraform" \
    output -raw database_endpoint
)"

ssh -t \
  -i "$project_dir/terraform/database-key.pem" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "ubuntu@$client_ip" \
  "sudo -n timeout 300 cloud-init status --wait &&
   python3 /opt/lab2-client/test_database.py '$nlb_host'"
