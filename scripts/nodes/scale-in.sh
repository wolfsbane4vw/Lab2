#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
aws_options=(
  --profile "${AWS_PROFILE:-taltech}"
  --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-north-1}}"
  --no-cli-pager
)

drain_candidate() {
  local target_group_arn
  local health

  target_group_arn="$(
    jq -er '
      .AutoScalingGroups[0].TargetGroupARNs |
      if length == 1 then .[0]
      else error("Expected exactly one ASG target group")
      end
    ' <<< "$group"
  )"

  health="$(
    aws elbv2 describe-target-health \
      "${aws_options[@]}" \
      --target-group-arn "$target_group_arn" \
      --output json
  )"

  # Require all current ASG members to be healthy NLB targets.
  if ! jq -e --argjson group "$group" '
    .TargetHealthDescriptions |
    (map(.Target.Id) | sort) ==
      ($group.AutoScalingGroups[0].Instances |
       map(.InstanceId) | sort)
    and all(.[]; .TargetHealth.State == "healthy"
                 and .Target.Port == 3306)
  ' <<< "$health" > /dev/null; then
    echo "NLB targets do not match the healthy ASG members." >&2
    return 1
  fi

  echo "Draining NLB connections from $candidate_id..."

  aws elbv2 deregister-targets \
    "${aws_options[@]}" \
    --target-group-arn "$target_group_arn" \
    --targets "Id=$candidate_id,Port=3306"

  if ! aws elbv2 wait target-deregistered \
    "${aws_options[@]}" \
    --target-group-arn "$target_group_arn" \
    --targets "Id=$candidate_id,Port=3306"; then
    echo "Could not confirm draining completed. Stopping." >&2
    echo "The target may remain deregistered; inspect before continuing." >&2
    return 1
  fi

  echo "NLB draining completed for $candidate_id."
}

stop_candidate() {
  local nodes
  local candidate_ip
  local attempt
  local remaining_size=$((current_size - 1))

  nodes="$(discover_nodes "$asg_name")"

  candidate_ip="$(
    jq -er --arg id "$candidate_id" '
      .[] | select(.instance_id == $id) | .public_ip
    ' <<< "$nodes"
  )"

  # Recheck all members after draining, before stopping the database.
  bash "$project_dir/scripts/nodes/check-nodes.sh" \
    cluster "$current_size" "$asg_name"

  echo "Stopping MariaDB on $candidate_id..."

  ssh_node "$candidate_ip" \
    sudo -n timeout 180 systemctl stop mariadb

  # Membership changes can take a little time to propagate.
  for attempt in {1..15}; do
    if bash "$project_dir/scripts/nodes/check-nodes.sh" \
      cluster "$remaining_size" "$asg_name" "$candidate_id"; then
      echo "Remaining $remaining_size members are healthy."
      return 0
    fi

    sleep 2
  done

  echo "Survivor verification failed. No instance will be terminated." >&2
  echo "The candidate's database is stopped; inspect before continuing." >&2
  return 1
}

terminate_candidate() {
  local latest_group
  local remaining_size=$((current_size - 1))

  # Refuse termination if ASG membership changed during draining.
  latest_group="$(
    aws autoscaling describe-auto-scaling-groups \
      "${aws_options[@]}" \
      --auto-scaling-group-names "$asg_name" \
      --output json
  )"

  if ! jq -e --argjson original "$group" \
    --argjson size "$current_size" '
      .AutoScalingGroups[0] as $latest |
      $latest.DesiredCapacity == $size and
      ($latest.Instances | map(.InstanceId) | sort) ==
        ($original.AutoScalingGroups[0].Instances |
         map(.InstanceId) | sort) and
      all($latest.Instances[];
          .LifecycleState == "InService"
          and .HealthStatus == "Healthy")
    ' <<< "$latest_group" > /dev/null; then
    echo "ASG changed during scale-in. Refusing termination." >&2
    echo "The candidate's database is stopped; inspect before continuing." >&2
    return 1
  fi

  echo "Terminating $candidate_id and reducing capacity to $remaining_size..."

  aws autoscaling terminate-instance-in-auto-scaling-group \
    "${aws_options[@]}" \
    --instance-id "$candidate_id" \
    --should-decrement-desired-capacity \
    --output json

  aws ec2 wait instance-terminated \
    "${aws_options[@]}" \
    --instance-ids "$candidate_id"

  bash "$project_dir/scripts/nodes/check-nodes.sh" \
    cluster "$remaining_size" "$asg_name"

  echo "Scale-in completed: $remaining_size healthy members remain."
}

group="$(
  aws autoscaling describe-auto-scaling-groups \
    "${aws_options[@]}" \
    --auto-scaling-group-names "$asg_name" \
    --output json
)"

current_size="$(
  jq -er '.AutoScalingGroups[0].DesiredCapacity //
          error("ASG not found")' <<< "$group"
)"

if (( current_size == 3 )); then
  echo "Already at three instances. Nothing to remove."
  exit 0
fi

if (( current_size < 3 )); then
  echo "Refusing scale-in below three instances." >&2
  exit 1
fi

# Do not scale in while instances are launching or terminating.
if ! jq -e --argjson size "$current_size" '
  .AutoScalingGroups[0].Instances |
  length == $size and
  all(.[]; .LifecycleState == "InService"
           and .HealthStatus == "Healthy")
' <<< "$group" > /dev/null; then
  echo "ASG membership is not stable and healthy. Try again later." >&2
  exit 1
fi

bash "$project_dir/scripts/nodes/check-nodes.sh" \
  cluster "$current_size" "$asg_name"

# Choose from the most populated AZ, preserving its remaining member.
candidate_id="$(
  jq -er '
    .AutoScalingGroups[0].Instances |
    group_by(.AvailabilityZone) |
    sort_by(length) |
    last |
    if length > 1 then
      sort_by(.InstanceId) | last | .InstanceId
    else
      error("No Availability Zone has a spare instance")
    end
  ' <<< "$group"
)"

echo "Cluster checks passed."
echo "Selected scale-in candidate: $candidate_id"
drain_candidate
stop_candidate
terminate_candidate
