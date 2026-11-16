#!/usr/bin/env bash

set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"
configure_script="$project_dir/scripts/provisioning/configure-node.sh"

asg_name="${1:-lab2-database}"

nodes="$(bash "$project_dir/scripts/nodes/discover-nodes.sh" "$asg_name")"

if ! jq -e '
    length >= 3 and
    all(.[];
        .instance_id != null and
        .private_ip != null and
        .public_ip != null
    )
' <<< "$nodes" > /dev/null; then
    echo "Expected at least three nodes with IDs and both IP addresses." >&2
    exit 1
fi

seed_ips="$(jq -r 'map(.private_ip) | join(",")' <<< "$nodes")"

node_rows="$(
  jq -r '.[] | [.instance_id, .private_ip, .public_ip] | @tsv' <<< "$nodes"
)"

while IFS=$'\t' read -r node_id private_ip public_ip; do
  echo "Configuring $node_id at $public_ip"

  ssh \
    -i "$key_path" \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    -o StrictHostKeyChecking=accept-new \
    "ubuntu@$public_ip" \
    sudo -n bash -s -- "$node_id" "$private_ip" "$seed_ips" \
    < "$configure_script"
done <<< "$node_rows"

echo "Configuration written to all discovered nodes."
