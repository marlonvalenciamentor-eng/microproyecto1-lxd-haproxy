#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
exec 0</dev/null   # prevent stdin from vagrant SSH channel interfering with lxc commands

NODE_IP="192.168.100.3"

# ── 1. Install / refresh LXD ─────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq snapd
export PATH=$PATH:/snap/bin

# ── 2. Initialize LXD cluster (bootstrap node) ───────────────────────────
# If cluster is already healthy, skip everything.
# Otherwise purge existing LXD state and do a clean init.
if lxc cluster list 2>/dev/null | grep -q "servidorUbuntu.*ONLINE"; then
  echo "LXD cluster already healthy — skipping init"
else
  echo "Purging existing LXD state and reinstalling for clean bootstrap..."
  lxd shutdown 2>/dev/null || true
  sleep 3
  snap remove lxd --purge 2>/dev/null || true
  snap install lxd --channel=5.0/stable
  sleep 15
  export PATH=$PATH:/snap/bin
  lxd waitready --timeout=60

  lxd init --preseed <<EOF
config:
  core.https_address: ${NODE_IP}:8443
networks:
- config:
    ipv4.address: 10.10.10.1/24
    ipv4.nat: "true"
    ipv6.address: none
  description: ""
  name: lxdbr0
  type: bridge
storage_pools:
- config: {}
  driver: dir
  name: default
profiles:
- config: {}
  description: ""
  devices:
    eth0:
      name: eth0
      network: lxdbr0
      type: nic
    root:
      path: /
      pool: default
      type: disk
  name: default
cluster:
  server_name: servidorUbuntu
  enabled: true
  member_config: []
  cluster_address: ""
  cluster_certificate: ""
  server_address: ${NODE_IP}:8443
  cluster_token: ""
EOF
fi

# ── 3. Generate join token for clienteUbuntu ─────────────────────────────
# Always regenerate — tokens expire
echo "Generating fresh join token for clienteUbuntu..."
lxc cluster add clienteUbuntu --quiet 2>/dev/null | tail -1 > /vagrant/lxd_join_token.txt
echo "Join token saved (first 20 chars): $(head -c 20 /vagrant/lxd_join_token.txt)..."

# ── 4. Launch web1 and web3 containers (idempotent) ──────────────────────
lxc info web1 2>/dev/null | grep -q "Status" || lxc launch ubuntu:18.04 web1 --target servidorUbuntu
lxc info web3 2>/dev/null | grep -q "Status" || lxc launch ubuntu:18.04 web3 --target servidorUbuntu
sleep 15

# ── 5. Install Apache on web1 and web3 ───────────────────────────────────
lxc exec web1 -- bash -c "apt-get update -qq && apt-get install -y apache2" || true
lxc file push /vagrant/web/web1/index.htm web1/var/www/html/index.html

lxc exec web3 -- bash -c "apt-get update -qq && apt-get install -y apache2" || true
lxc file push /vagrant/web/web3/index.htm web3/var/www/html/index.html

# ── 6. Proxy devices for web containers (idempotent) ─────────────────────
lxc config device list web1 2>/dev/null | grep -q proxy80 || \
  lxc config device add web1 proxy80 proxy \
    listen=tcp:0.0.0.0:8081 connect=tcp:127.0.0.1:80 bind=host

lxc config device list web3 2>/dev/null | grep -q proxy80 || \
  lxc config device add web3 proxy80 proxy \
    listen=tcp:0.0.0.0:8083 connect=tcp:127.0.0.1:80 bind=host

# ── 7. Launch haproxy container (idempotent) ─────────────────────────────
lxc info haproxy 2>/dev/null | grep -q "Status" || { lxc launch ubuntu:18.04 haproxy --target servidorUbuntu; sleep 10; }

lxc exec haproxy -- bash -c "apt-get update -qq && apt-get install -y haproxy" || true

lxc file push /vagrant/haproxy/haproxy.cfg  haproxy/etc/haproxy/haproxy.cfg
lxc exec haproxy -- mkdir -p /etc/haproxy/errors
lxc file push /vagrant/haproxy/errors/503.http haproxy/etc/haproxy/errors/503.http

lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable  haproxy

# ── 8. Expose HAProxy ports (idempotent) ─────────────────────────────────
lxc config device list haproxy 2>/dev/null | grep -q proxy80 || \
  lxc config device add haproxy proxy80   proxy \
    listen=tcp:0.0.0.0:80   connect=tcp:127.0.0.1:80  bind=host

lxc config device list haproxy 2>/dev/null | grep -q proxy8404 || \
  lxc config device add haproxy proxy8404 proxy \
    listen=tcp:0.0.0.0:8404 connect=tcp:127.0.0.1:8404 bind=host

echo ""
echo "=== servidorUbuntu provisioning complete ==="
lxc list
