#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

mode="${1:-installation}"
expected_size="${2:-3}"
asg_name="${3:-lab2-database}"

if [[ "$mode" != "installation" && "$mode" != "cluster" ]]; then
  echo "Usage: bash check-nodes.sh [installation|cluster] [expected-size] [asg-name]" >&2
  exit 1
fi

if [[ ! "$expected_size" =~ ^[1-9][0-9]*$ ]]; then
  echo "Expected cluster size must be a positive integer." >&2
  exit 1
fi

nodes="$(discover_nodes "$asg_name")"
require_nodes "$nodes"
node_ips="$(jq -r '.[].public_ip' <<< "$nodes")"

failed=0
checked=0
size_mismatches=0
summary=""
observed_sizes=""
observed_uuids=""

# Discovery is live, so replacement and scale-out nodes are included.
while IFS= read -r ip; do
  checked=$((checked + 1))
  echo "Checking $ip..."

  if node_output="$(ssh_script "$ip" "$mode" <<'REMOTE' 2>&1
set -euo pipefail

mode="$1"

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

if [[ "$mode" == "installation" ]]; then
  # Installation remains valid whether MariaDB has been started or not.
  printf 'CHECK_RESULT\t%s\t-\t-\n' "$status"
  exit 0
fi

if [[ "$status" != "active" ]]; then
  echo "FAIL: expected active, found $status"
  exit 1
fi

echo "Checking Galera status..."
galera_status="$(
  sudo -n mariadb --batch --skip-column-names --execute="
    SHOW GLOBAL STATUS
    WHERE Variable_name IN (
      'wsrep_cluster_size',
      'wsrep_cluster_status',
      'wsrep_local_state_comment',
      'wsrep_ready',
      'wsrep_connected',
      'wsrep_cluster_state_uuid'
    );
  "
)"

printf '%s\n' "$galera_status"

check_status() {
  local variable="$1"
  local expected="$2"
  local actual

  actual="$(
    awk -v name="$variable" '$1 == name { print $2 }' \
      <<< "$galera_status"
  )"

  if [[ "$actual" != "$expected" ]]; then
    echo "FAIL: $variable expected $expected, found ${actual:-missing}"
    exit 1
  fi
}

check_status wsrep_cluster_status Primary
check_status wsrep_local_state_comment Synced
check_status wsrep_ready ON
check_status wsrep_connected ON

# Report size separately: a healthy node can belong to a smaller cluster
# than the operator requested. Do not count that as a node-health failure.
reported_size="$(awk '$1 == "wsrep_cluster_size" { print $2 }' <<< "$galera_status")"
cluster_uuid="$(awk '$1 == "wsrep_cluster_state_uuid" { print $2 }' <<< "$galera_status")"

if [[ ! "$reported_size" =~ ^[1-9][0-9]*$ || -z "$cluster_uuid" ]]; then
  echo "FAIL: cluster size or cluster UUID is missing/invalid"
  exit 1
fi

printf 'CHECK_RESULT\t%s\t%s\t%s\n' "$status" "$reported_size" "$cluster_uuid"
REMOTE
  )"; then
    result="$(awk -F '\t' '$1 == "CHECK_RESULT" { print $2 "\t" $3 "\t" $4 }' <<< "$node_output")"
    if [[ -z "$result" ]]; then
      summary+="$ip  FAIL — no check result received"$'\n'
      failed=$((failed + 1))
      continue
    fi

    IFS=$'\t' read -r service reported_size cluster_uuid <<< "$result"

    if [[ "$mode" == "installation" ]]; then
      summary+="$ip  OK — startup complete, packages installed; MariaDB $service"$'\n'
    else
      summary+="$ip  OK — MariaDB active; Primary, Synced, ready, connected"$'\n'
      observed_sizes+="$reported_size"$'\n'
      observed_uuids+="$cluster_uuid"$'\n'
      if [[ "$reported_size" != "$expected_size" ]]; then
        size_mismatches=$((size_mismatches + 1))
      fi
    fi
  else
    summary+="$ip  FAIL — connection, installation, or node-health check failed"$'\n'
    failed=$((failed + 1))
    # Keep diagnostics for failures without repeating successful package logs.
    printf '%s\n' "$node_output" | sed 's/^/  /'
  fi
done <<< "$node_ips"

echo
if [[ "$mode" == "installation" ]]; then
  echo "Installation summary ($checked nodes checked):"
else
  echo "Node health ($checked nodes checked):"
fi
printf '%s' "$summary"
echo "Node checks: $((checked - failed)) passed, $failed failed."

if [[ "$mode" == "installation" ]]; then
  echo "Service state is informational; MariaDB may be active or inactive."
  if (( failed > 0 )); then
    exit 1
  fi
  exit 0
fi

identity_mismatch=0
if [[ -n "$observed_sizes" ]]; then
  sizes="$(printf '%s' "$observed_sizes" | sort -n -u | paste -sd ',' -)"
  if (( size_mismatches > 0 )); then
    echo "Cluster size: FAIL — expected $expected_size members; passing nodes report: $sizes."
    echo "This script checks the cluster; it does not add or remove nodes."
    # Offer a concrete command only when every checked node is healthy and
    # their shared reported size equals the number of addresses checked.
    if (( failed == 0 )) && [[ "$sizes" == "$checked" ]]; then
      echo "To check the current $sizes-node setup, run:"
      echo "  bash scripts/nodes/check-nodes.sh cluster $sizes"
    fi
  else
    echo "Cluster size: OK — passing nodes report $expected_size members."
  fi

  uuids="$(printf '%s' "$observed_uuids" | sort -u)"
  uuid_count="$(printf '%s\n' "$uuids" | awk 'END { print NR }')"
  if (( uuid_count > 1 )); then
    identity_mismatch=1
    echo "Cluster identity: FAIL — passing nodes report different cluster UUIDs:"
    printf '%s\n' "$uuids"
  else
    echo "Cluster identity: $uuids (same on passing nodes)."
  fi
else
  echo "Cluster size and identity: NOT CHECKED — no node passed its checks."
fi

echo "Addresses were discovered live from ASG $asg_name."

if (( failed > 0 || size_mismatches > 0 || identity_mismatch > 0 )); then
  exit 1
fi
