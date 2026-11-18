#!/usr/bin/env bash
set -euo pipefail
trap 'exit 0' INT TERM

mode="${1:-}"
asg_name="${2:-lab2-database}"
alarm_name="${asg_name%-database}-simulated-load-high"

case "$mode" in
  high) value=100 ;;
  low)  value=0 ;;
  *)
    echo "Usage: bash scripts/simulate-load.sh high|low [asg-name]" >&2
    exit 1
    ;;
esac

aws_options=(
  --profile "${AWS_PROFILE:-taltech}"
  --region "${AWS_REGION:-${AWS_DEFAULT_REGION:-eu-north-1}}"
  --no-cli-pager
)

echo "Publishing $mode simulated load every 30 seconds."
echo "Press Ctrl+C to stop."

while true; do
  aws cloudwatch put-metric-data \
    "${aws_options[@]}" \
    --namespace Lab2 \
    --metric-name SimulatedLoad \
    --dimensions "AutoScalingGroupName=$asg_name" \
    --unit Percent \
    --value "$value"

  state="$(
    aws cloudwatch describe-alarms \
      "${aws_options[@]}" \
      --alarm-names "$alarm_name" \
      --query 'MetricAlarms[0].StateValue' \
      --output text
  )"

  if [[ "$state" == "None" ]]; then
    echo "Alarm not found: $alarm_name" >&2
    exit 1
  fi

  echo "Published $value; alarm state: $state"
  sleep 30
done
