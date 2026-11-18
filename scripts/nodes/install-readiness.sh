#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../lib/nodes.sh"

asg_name="${1:-lab2-database}"
nodes="$(discover_nodes "$asg_name")"
require_nodes "$nodes" 3

script_data="$(
  base64 < "$project_dir/scripts/server/galera_readiness.py" |
    tr -d '\n'
)"

service_data="$(
  base64 < "$project_dir/terraform/templates/galera-readiness.service" |
    tr -d '\n'
)"

node_ips="$(jq -r '.[].public_ip' <<< "$nodes")"

while IFS= read -r ip; do
  echo "Installing readiness service on $ip..."
  wait_for_ssh "$ip"
  wait_for_installation "$ip"

  ssh_script "$ip" "$script_data" "$service_data" <<'REMOTE'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l

if ! command -v python3 >/dev/null 2>&1; then
  apt-get -o DPkg::Lock::Timeout=300 install -y python3
fi

install -d -m 0755 /opt/lab2
printf '%s' "$1" | base64 --decode > /opt/lab2/galera_readiness.py
printf '%s' "$2" | base64 --decode \
  > /etc/systemd/system/galera-readiness.service

chmod 0644 \
  /opt/lab2/galera_readiness.py \
  /etc/systemd/system/galera-readiness.service

systemctl daemon-reload
systemctl enable galera-readiness.service
systemctl restart galera-readiness.service

for attempt in {1..30}; do
  if python3 -c '
import urllib.request
with urllib.request.urlopen(
    "http://127.0.0.1:9200/ready", timeout=5
) as response:
    print(response.read().decode(), end="")
' 2>/dev/null; then
    exit 0
  fi

  sleep 2
done

echo "Readiness endpoint did not become healthy." >&2
journalctl -u galera-readiness.service -n 20 --no-pager
exit 1
REMOTE
done <<< "$node_ips"
