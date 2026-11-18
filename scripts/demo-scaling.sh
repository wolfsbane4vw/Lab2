#!/usr/bin/env bash
set -euo pipefail
# Keep the prompted database password out of shell tracing.
set +x

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
asg_name="${1:-lab2-database}"
alarm_name="${asg_name%-database}-simulated-load-high"
load_pid=""

aws_options=(
  --profile "${AWS_PROFILE:-taltech}"
  --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-north-1}}"
  --no-cli-pager
)

stop_load() {
  if [[ -n "$load_pid" ]]; then
    kill -TERM "$load_pid" 2>/dev/null || true
    wait "$load_pid" 2>/dev/null || true
    load_pid=""
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  stop_load
  unset db_password
  if (( status != 0 )); then
    echo "Demo stopped. Inspect the cluster before retrying; no recovery was attempted." >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

start_load() {
  stop_load
  bash "$project_dir/scripts/simulate-load.sh" "$1" "$asg_name" &
  load_pid=$!
}

check_publisher() {
  if ! kill -0 "$load_pid" 2>/dev/null; then
    echo "Load publisher stopped unexpectedly." >&2
    return 1
  fi
}

read_group() {
  aws autoscaling describe-auto-scaling-groups \
    "${aws_options[@]}" \
    --auto-scaling-group-names "$asg_name" \
    --query 'AutoScalingGroups[0]' --output json
}

wait_for_capacity() {
  local expected="$1" attempt group
  echo "Waiting for $expected healthy, InService ASG instances..."
  for attempt in {1..60}; do
    check_publisher
    group="$(read_group)"
    if jq -e --argjson expected "$expected" '
      .DesiredCapacity == $expected and
      (.Instances | length) == $expected and
      all(.Instances[];
          .LifecycleState == "InService" and .HealthStatus == "Healthy")
    ' <<< "$group" > /dev/null; then
      return 0
    fi
    sleep 10
  done
  echo "Timed out waiting for ASG capacity $expected." >&2
  return 1
}

wait_for_low_alarm() {
  local attempt state
  echo "Waiting for low load to clear the alarm..."
  for attempt in {1..60}; do
    check_publisher
    state="$(aws cloudwatch describe-alarms \
      "${aws_options[@]}" --alarm-names "$alarm_name" \
      --query 'MetricAlarms[0].StateValue' --output text)"
    if [[ "$state" == "OK" ]]; then
      return 0
    fi
    if [[ "$state" == "None" ]]; then
      echo "Alarm not found: $alarm_name" >&2
      return 1
    fi
    sleep 10
  done
  echo "Timed out waiting for the alarm to return to OK." >&2
  return 1
}

wait_for_cluster() {
  local expected="$1" deadline=$((SECONDS + 120))
  echo "Waiting for all $expected Galera members to agree before scale-in..."
  while true; do
    check_publisher
    if bash "$project_dir/scripts/nodes/check-nodes.sh" cluster "$expected" "$asg_name"; then
      return 0
    fi
    if (( SECONDS >= deadline )); then
      echo "Galera membership did not stabilize within the retry window. Refusing scale-in." >&2
      return 1
    fi
    echo "Cluster checks have not passed yet; retrying in 10 seconds..."
    sleep 10
  done
}

return_to_three() {
  local group size
  group="$(read_group)"
  size="$(jq -er '.DesiredCapacity' <<< "$group")"
  case "$size" in
    3|4|5) ;;
    *) echo "Expected capacity between three and five." >&2; return 1 ;;
  esac

  wait_for_capacity "$size"
  while (( size > 3 )); do
    wait_for_cluster "$size"
    bash "$project_dir/scripts/nodes/scale-in.sh" "$asg_name"
    size=$((size - 1))
    wait_for_capacity "$size"
  done
}

verify_cluster() {
  bash "$project_dir/scripts/nodes/check-nodes.sh" cluster "$1" "$asg_name"
  bash "$project_dir/scripts/nodes/test-replication.sh" "$asg_name"
  printf '%s\n' "$db_password" |
    bash "$project_dir/scripts/nodes/test-load-balancer.sh" --password-stdin
}

echo "Demo: three -> five -> three nodes. Stop any separate watcher or publisher first."
group="$(read_group)"
if ! jq -e '
  .DesiredCapacity == 3 and
  (.Instances | length) == 3 and
  all(.Instances[];
      .LifecycleState == "InService" and .HealthStatus == "Healthy")
' <<< "$group" > /dev/null; then
  echo "Start this demo with three healthy, InService ASG instances." >&2
  echo "If capacity is higher, use controlled scale-in after clearing high load." >&2
  exit 1
fi

if ! IFS= read -r -s -p "Password for lab2_client (used for both NLB tests): " db_password; then
  printf '\n' >&2
  echo "Could not read the database password." >&2
  exit 1
fi
printf '\n'
if [[ -z "$db_password" ]]; then
  echo "The database password cannot be empty." >&2
  exit 1
fi

bash "$project_dir/scripts/nodes/check-nodes.sh" cluster 3 "$asg_name"

echo "Clearing any previous high-load condition..."
start_load low
wait_for_low_alarm
stop_load

echo "HIGH LOAD: CloudWatch will request five instances."
start_load high
wait_for_capacity 5
bash "$project_dir/scripts/nodes/cluster.sh" join "$asg_name"
verify_cluster 5

echo "LOW LOAD: draining and removing nodes safely until three remain."
start_load low
wait_for_low_alarm
return_to_three
verify_cluster 3
stop_load

echo "Demo passed: high load -> five nodes; low load -> three nodes."
