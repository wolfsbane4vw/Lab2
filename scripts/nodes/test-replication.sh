#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
nodes="$(discover_nodes "$asg_name")"
require_nodes "$nodes" 3

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
