#!/usr/bin/env bash
# Run from any directory. No AWS credentials are needed for validation.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

terraform -chdir="$project_dir/terraform" fmt -check -recursive
terraform -chdir="$project_dir/terraform" init -backend=false -input=false
terraform -chdir="$project_dir/terraform" validate

