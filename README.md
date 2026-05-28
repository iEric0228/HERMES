# Hermes on AWS

Terraform + Docker deployment for [Hermes Agent](https://github.com/NousResearch/hermes-agent) on an AWS EC2 instance with Discord gateway, S3 backups, and data migration tooling.

## Architecture

```
You (Discord / SSH tunnel)
    |
    v
[EC2 t4g.medium - ARM, 4GB RAM]
    |-- Docker: hermes gateway (Discord bot + cron)
    |-- Docker: hermes dashboard (localhost:9119)
    |-- /data/hermes (50GB EBS, encrypted)
    |-- /data/documents (read-only mount)
    |
    v
[S3 backup bucket - versioned, KMS encrypted]
```

**Resources created by Terraform:**

| Resource | Purpose |
|----------|---------|
| VPC + public subnet | Isolated networking |
| EC2 (t4g.medium) | Runs Hermes in Docker |
| EBS 50GB gp3 | Persistent data volume (survives instance termination) |
| Elastic IP | Static public IP |
| S3 bucket | Nightly backups, versioned with Glacier lifecycle |
| IAM role | Least-privilege: SSM + S3 + SNS + CloudWatch |
| Security group | SSH from your IP only, all outbound |
| SNS topic | Email alerts for failures and alarms |
| CloudWatch alarms | Instance status check + high CPU alerts |

## Prerequisites

- AWS CLI configured (`aws sts get-caller-identity`)
- Terraform >= 1.5
- An EC2 key pair in your target region
- OpenRouter API key ([openrouter.ai/keys](https://openrouter.ai/keys))
- Discord bot token ([discord.com/developers](https://discord.com/developers/applications))

## Quick start

### 1. Configure Terraform

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region         = "us-east-1"
instance_type      = "t4g.medium"
key_name           = "your-key-pair"
allowed_ssh_cidr   = "YOUR_PUBLIC_IP/32"   # curl -4 ifconfig.me
data_volume_size   = 50
notification_email = "you@example.com"     # optional: alert emails
```

### 2. Deploy infrastructure

```bash
terraform init
terraform plan
terraform apply
```

Note the outputs: `public_ip`, `ssh_command`, `dashboard_tunnel`.

### 3. Wait for bootstrap (~3 min)

The EC2 user-data script installs Docker, creates swap, and mounts the data volume.

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP> 'tail -f /var/log/hermes-setup.log'
```

### 4. Configure secrets

```bash
cp .env.example .env
# Edit .env with your OpenRouter key and Discord bot token
```

### 5. Migrate data (optional)

```bash
./scripts/migrate-data.sh <EC2_IP> ~/.ssh/your-key.pem ~/path/to/documents
```

This rsyncs `~/.hermes` (memories, skills, sessions) and personal documents to the EC2 data volume, then creates an initial S3 backup.

### 6. Deploy Hermes

```bash
./scripts/deploy.sh <EC2_IP> ~/.ssh/your-key.pem
```

### 7. Enable Discord and set model

```bash
SSH="ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP>"

# Enable Discord gateway
$SSH 'docker exec hermes hermes config set gateway.discord.enabled true'

# Set a cost-effective default model
$SSH 'docker exec hermes hermes config set model.default google/gemini-2.5-flash-preview'

# Restart to apply
$SSH 'cd /opt/hermes && docker compose restart gateway'
```

### 8. Invite the bot to your server

Go to Discord Developer Portal > OAuth2 > URL Generator:
- Scope: `bot`
- Permissions: Send Messages, Read Message History, Attach Files, Embed Links

Open the generated URL, select your server, authorize.

### 9. Access the dashboard

```bash
# Create SSH tunnel (run locally)
ssh -i ~/.ssh/your-key.pem -L 9119:localhost:9119 ubuntu@<EC2_IP>

# Then open http://localhost:9119
```

## File structure

```
.
├── .env.example              # API keys template (never committed)
├── .gitignore
├── docker-compose.yml        # Hermes gateway + dashboard services
├── terraform/
│   ├── main.tf               # VPC, EC2, EBS, S3, IAM, SNS, CloudWatch
│   ├── variables.tf          # Configurable inputs
│   ├── outputs.tf            # IP, SSH command, tunnel command
│   ├── terraform.tfvars.example
│   └── user-data.sh.tpl      # EC2 bootstrap (Docker, swap, EBS mount)
└── scripts/
    ├── deploy.sh             # Push config + start containers on EC2
    ├── migrate-data.sh       # rsync local data to EC2 + S3 backup
    ├── backup.sh             # Nightly S3 backup with SNS failure alerts
    ├── restore.sh            # Restore from S3 backup
    └── disk-check.sh         # Disk usage monitor (cron every 6h)
```

## Operations

### View logs

```bash
# Gateway log (Discord connection, agent activity)
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP> \
  'docker exec hermes tail -f /opt/data/logs/gateway.log'

# Docker compose logs
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP> \
  'cd /opt/hermes && docker compose logs -f'
```

### Change model on the fly

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP> \
  'docker exec hermes hermes config set model.default anthropic/claude-sonnet-4'
```

No restart needed. You can also type `/model <name>` in Discord.

### Backups (automated)

`deploy.sh` installs two cron jobs automatically:
- **Nightly backup** (3 AM) — syncs data to S3, sends SNS alert on failure
- **Disk check** (every 6h) — alerts via SNS when data volume exceeds 85%

Check backup status:
```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP> \
  'tail -20 /var/log/hermes-backup.log'
```

### Restore from backup

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP>
/opt/hermes/scripts/restore.sh
```

### Update Hermes

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<EC2_IP>
cd /opt/hermes && docker compose pull && docker compose up -d
```

### Update your SSH IP

If your home IP changes and SSH stops working:

```bash
cd terraform
# Edit terraform.tfvars with new IP
terraform apply
```

## Monitoring

Terraform creates CloudWatch alarms and an SNS topic for alerts. Set `notification_email` in `terraform.tfvars` to receive them.

| Alert | Trigger | How |
|-------|---------|-----|
| Instance down | EC2 status check fails (2 consecutive) | CloudWatch alarm |
| High CPU | CPU > 90% for 15 min | CloudWatch alarm |
| Backup failed | S3 sync error during nightly backup | SNS from backup.sh |
| Disk full | Data volume > 85% capacity | SNS from disk-check.sh |

After first deploy, confirm the SNS subscription email (check spam).

Log rotation is configured via logrotate (14 days, 100MB max per file, compressed).

## Estimated monthly cost

| Resource | Cost |
|----------|------|
| EC2 t4g.medium (on-demand) | ~$24 |
| EBS 30GB root + 50GB data (gp3) | ~$6 |
| Elastic IP | ~$4 |
| S3 backup (~50GB) | ~$1 |
| CloudWatch alarms (2) | ~$0.20 |
| **Infrastructure total** | **~$35/mo** |
| LLM via OpenRouter (varies) | $5-30/mo |

Save ~40% on EC2 with a 1-year Reserved Instance.

## Troubleshooting

**SSH connection refused after reboot**
Your public IP may have changed. Update `allowed_ssh_cidr` in `terraform.tfvars` and run `terraform apply`.

**"No messaging platforms enabled"**
Run `docker exec hermes hermes config set gateway.discord.enabled true` and restart the gateway.

**Permission errors in logs**
The Hermes container runs as UID 10000. Ensure `/data/hermes` is owned by 10000:10000:
```bash
sudo chown -R 10000:10000 /data/hermes
```

**High token burn**
Switch to a cheaper model (`google/gemini-2.5-flash-preview` or `deepseek/deepseek-chat`) and reduce max turns:
```bash
docker exec hermes hermes config set model.default google/gemini-2.5-flash-preview
docker exec hermes hermes config set agent.max_turns 30
```

## Security

- SSH restricted to a single IP (security group)
- Dashboard is localhost-only (access via SSH tunnel)
- All EBS volumes encrypted at rest (AWS-managed KMS)
- S3 bucket: KMS encryption, versioning, public access blocked
- IAM role follows least privilege (S3 backup bucket only)
- `.env` files in `.gitignore` (never committed)
- Automatic OS security updates via unattended-upgrades
- 4GB swap prevents OOM kills
