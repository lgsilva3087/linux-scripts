#!/usr/bin/env bash

sudo apt-get install -y \
  docker.io \
  docker-compose
sudo groupadd docker || true
sudo usermod -aG docker $(id -un)
sudo systemctl enable docker.service
if [ ! -f "/etc/docker/daemon.json" ]; then
  sudo tee /etc/docker/daemon.json <<EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF
fi
