#!/usr/bin/env bash
# Shared laptop-side helpers. Callers enable set -euo pipefail.
project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"
ssh_options=(
  -i "$key_path"
  -o BatchMode=yes
  -o ConnectTimeout=10
  -o StrictHostKeyChecking=accept-new
)

discover_nodes() {
  local asg_name="${1:-lab2-database}"
  aws ec2 describe-instances \
    --profile "${AWS_PROFILE:-taltech}" \
    --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-north-1}}" \
    --filters \
      "Name=tag:aws:autoscaling:groupName,Values=$asg_name" \
      "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{instance_id:InstanceId,private_ip:PrivateIpAddress,public_ip:PublicIpAddress}' \
    --output json --no-cli-pager |
    jq -e '
      if type == "array" and all(.[];
        (.instance_id | type == "string" and length > 0) and
        (.private_ip | type == "string" and length > 0) and
        (.public_ip | type == "string" and length > 0)
      ) then sort_by(.instance_id)
      else error("Discovery requires instance IDs and private/public IPs")
      end'
}

require_nodes() {
  local nodes="$1"
  local minimum="${2:-1}"
  if ! jq -e --argjson minimum "$minimum" 'length >= $minimum' <<< "$nodes" > /dev/null; then
    echo "Expected at least $minimum running ASG nodes." >&2
    return 1
  fi
}

# Commands must not consume the caller's loop input.
ssh_node() {
  local ip="$1"
  shift
  ssh -n "${ssh_options[@]}" "ubuntu@$ip" "$@"
}

# Remote scripts intentionally arrive through stdin, so no SSH -n here.
ssh_script() {
  local ip="$1"
  shift
  ssh "${ssh_options[@]}" "ubuntu@$ip" 'sudo -n bash -s --' "$@"
}

# SQL is constructed internally by the callers, not accepted from external input.
ssh_sql() {
  local ip="$1"
  local sql="$2"
  ssh_node "$ip" "sudo -n timeout 15 mariadb --batch --skip-column-names --execute=\"$sql\""
}
