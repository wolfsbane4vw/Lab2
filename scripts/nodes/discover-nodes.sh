#!/usr/bin/env bash
set -euo pipefail

asg_name="${1:-lab2-database}"

aws ec2 describe-instances \
    --profile "${AWS_PROFILE:-taltech}" \
    --region eu-north-1 \
    --filters \
        "Name=tag:aws:autoscaling:groupName,Values=$asg_name" \
        "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].{
        instance_id:InstanceId,
        private_ip:PrivateIpAddress,
        public_ip:PublicIpAddress
    }' \
    --output json \
    --no-cli-pager
