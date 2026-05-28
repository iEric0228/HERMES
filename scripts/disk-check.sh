#!/bin/bash
set -euo pipefail

# Check disk usage and alert via SNS if above threshold
# Runs via cron every 6 hours

CONF="/opt/hermes/backup.conf"
THRESHOLD=85

if [ ! -f "$CONF" ]; then
  echo "WARNING: No backup.conf found, skipping disk check"
  exit 0
fi

source "$CONF"

USAGE=$(df /data | tail -1 | awk '{print $5}' | tr -d '%')
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ "$USAGE" -gt "$THRESHOLD" ]; then
  HOSTNAME=$(hostname)
  echo "[$TIMESTAMP] ALERT: Disk usage at ${USAGE}% (threshold: ${THRESHOLD}%)"
  if [ -n "${SNS_TOPIC_ARN:-}" ]; then
    aws sns publish \
      --topic-arn "$SNS_TOPIC_ARN" \
      --subject "Hermes: Disk usage at ${USAGE}%" \
      --message "Data volume /data is at ${USAGE}% capacity on ${HOSTNAME}. Consider cleaning up old logs or expanding the EBS volume." \
      --region "${AWS_DEFAULT_REGION:-us-east-1}" \
      2>/dev/null || true
  fi
else
  echo "[$TIMESTAMP] OK: Disk usage at ${USAGE}%"
fi
