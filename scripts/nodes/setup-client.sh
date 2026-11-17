#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
nodes="$(discover_nodes "$asg_name")"
require_nodes "$nodes" 3

expected_size="$(jq 'length' <<< "$nodes")"
# Verify the cluster before changing database accounts.
bash "$project_dir/scripts/nodes/check-nodes.sh" \
  cluster "$expected_size" "$asg_name"

read -r -s -p "Password for lab2_client: " password
printf '\n'
read -r -s -p "Confirm password: " confirmation
printf '\n'

if [[ -z "$password" || "$password" != "$confirmation" ]]; then
  echo "Passwords must match and cannot be empty." >&2
  exit 1
fi

# Compute MariaDB's native password hash locally.
# The password is not embedded in SQL or passed as a command argument.
password_hash="*$(
  printf '%s' "$password" |
    openssl dgst -sha1 -binary |
    openssl dgst -sha1 |
    awk '{print toupper($NF)}'
)"
unset password confirmation

if [[ ! "$password_hash" =~ ^\*[0-9A-F]{40}$ ]]; then
  echo "Could not generate the password hash." >&2
  exit 1
fi

node_ip="$(jq -r '.[0].public_ip' <<< "$nodes")"

ssh_script "$node_ip" <<REMOTE
set -euo pipefail

timeout 15 mariadb <<'SQL'
CREATE USER IF NOT EXISTS 'lab2_client'@'%'
  IDENTIFIED BY PASSWORD '$password_hash';

ALTER USER 'lab2_client'@'%'
  IDENTIFIED BY PASSWORD '$password_hash';

GRANT SELECT ON lab2_replication_test.* TO 'lab2_client'@'%';
SQL
REMOTE

echo "Client account configured through $node_ip."