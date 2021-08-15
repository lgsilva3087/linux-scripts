#!/usr/bin/env bash

# qemu-kvm
sudo apt-get install -y \
  bridge-utils \
  dnsmasq-base \
  iptables \
  libvirt-clients \
  libvirt-daemon \
  libvirt-daemon-system \
  qemu-kvm \
  virtinst \
  virt-manager
## Start default network and add vhost_net module
sudo virsh net-start default || true
sudo virsh net-autostart default || true
sudo modprobe vhost_net
echo "vhost_net" | sudo  tee -a /etc/modules
## Allow current user access to libvirt
sudo adduser $(id -un) libvirt
sudo adduser $(id -un) libvirt-qemu
## Create Linux Bridge(br0) for KVM VMs

