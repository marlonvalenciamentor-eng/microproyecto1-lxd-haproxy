#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_IP="192.168.100.3"
CLIENT_IP="192.168.100.2"

# ── 1. Install LXD ────────────────────────────────────────────────────────
apt-get update -qq
apt-get install -y -qq snapd
snap install lxd --channel=5.0/stable
export PATH=$PATH:/snap/bin
sleep 5

# ── 2. Initialize LXD cluster (bootstrap node) ───────────────────────────
lxd init --preseed <<EOF
config: {}
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
  cluster_address: ${NODE_IP}:8443
  cluster_certificate: ""
  server_address: ${NODE_IP}:8443
  cluster_token: ""
EOF

# ── 3. Generate join token for clienteUbuntu and save to shared folder ────
lxc cluster add clienteUbuntu --quiet 2>/dev/null | tail -1 > /vagrant/lxd_join_token.txt
echo "Join token saved to /vagrant/lxd_join_token.txt"

# ── 4. Launch web1 (produccion) and web3 (backup) ────────────────────────
lxc launch ubuntu:18.04 web1 --target servidorUbuntu
lxc launch ubuntu:18.04 web3 --target servidorUbuntu

# Wait for containers to get an IP
sleep 15

# Install Apache on web1
lxc exec web1 -- bash -c "apt-get update -qq && apt-get install -y apache2"
lxc file push /vagrant/web/web1/index.htm web1/var/www/html/index.html

# Install Apache on web3
lxc exec web3 -- bash -c "apt-get update -qq && apt-get install -y apache2"
lxc file push /vagrant/web/web3/index.htm web3/var/www/html/index.html

# ── 5. Expose web containers via proxy devices ────────────────────────────
lxc config device add web1 proxy80 proxy \
  listen=tcp:0.0.0.0:8081 connect=tcp:127.0.0.1:80 bind=host

lxc config device add web3 proxy80 proxy \
  listen=tcp:0.0.0.0:8083 connect=tcp:127.0.0.1:80 bind=host

# ── 6. Launch haproxy container ───────────────────────────────────────────
lxc launch ubuntu:18.04 haproxy --target servidorUbuntu
sleep 10

lxc exec haproxy -- bash -c "apt-get update -qq && apt-get install -y haproxy"

# Push config and error page
lxc file push /vagrant/haproxy/haproxy.cfg  haproxy/etc/haproxy/haproxy.cfg
lxc exec haproxy -- mkdir -p /etc/haproxy/errors
lxc file push /vagrant/haproxy/errors/503.http haproxy/etc/haproxy/errors/503.http

lxc exec haproxy -- systemctl restart haproxy
lxc exec haproxy -- systemctl enable  haproxy

# ── 7. Expose HAProxy frontend and stats ─────────────────────────────────
lxc config device add haproxy proxy80   proxy \
  listen=tcp:0.0.0.0:80   connect=tcp:127.0.0.1:80  bind=host
lxc config device add haproxy proxy8404 proxy \
  listen=tcp:0.0.0.0:8404 connect=tcp:127.0.0.1:8404 bind=host

echo ""
echo "=== servidorUbuntu provisioning complete ==="
lxc list
