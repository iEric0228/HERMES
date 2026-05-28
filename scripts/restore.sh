#!/bin/bash
set -euo pipefail

# Restore Hermes data from S3 (run on EC2)
# Usage: ./scripts/restore.sh

CONF="/opt/hermes/backup.conf"

# Load config (bucket name written by Terraform bootstrap)
if [ -f "$CONF" ]; then
  source "$CONF"
  BUCKET="${BACKUP_BUCKET:-}"
else
  # Fallback: discover bucket by name prefix
  BUCKET=$(aws s3 ls | grep hermes-backup | awk '{print $3}' | head -1)
fi

if [ -z "$BUCKET" ]; then
  echo "ERROR: No backup bucket configured or discovered"
  exit 1
fi

echo "=== Restoring from s3://$BUCKET ==="
echo ""
echo "WARNING: This will overwrite current data in /data/hermes and /data/documents."
read -p "Continue? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo "[1/3] Stopping Hermes..."
cd /opt/hermes && docker compose down

echo "[2/3] Restoring data..."
aws s3 sync "s3://$BUCKET/hermes/" /data/hermes/ --delete
aws s3 sync "s3://$BUCKET/documents/" /data/documents/ --delete
chown -R 10000:10000 /data/hermes /data/documents

echo "[3/3] Restarting Hermes..."
cd /opt/hermes && docker compose up -d

echo "=== Restore complete ==="
