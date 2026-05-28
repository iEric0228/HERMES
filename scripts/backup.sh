#!/bin/bash
set -euo pipefail

# Backup Hermes data to S3 (run on EC2 via cron)
# Sends SNS alert on failure if configured.

CONF="/opt/hermes/backup.conf"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Load config (bucket name + SNS topic written by Terraform bootstrap)
if [ -f "$CONF" ]; then
  source "$CONF"
  BUCKET="${BACKUP_BUCKET:-}"
else
  # Fallback: discover bucket by name prefix
  BUCKET=$(aws s3 ls | grep hermes-backup | awk '{print $3}' | head -1)
fi

if [ -z "$BUCKET" ]; then
  echo "[$TIMESTAMP] ERROR: No backup bucket configured or discovered"
  exit 1
fi

# Alert via SNS on any failure
notify_failure() {
  local msg="$1"
  echo "[$TIMESTAMP] BACKUP FAILED: $msg"
  if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    aws sns publish \
      --topic-arn "$SNS_TOPIC_ARN" \
      --subject "Hermes: Backup failed" \
      --message "Backup failed at $TIMESTAMP on $(hostname): $msg" \
      --region "${AWS_DEFAULT_REGION:-us-east-1}" \
      2>/dev/null || true
  fi
  exit 1
}

trap 'notify_failure "unexpected error on line $LINENO"' ERR

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
