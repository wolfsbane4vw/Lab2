#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
previous_ids=""

aws_options=(
  --profile "${AWS_PROFILE:-taltech}"
  --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-north-1}}"
  --no-cli-pager
)

echo "Watching $asg_name. Keep this laptop awake."
echo "AWS launches and terminates instances; this watcher joins fresh nodes."
echo "Press Ctrl+C to stop."

while true; do
  if ! nodes="$(discover_nodes "$asg_name")"; then
    echo "Discovery failed. Check your AWS login and restart the watcher." >&2
    exit 1
  fi

  require_nodes "$nodes" 3
  current_ids="$(jq -r '.[].instance_id' <<< "$nodes")"

  if [[ "$current_ids" != "$previous_ids" ]]; then
    if [[ -z "$previous_ids" ]]; then
      echo "Initial scan: checking the currently discovered members."
    else
      added_ids="$(
        comm -13 \
          <(printf '%s\n' "$previous_ids" | sort) \
          <(printf '%s\n' "$current_ids" | sort)
      )"

      removed_ids="$(
        comm -23 \
          <(printf '%s\n' "$previous_ids" | sort) \
          <(printf '%s\n' "$current_ids" | sort)
      )"

      if [[ -n "$added_ids" ]]; then
        printf 'New running instance(s) detected:\n%s\n' "$added_ids"
      fi

      if [[ -n "$removed_ids" ]]; then
        printf 'Instance(s) no longer discovered as running:\n%s\n' "$removed_ids"
      fi
    fi

    group="$(
      aws autoscaling describe-auto-scaling-groups \
        "${aws_options[@]}" \
        --auto-scaling-group-names "$asg_name" \
        --query 'AutoScalingGroups[0]' \
        --output json
    )"

    desired_size="$(jq -er '.DesiredCapacity' <<< "$group")"
    discovered_size="$(jq 'length' <<< "$nodes")"

    transitioning="$(
      jq '[.Instances[] |
           select(.LifecycleState != "InService")] | length' <<< "$group"
    )"

    echo "ASG snapshot: desired=$desired_size; discovered running=$discovered_size"

    jq -r '.Instances[] |
      select(.LifecycleState != "InService") |
      "AWS lifecycle: \(.InstanceId) — \(.LifecycleState)"' <<< "$group"

    echo "Checking existing members and joining fresh nodes..."

    if ! bash "$project_dir/scripts/nodes/cluster.sh" join "$asg_name"; then
      echo "Joining or verification failed. Stopping for inspection." >&2
      echo "Do not run init to recover the cluster." >&2
      exit 1
    fi

    previous_ids="$current_ids"

    if (( discovered_size != desired_size || transitioning > 0 )); then
      echo "Cluster checks passed; AWS membership is still transitioning."
      echo "Temporary overlap can include both an old node and its replacement."
    else
      echo "Cluster checks passed with membership matching desired capacity."
    fi

    echo "Continuing to watch."
  fi

  sleep 30
done
