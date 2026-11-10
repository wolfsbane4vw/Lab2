#!/usr/bin/env bash
set -euo pipefail

node_name="${1:?Provide the node name}"
node_ip="${2:?Provide the node private IP}"
seed_ips="${3:?Provide comma-separated cluster private IPs}"

if [[ "$EUID" -ne 0 ]]; then
    echo "Run this script as root on a database node." >&2
    exit 1
fi

if systemctl is-active --quiet mariadb; then
    echo "MariaDB is already running. Refusing initial configuration." >&2
    exit 1
fi

cat > /etc/mysql/mariadb.conf.d/60-galera.cnf <<EOF
[mysqld]
bind-address=0.0.0.0

wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_name=lab2-galera
wsrep_cluster_address=gcomm://$seed_ips

wsrep_node_name=$node_name
wsrep_node_address=$node_ip

binlog_format=ROW
default_storage_engine=InnoDB
innodb_autoinc_lock_mode=2

wsrep_sst_method=rsync
EOF

echo "Galera configuration written for $node_name"
