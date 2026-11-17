#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
previous_ids=""

echo "Watching $asg_name. Keep this laptop awake."
echo "Press Ctrl+C to stop."

while true; do
  if ! nodes="$(discover_nodes "$asg_name")"; then
    echo "Discovery failed. Check your AWS login and restart the watcher." >&2
    exit 1
  fi

  require_nodes "$nodes" 3
  current_ids="$(jq -r '.[].instance_id' <<< "$nodes")"

  if [[ "$current_ids" != "$previous_ids" ]]; then
    echo "Checking ASG membership and joining fresh nodes..."

    if ! bash "$project_dir/scripts/nodes/cluster.sh" join "$asg_name"; then
      echo "Joining or verification failed. Stopping for inspection." >&2
      echo "Do not run init to recover the cluster." >&2
      exit 1
    fi

    previous_ids="$current_ids"
    echo "Cluster verified. Continuing to watch."
  fi

  sleep 30
done
