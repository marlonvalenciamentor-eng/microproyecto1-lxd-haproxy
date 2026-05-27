#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
exec 0</dev/null   # prevent stdin from vagrant SSH channel interfering with lxc commands

NODE_IP="192.168.100.2"
SERVER_IP="192.168.100.3"

# ── 1. Install LXD ────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq snapd
export PATH=$PATH:/snap/bin

if ! snap list lxd 2>/dev/null | grep -q lxd; then
  snap install lxd --channel=5.0/stable
else
  snap refresh lxd --channel=5.0/stable 2>/dev/null || true
fi

lxd waitready --timeout=60

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

# ── 3. Join LXD cluster (idempotent) ─────────────────────────────────────
if lxc cluster list 2>/dev/null | grep -q "clienteUbuntu"; then
  echo "Already a member of LXD cluster as clienteUbuntu, skipping join"
else
  echo "Joining LXD cluster..."
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
fi

# ── 4. Launch web2 and web4 containers (idempotent) ──────────────────────
if ! lxc info web2 2>/dev/null | grep -q "Status"; then
  lxc launch ubuntu:18.04 web2 --target clienteUbuntu
fi
if ! lxc info web4 2>/dev/null | grep -q "Status"; then
  lxc launch ubuntu:18.04 web4 --target clienteUbuntu
fi

sleep 15

# ── 5. Install Apache on web2 and web4 ───────────────────────────────────
lxc exec web2 -- bash -c "apt-get update -qq && apt-get install -y apache2" || true
lxc file push /vagrant/web/web2/index.htm web2/var/www/html/index.html

lxc exec web4 -- bash -c "apt-get update -qq && apt-get install -y apache2" || true
lxc file push /vagrant/web/web4/index.htm web4/var/www/html/index.html

# ── 6. Proxy devices (idempotent) ─────────────────────────────────────────
lxc config device list web2 2>/dev/null | grep -q proxy80 || \
  lxc config device add web2 proxy80 proxy \
    listen=tcp:0.0.0.0:8082 connect=tcp:127.0.0.1:80 bind=host

lxc config device list web4 2>/dev/null | grep -q proxy80 || \
  lxc config device add web4 proxy80 proxy \
    listen=tcp:0.0.0.0:8084 connect=tcp:127.0.0.1:80 bind=host

echo ""
echo "=== clienteUbuntu provisioning complete ==="
lxc list
