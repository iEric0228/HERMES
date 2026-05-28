#!/bin/bash
set -euo pipefail
exec > >(tee /var/log/hermes-setup.log) 2>&1

echo "=== Hermes VPS bootstrap ==="

# Nitro/Graviton instances expose EBS as NVMe, not xvdf.
# Discover the real device name by probing known paths.
echo "Waiting for data volume..."
DATA_DEVICE=""
for i in $(seq 1 60); do
  for dev in /dev/nvme1n1 /dev/xvdf /dev/sdf; do
    if [ -b "$dev" ]; then DATA_DEVICE="$dev"; break 2; fi
  done
  sleep 2
done
if [ -z "$DATA_DEVICE" ]; then
  echo "ERROR: data volume never appeared after 120s"
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
grep -q hermes-data /etc/fstab || \
  echo "LABEL=hermes-data /data ext4 defaults,nofail 0 2" >> /etc/fstab

# Create data directories owned by the container's default hermes user (UID 10000)
mkdir -p /data/hermes /data/documents
chown -R 10000:10000 /data/hermes /data/documents

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

# 4GB swap as safety net
fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q swapfile /etc/fstab || \
  echo "/swapfile swap swap defaults 0 0" >> /etc/fstab

# Useful tools
apt-get install -y awscli jq htop unzip rsync

# Automatic security updates
apt-get install -y unattended-upgrades
dpkg-reconfigure -f noninteractive unattended-upgrades

# Deployment directory
mkdir -p /opt/hermes/scripts
chown -R ubuntu:ubuntu /opt/hermes

# Write config for backup and monitoring scripts
cat > /opt/hermes/backup.conf <<CONF
BACKUP_BUCKET=${backup_bucket}
SNS_TOPIC_ARN=${sns_topic_arn}
AWS_DEFAULT_REGION=${aws_region}
CONF
chown ubuntu:ubuntu /opt/hermes/backup.conf

# Log rotation for Hermes (prevents data volume from filling up)
cat > /etc/logrotate.d/hermes <<'LOGROTATE'
/data/hermes/logs/*.log
/data/hermes/logs/**/*.log {
  daily
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  copytruncate
  maxsize 100M
}
LOGROTATE

echo "=== Bootstrap complete ==="
