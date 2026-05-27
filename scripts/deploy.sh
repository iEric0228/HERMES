#!/bin/bash
set -euo pipefail

# Deploy Hermes to EC2 instance
# Usage: ./scripts/deploy.sh <EC2_IP> <SSH_KEY_PATH>

EC2_IP="${1:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"
SSH_KEY="${2:?Usage: $0 <EC2_IP> <SSH_KEY_PATH>}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -i $SSH_KEY"
REMOTE="ubuntu@$EC2_IP"

echo "=== Deploying Hermes to $EC2_IP ==="

echo "[1/4] Copying deployment files..."
scp $SSH_OPTS docker-compose.yml "$REMOTE:/opt/hermes/"
scp $SSH_OPTS .env "$REMOTE:/opt/hermes/"

echo "[2/4] Pulling latest Hermes image..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose pull"

echo "[3/4] Starting services..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose up -d"

echo "[4/4] Checking status..."
ssh $SSH_OPTS "$REMOTE" "cd /opt/hermes && docker compose ps"

echo ""
echo "=== Deployment complete ==="
echo "Dashboard: ssh $SSH_OPTS -L 9119:localhost:9119 $REMOTE"
echo "           then open http://localhost:9119"
echo "Logs:      ssh $SSH_OPTS $REMOTE 'cd /opt/hermes && docker compose logs -f'"
