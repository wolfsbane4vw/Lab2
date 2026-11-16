#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"

asg_name="${1:-lab2-database}"
nodes="$(bash "$project_dir/scripts/nodes/discover-nodes.sh" "$asg_name")"

if ! jq -e '
  length >= 3 and
  all(.[]; .instance_id != null and .public_ip != null)
' <<< "$nodes" > /dev/null; then
  echo "Expected at least three nodes with IDs and public IPs." >&2
  exit 1
fi

ssh_sql() {
  local ip="$1"
  local sql="$2"

  ssh \
    -n \
    -i "$key_path" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "ubuntu@$ip" \
    "sudo -n mariadb --batch --skip-column-names --execute=\"$sql\""
}

writer_ip="$(jq -r 'sort_by(.instance_id) | .[0].public_ip' <<< "$nodes")"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"
expected_message="hello-from-lab2"

write_sql="
CREATE DATABASE IF NOT EXISTS lab2_replication_test;

CREATE TABLE IF NOT EXISTS lab2_replication_test.checks (
  run_id VARCHAR(64) PRIMARY KEY,
  message VARCHAR(255) NOT NULL
) ENGINE=InnoDB;

INSERT INTO lab2_replication_test.checks (run_id, message)
VALUES ('$run_id', '$expected_message');
"

echo "Writing test row $run_id on $writer_ip"
ssh_sql "$writer_ip" "$write_sql"

read_sql="
SET SESSION wsrep_sync_wait = 1;

SELECT message
FROM lab2_replication_test.checks
WHERE run_id = '$run_id';
"

node_ips="$(jq -r '.[].public_ip' <<< "$nodes")"
failed=0
checked=0

while IFS= read -r ip; do
  checked=$((checked + 1))

  if actual="$(ssh_sql "$ip" "$read_sql")"; then
    if [[ "$actual" == "$expected_message" ]]; then
      echo "PASS: $ip returned the test row"
    else
      echo "FAIL: $ip returned '${actual:-no row}'"
      failed=$((failed + 1))
    fi
  else
    echo "FAIL: could not query $ip"
    failed=$((failed + 1))
  fi
done <<< "$node_ips"

echo
echo "Replication test: $((checked - failed)) passed, $failed failed."

if (( failed > 0 )); then
  exit 1
fi
