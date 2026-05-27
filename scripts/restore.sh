#!/bin/bash
set -euo pipefail

# Restore Hermes data from S3 (run on EC2)
# Usage: ./scripts/restore.sh

BUCKET=$(aws s3 ls | grep hermes-backup | awk '{print $3}' | head -1)

if [ -z "$BUCKET" ]; then
  echo "ERROR: No hermes-backup S3 bucket found"
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

echo "[3/3] Restarting Hermes..."
cd /opt/hermes && docker compose up -d

echo "=== Restore complete ==="
