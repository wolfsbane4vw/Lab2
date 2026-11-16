#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"

asg_name="${1:-lab2-database}"
nodes="$(bash "$project_dir/scripts/nodes/discover-nodes.sh" "$asg_name")"

if ! jq -e '
  length >= 3 and
  all(.[]; .public_ip != null)
' <<< "$nodes" > /dev/null; then
  echo "Expected at least three nodes with public IP addresses." >&2
  exit 1
fi

node_ips="$(jq -r '.[].public_ip' <<< "$nodes")"

ssh_node() {
  local ip="$1"
  shift

  ssh \
    -n \
    -i "$key_path" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "ubuntu@$ip" "$@"
}

while IFS= read -r ip; do
  echo "Starting MariaDB on $ip"
  ssh_node "$ip" sudo -n systemctl start mariadb
done <<< "$node_ips"

status_sql="
SHOW GLOBAL STATUS
WHERE Variable_name IN (
  'wsrep_cluster_size',
  'wsrep_cluster_status',
  'wsrep_local_state_comment',
  'wsrep_ready',
  'wsrep_cluster_state_uuid'
);
"

while IFS= read -r ip; do
  echo
  echo "Cluster status on $ip"
  ssh_node "$ip" "sudo -n mariadb --execute=\"$status_sql\""
done <<< "$node_ips"
