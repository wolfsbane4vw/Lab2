#!/usr/bin/env bash
# Authenticate first using the same AWS account/profile as Lab1, for example:
# export AWS_PROFILE=taltech
# aws sso login --profile taltech
# Set Lab1's AMI ID and region in terraform/terraform.tfvars before planning.
# Also set ssh_cidr and run bash scripts/create-test-key.sh once.
# This script saves a plan; it does not apply it.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

terraform -chdir="$project_dir/terraform" init -input=false
terraform -chdir="$project_dir/terraform" validate
terraform -chdir="$project_dir/terraform" plan -input=false -out=tfplan "$@"

