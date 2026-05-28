#!/bin/bash
set -euo pipefail

# Migrate local Hermes data + documents to EC2
# Usage: ./scripts/migrate-data.sh <EC2_IP> <SSH_KEY_PATH> [DOCS_DIR]

EC2_IP="${1:?Usage: $0 <EC2_IP> <SSH_KEY_PATH> [DOCS_DIR]}"
SSH_KEY="${2:?Usage: $0 <EC2_IP> <SSH_KEY_PATH> [DOCS_DIR]}"
DOCS_DIR="${3:-}"
SSH_OPTS="-o StrictHostKeyChecking=accept-new -i $SSH_KEY"
REMOTE="ubuntu@$EC2_IP"

HERMES_LOCAL="$HOME/.hermes"

echo "=== Hermes Data Migration ==="
echo "Target: $EC2_IP"
echo ""

# ---------- Pre-flight checks ----------

if [ ! -d "$HERMES_LOCAL" ]; then
  echo "WARNING: No local ~/.hermes directory found."
  echo "Skipping Hermes data migration (fresh install)."
  SKIP_HERMES=true
else
  HERMES_SIZE=$(du -sh "$HERMES_LOCAL" 2>/dev/null | cut -f1)
  echo "Hermes data: $HERMES_LOCAL ($HERMES_SIZE)"
  SKIP_HERMES=false
fi

if [ -n "$DOCS_DIR" ]; then
  if [ ! -d "$DOCS_DIR" ]; then
    echo "ERROR: Documents directory not found: $DOCS_DIR"
    exit 1
  fi
  DOCS_SIZE=$(du -sh "$DOCS_DIR" 2>/dev/null | cut -f1)
  echo "Documents:   $DOCS_DIR ($DOCS_SIZE)"
fi

echo ""
read -p "Proceed with migration? [y/N] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

# ---------- Ensure remote directories exist ----------

echo "[1/5] Preparing remote directories..."
ssh $SSH_OPTS "$REMOTE" "sudo mkdir -p /data/hermes /data/documents && sudo chown -R 10000:10000 /data/hermes /data/documents"

# ---------- Migrate Hermes data ----------

if [ "$SKIP_HERMES" = false ]; then
  echo "[2/5] Syncing Hermes data (~/.hermes -> /data/hermes)..."
  rsync -avz --progress \
    --exclude='*.pyc' \
    --exclude='__pycache__' \
    --exclude='.git' \
    -e "ssh $SSH_OPTS" \
    "$HERMES_LOCAL/" "$REMOTE:/data/hermes/"
  ssh $SSH_OPTS "$REMOTE" "sudo chown -R 10000:10000 /data/hermes"
else
  echo "[2/5] Skipped (no local Hermes data)."
fi

# ---------- Migrate documents ----------

if [ -n "$DOCS_DIR" ]; then
  echo "[3/5] Syncing documents..."
  rsync -avz --progress \
    -e "ssh $SSH_OPTS" \
    "$DOCS_DIR/" "$REMOTE:/data/documents/"
  ssh $SSH_OPTS "$REMOTE" "sudo chown -R 10000:10000 /data/documents"
else
  echo "[3/5] Skipped (no documents directory specified)."
fi

# ---------- Validate ----------

echo "[4/5] Validating remote data..."
ssh $SSH_OPTS "$REMOTE" bash -s <<'VALIDATE'
echo "Remote /data/hermes:"
du -sh /data/hermes 2>/dev/null || echo "  (empty)"
ls /data/hermes/ 2>/dev/null | head -20

echo ""
echo "Remote /data/documents:"
du -sh /data/documents 2>/dev/null || echo "  (empty)"
ls /data/documents/ 2>/dev/null | head -20
VALIDATE

# ---------- Backup to S3 ----------

echo "[5/5] Creating initial S3 backup..."
ssh $SSH_OPTS "$REMOTE" bash -s <<'BACKUP'
BUCKET=$(aws s3 ls | grep hermes-backup | awk '{print $3}' | head -1)
if [ -n "$BUCKET" ]; then
  echo "Backing up to s3://$BUCKET ..."
  aws s3 sync /data/hermes "s3://$BUCKET/hermes/" --quiet
  aws s3 sync /data/documents "s3://$BUCKET/documents/" --quiet
  echo "Backup complete."
else
  echo "WARNING: No S3 backup bucket found. Run 'terraform apply' first."
fi
BACKUP

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps:"
echo "  1. Deploy Hermes:    ./scripts/deploy.sh $EC2_IP $SSH_KEY"
echo "  2. Enable Discord:   ssh $SSH_OPTS $REMOTE 'docker exec hermes hermes config set gateway.discord.enabled true'"
echo "  3. Select model:     ssh $SSH_OPTS $REMOTE 'docker exec hermes hermes config set model.default google/gemini-2.5-flash-preview'"
