#!/usr/bin/env bash
# Initial creation and joining are explicit operations; this is not recovery.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

action="${1:-}"
asg_name="${2:-lab2-database}"
if [[ "$action" != "init" && "$action" != "join" ]]; then
  echo "Usage: bash cluster.sh init|join [asg-name]" >&2
  exit 1
fi

nodes="$(discover_nodes "$asg_name")"
require_nodes "$nodes" 3
rows="$(jq -r '.[] | [.instance_id, .private_ip, .public_ip] | @tsv' <<< "$nodes")"
seed_ips="$(jq -r 'map(.private_ip) | join(",")' <<< "$nodes")"

# Check every initial node before changing any node. Existing data needs recovery.
check_fresh() {
  ssh_script "$1" <<'REMOTE'
set -euo pipefail
timeout 300 cloud-init status --wait
if systemctl is-active --quiet mariadb ||
   [[ -e /var/lib/mysql/grastate.dat || -e /var/lib/mysql/gvwstate.dat ]]; then
  echo "Refusing fresh setup: MariaDB is running or previous Galera state exists." >&2
  exit 1
fi
if ! grep -q '^wsrep_cluster_name=' /etc/mysql/mariadb.conf.d/60-galera.cnf; then
  echo "Common Galera configuration is missing. Use the updated Terraform launch template." >&2
  exit 1
fi
REMOTE
}

configure_node() {
  local ip="$1" node_id="$2" private_ip="$3"
  ssh_script "$ip" "$node_id" "$private_ip" "$seed_ips" <<'REMOTE'
set -euo pipefail
if systemctl is-active --quiet mariadb; then
  echo "Refusing to overwrite a running node's configuration." >&2
  exit 1
fi
cat > /etc/mysql/mariadb.conf.d/90-galera-node.cnf <<EOF
[mysqld]
wsrep_on=ON
wsrep_node_name=$1
wsrep_node_address=$2
wsrep_cluster_address=gcomm://$3
EOF
REMOTE
}

status_sql="SHOW GLOBAL STATUS WHERE Variable_name IN (
  'wsrep_cluster_status', 'wsrep_local_state_comment',
  'wsrep_ready', 'wsrep_connected');"

node_ready() {
  local status
  status="$(ssh_sql "$1" "$status_sql")" || return 1
  awk '
    $1 == "wsrep_cluster_status" && $2 == "Primary" { ok++ }
    $1 == "wsrep_local_state_comment" && $2 == "Synced" { ok++ }
    $1 == "wsrep_ready" && $2 == "ON" { ok++ }
    $1 == "wsrep_connected" && $2 == "ON" { ok++ }
    END { exit (ok != 4) }
  ' <<< "$status"
}

wait_ready() {
  local attempt
  for attempt in {1..30}; do
    if node_ready "$1" 2>/dev/null; then
      return 0
    fi
    sleep 2
  done
  echo "Node $1 did not become ready. Inspect its MariaDB journal; do not rebootstrap." >&2
  return 1
}

if [[ "$action" == "init" ]]; then
  while IFS=$'\t' read -r node_id private_ip public_ip; do
    echo "Checking fresh node $node_id"
    check_fresh "$public_ip"
  done <<< "$rows"

  while IFS=$'\t' read -r node_id private_ip public_ip; do
    echo "Configuring $node_id"
    configure_node "$public_ip" "$node_id" "$private_ip"
  done <<< "$rows"

  first_ip="$(jq -r '.[0].public_ip' <<< "$nodes")"
  echo "Bootstrapping once on $first_ip"
  check_fresh "$first_ip"
  ssh_node "$first_ip" sudo -n galera_new_cluster
  wait_ready "$first_ip"
else
  # Joining never bootstraps. Require a healthy existing cluster first.
  primary_found=false
  while IFS=$'\t' read -r node_id private_ip public_ip; do
    if node_ready "$public_ip" 2>/dev/null; then
      primary_found=true
      break
    fi
  done <<< "$rows"
  if [[ "$primary_found" != true ]]; then
    echo "No healthy existing cluster found. Join will not bootstrap or recover one." >&2
    exit 1
  fi
fi

while IFS=$'\t' read -r node_id private_ip public_ip; do
  if [[ "$action" == "join" ]] && ! ssh_node "$public_ip" sudo -n systemctl is-active --quiet mariadb; then
    check_fresh "$public_ip"
    configure_node "$public_ip" "$node_id" "$private_ip"
  fi
  echo "Starting/checking $node_id"
  ssh_node "$public_ip" sudo -n systemctl start mariadb
  wait_ready "$public_ip"
done <<< "$rows"

bash "$project_dir/scripts/nodes/check-nodes.sh" cluster "$(jq 'length' <<< "$nodes")" "$asg_name"
