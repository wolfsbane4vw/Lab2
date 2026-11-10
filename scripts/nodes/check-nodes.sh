#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"

node_ips="$(
  terraform -chdir="$project_dir/terraform" output \
    -json database_public_ips |
    jq -er 'if length == 0 then error("No node IPs found") else .[] end'
)"

failed=0

while IFS= read -r ip; do
  echo
  echo "Checking $ip"

  if ssh \
    -i "$key_path" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "ubuntu@$ip" 'bash -s' <<'REMOTE'
set -euo pipefail

echo "Waiting for cloud-init..."
sudo -n timeout 300 cloud-init status --wait

echo "MariaDB version:"
mariadb --version

echo "Checking required packages..."
for package in mariadb-server mariadb-backup galera-4 rsync; do
  status="$(dpkg-query -W -f='${Status}' "$package")"

  if [[ "$status" != "install ok installed" ]]; then
    echo "FAIL: $package is not installed"
    exit 1
  fi

  echo "OK: $package"
done

echo "Checking MariaDB service..."
status="$(systemctl is-active mariadb || true)"

if [[ "$status" != "inactive" ]]; then
  echo "FAIL: expected inactive, found $status"
  exit 1
fi

echo "OK: MariaDB is inactive as expected"
REMOTE
  then
    echo "PASS: $ip"
  else
    echo "FAIL: $ip"
    failed=$((failed + 1))
  fi
done <<< "$node_ips"

echo
echo "Failed nodes: $failed"

if (( failed > 0 )); then
  exit 1
fi
