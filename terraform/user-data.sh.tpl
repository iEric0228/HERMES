#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/hermes-setup.log) 2>&1

echo "=== Hermes VPS bootstrap ==="

# Wait for the data EBS volume to appear.
# Nitro/Graviton instances expose EBS as NVMe — discover the real device name.
echo "Waiting for data volume..."
DATA_DEVICE=""
for i in $(seq 1 60); do
  for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$dev" ]; then DATA_DEVICE="$dev"; break 2; fi
  done
  sleep 2
done
if [ -z "$DATA_DEVICE" ]; then
  echo "ERROR: data volume never appeared"
  exit 1
fi
echo "Found data volume at $DATA_DEVICE"

# Format only if unformatted
if ! blkid "$DATA_DEVICE" | grep -q ext4; then
  mkfs.ext4 -L hermes-data "$DATA_DEVICE"
fi

# Mount data volume
mkdir -p /data
mount "$DATA_DEVICE" /data
echo "LABEL=hermes-data /data ext4 defaults,nofail 0 2" >> /etc/fstab

# Create Hermes data directory
mkdir -p /data/hermes
chown 1000:1000 /data/hermes

# System updates
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

# Install Docker
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Enable swap (t3.small has only 2GB RAM)
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# Install useful tools
apt-get install -y awscli jq htop unzip rsync

# Set up automatic security updates
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# Create hermes deployment directory
mkdir -p /opt/hermes
chown ubuntu:ubuntu /opt/hermes

echo "=== Bootstrap complete ==="
