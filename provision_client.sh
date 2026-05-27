#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_IP="192.168.100.2"
SERVER_IP="192.168.100.3"

# ── 1. Install LXD ────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq snapd
snap install lxd --channel=5.0/stable
export PATH=$PATH:/snap/bin
sleep 5

# ── 2. Wait for join token from servidorUbuntu ────────────────────────────
echo "Waiting for join token from servidorUbuntu..."
TOKEN_FOUND=0
for i in $(seq 1 36); do
  if [ -s /vagrant/lxd_join_token.txt ]; then
    TOKEN_FOUND=1
    break
  fi
  echo "  attempt $i/36 — waiting 10s..."
  sleep 10
done

if [ "$TOKEN_FOUND" -eq 0 ]; then
  echo "ERROR: Token not found after 6 minutes. Is servidorUbuntu provisioning still running?"
  exit 1
fi

JOIN_TOKEN=$(cat /vagrant/lxd_join_token.txt)
echo "Token obtained: ${JOIN_TOKEN:0:20}..."

# ── 3. Join LXD cluster ───────────────────────────────────────────────────
lxd init --preseed <<EOF
config: {}
cluster:
  server_name: clienteUbuntu
  enabled: true
  member_config:
  - entity: storage-pool
    name: default
    key: source
    value: ""
  - entity: network
    name: lxdbr0
    key: bridge.external_interfaces
    value: ""
  cluster_address: ${SERVER_IP}:8443
  server_address: ${NODE_IP}:8443
  cluster_token: "${JOIN_TOKEN}"
EOF

# ── 4. Launch web2 (produccion) and web4 (backup) ────────────────────────
lxc launch ubuntu:18.04 web2 --target clienteUbuntu
lxc launch ubuntu:18.04 web4 --target clienteUbuntu

sleep 15

# Install Apache on web2
lxc exec web2 -- bash -c "apt-get update -qq && apt-get install -y apache2"
lxc file push /vagrant/web/web2/index.htm web2/var/www/html/index.html

# Install Apache on web4
lxc exec web4 -- bash -c "apt-get update -qq && apt-get install -y apache2"
lxc file push /vagrant/web/web4/index.htm web4/var/www/html/index.html

# ── 5. Expose web containers via proxy devices ────────────────────────────
lxc config device add web2 proxy80 proxy \
  listen=tcp:0.0.0.0:8082 connect=tcp:127.0.0.1:80 bind=host

lxc config device add web4 proxy80 proxy \
  listen=tcp:0.0.0.0:8084 connect=tcp:127.0.0.1:80 bind=host

echo ""
echo "=== clienteUbuntu provisioning complete ==="
lxc list
