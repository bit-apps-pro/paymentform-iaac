#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Installing Valkey on AL2023..."

dnf install -y valkey

mkdir -p /etc/valkey

%{ if cluster_mode }
# ── Cluster mode (node_count >= 3) ──────────────────────────────────────────
# Cluster formation (CLUSTER CREATE) is handled externally via SSM Run Command
# after all nodes are up. This script just starts the node with cluster-enabled.
ANNOUNCE_IP=$(hostname -I | awk '{print $1}')

cat > /etc/valkey/valkey.conf <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
requirepass ${cluster_password}
masterauth ${cluster_password}
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
supervised systemd
pidfile /var/run/valkey/valkey.pid
loglevel notice
logfile ""
databases 16
always-show-logo no

maxmemory 2.5gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

cluster-enabled yes
cluster-config-file /etc/valkey/nodes.conf
cluster-node-timeout 5000
cluster-announce-ip $ANNOUNCE_IP
cluster-announce-port 6379
cluster-announce-bus-port 16379

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
save ""
EOF

%{ else }
# ── Standalone mode (node_count = 1) ────────────────────────────────────────
# No cluster-enabled. Single node, all 16384 hash slots are served locally.
cat > /etc/valkey/valkey.conf <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
requirepass ${cluster_password}
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
supervised systemd
pidfile /var/run/valkey/valkey.pid
loglevel notice
logfile ""
databases 16
always-show-logo no

maxmemory 2.5gb
maxmemory-policy allkeys-lru
lazyfree-lazy-eviction yes
lazyfree-lazy-expire yes
lazyfree-lazy-server-del yes
replica-lazy-flush yes

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
save ""
EOF

%{ endif }

mkdir -p /var/run/valkey
chown -R valkey:valkey /var/lib/valkey
chown -R valkey:valkey /etc/valkey

systemctl enable valkey
systemctl start valkey

log "Valkey node ${node_index} setup complete (cluster_mode=${cluster_mode})"
