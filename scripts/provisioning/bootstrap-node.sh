#!/usr/bin/env bash
set -euo pipefail

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root on the first database node." >&2
    exit 1
fi

if [[ ! -f /etc/mysql/mariadb.conf.d/60-galera.cnf ]]; then
  echo "Galera configuration is missing." >&2
  exit 1
fi

if systemctl is-active --quiet mariadb; then
  echo "MariaDB is already running. Refusing bootstrap." >&2
  exit 1
fi

if [[ -e /var/lib/mysql/grastate.dat ||
      -e /var/lib/mysql/gvwstate.dat ]]; then
  echo "Previous Galera state exists. Use a recovery procedure instead." >&2
  exit 1
fi

echo "Bootstrapping a new Galera cluster..."
galera_new_cluster

mariadb --execute="
  SHOW GLOBAL STATUS
  WHERE Variable_name IN (
    'wsrep_cluster_size',
    'wsrep_cluster_status',
    'wsrep_local_state_comment',
    'wsrep_ready'
  );
"