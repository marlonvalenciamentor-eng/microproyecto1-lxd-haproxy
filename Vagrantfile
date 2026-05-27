# -*- mode: ruby -*-
# vi: set ft=ruby :
Vagrant.configure("2") do |config|
  if Vagrant.has_plugin? "vagrant-vbguest"
    config.vbguest.no_install  = true
    config.vbguest.auto_update = false
    config.vbguest.no_remote   = true
  end

  # ── servidorUbuntu — LXD node 1 (haproxy + web1 + web3-backup) ───────────
  # Defined first so Vagrant provisions it before clienteUbuntu
  config.vm.define :servidorUbuntu do |s|
    s.vm.box      = "bento/ubuntu-20.04"
    s.vm.hostname = "servidorUbuntu"
    s.vm.network :private_network, ip: "192.168.100.3"
    # HAProxy frontend
    s.vm.network "forwarded_port", guest: 80,   host: 8080
    # HAProxy stats GUI
    s.vm.network "forwarded_port", guest: 8404, host: 8404
    # Direct access to each web container (optional / debug)
    s.vm.network "forwarded_port", guest: 8081, host: 8081
    s.vm.network "forwarded_port", guest: 8083, host: 8083
    s.vm.provider "virtualbox" do |vb|
      vb.memory = "2048"
      vb.cpus   = 2
    end
    s.vm.provision "shell", path: "provision_server.sh"
  end

  # ── clienteUbuntu — LXD node 2 (web2 + web4-backup) ──────────────────────
  config.vm.define :clienteUbuntu do |c|
    c.vm.box      = "bento/ubuntu-20.04"
    c.vm.hostname = "clienteUbuntu"
    c.vm.network :private_network, ip: "192.168.100.2"
    c.vm.provider "virtualbox" do |vb|
      vb.memory = "1536"
      vb.cpus   = 2
    end
    c.vm.provision "shell", path: "provision_client.sh"
  end
end
