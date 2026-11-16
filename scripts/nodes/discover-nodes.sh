#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

discover_nodes "${1:-lab2-database}"
