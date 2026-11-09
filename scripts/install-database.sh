#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y \
    mariadb-server \
    mariadb-backup \
    galera-4 \
    rsync

systemctl disable --now mariadb
