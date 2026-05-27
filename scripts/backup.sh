#!/bin/bash
set -euo pipefail

# Backup Hermes data to S3 (run on EC2 via cron)
# Install: crontab -e → 0 3 * * * /opt/hermes/scripts/backup.sh

BUCKET=$(aws s3 ls | grep hermes-backup | awk '{print $3}' | head -1)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -z "$BUCKET" ]; then
  echo "ERROR: No hermes-backup S3 bucket found"
  exit 1
fi

echo "[$TIMESTAMP] Backing up to s3://$BUCKET ..."

aws s3 sync /data/hermes "s3://$BUCKET/hermes/" \
  --exclude '*.pyc' \
  --exclude '__pycache__/*' \
  --delete \
  --quiet

aws s3 sync /data/documents "s3://$BUCKET/documents/" \
  --delete \
  --quiet

echo "[$TIMESTAMP] Backup complete."
