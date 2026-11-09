#!/usr/bin/env bash
# Generates a dedicated local SSH key. Makes no AWS calls.
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
key_path="$project_dir/terraform/database-key.pem"

if [[ -e "$key_path" || -e "$key_path.pub" ]]; then
  echo "A database key file already exists. Keeping it unchanged."
  exit 0
fi

ssh-keygen -t ed25519 -f "$key_path" -N '' -C 'lab2-database'
