#!/bin/bash
set -euo pipefail

# Deploy Hermes to EC2 instance
# Usage: ./scripts/deploy.sh <EC2_IP> <SSH_KEY_PATH>

EC2_IP="${1:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"
SSH_KEY="${2:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -i $SSH_KEY"
REMOTE="ubuntu@$EC2_IP"

echo "=== Deploying Hermes to $EC2_IP ==="

echo "[1/6] Copying deployment files..."
scp $SSH_OPTS docker-compose.yml "$REMOTE:/opt/hermes/"
scp $SSH_OPTS .env "$REMOTE:/opt/hermes/"
scp $SSH_OPTS scripts/*.sh "$REMOTE:/opt/hermes/scripts/"

echo "[2/6] Writing .env into Hermes home directory..."
ssh $SSH_OPTS "$REMOTE" "sudo cp /opt/hermes/.env /data/hermes/.env && sudo chown 10000:10000 /data/hermes/.env"

echo "[3/6] Setting up scheduled tasks..."
ssh $SSH_OPTS "$REMOTE" bash -s <<'CRON'
chmod +x /opt/hermes/scripts/*.sh
# Replace hermes-related cron entries, keep anything else
(crontab -l 2>/dev/null | grep -v '/opt/hermes/scripts/'; \
 echo "0 3 * * * /opt/hermes/scripts/backup.sh >> /var/log/hermes-backup.log 2>&1"; \
 echo "0 */6 * * * /opt/hermes/scripts/disk-check.sh >> /var/log/hermes-disk-check.log 2>&1" \
) | crontab -
echo "Cron jobs installed:"
crontab -l
CRON

echo "[4/6] Pulling latest Hermes image..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose pull"

echo "[5/6] Starting services..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose up -d"

echo "[6/6] Checking status..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose ps"

echo ""
echo "=== Deployment complete ==="
echo ""
echo "Dashboard: ssh $SSH_OPTS -L 9119:localhost:9119 $REMOTE"
echo "           then open http://localhost:9119"
echo "Logs:      ssh $SSH_OPTS $REMOTE 'cd /opt/hermes && docker compose logs -f'"
