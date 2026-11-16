#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"
bootstrap_script="$project_dir/scripts/provisioning/bootstrap-node.sh"

asg_name="${1:-lab2-database}"
nodes="$(bash "$project_dir/scripts/nodes/discover-nodes.sh" "$asg_name")"

first_node="$(
  jq -ce 'sort_by(.instance_id) | .[0] // error("No nodes found")' \
    <<< "$nodes"
)"

node_id="$(jq -er '.instance_id' <<< "$first_node")"
public_ip="$(jq -er '.public_ip' <<< "$first_node")"

echo "Bootstrapping the initial cluster on $node_id at $public_ip"

ssh \
  -i "$key_path" \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  -o StrictHostKeyChecking=accept-new \
  "ubuntu@$public_ip" \
  'sudo -n bash -s' \
  < "$bootstrap_script"
