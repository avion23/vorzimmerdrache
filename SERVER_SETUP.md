# Server Setup Guide

## Prerequisites

### Server Requirements
- **RAM**: 1GB minimum (CX11 at Hetzner recommended)
- **Storage**: 20GB minimum (Docker volumes + logs)
- **OS**: Ubuntu 22.04 LTS or Debian 12
- **Ports**: 80 and 443 must be open
- **Docker**: 20.10+ (installed by deploy script if missing)

### Domain Configuration
- Domain or subdomain pointing to your server IP
- DNS A record required (AAAA for IPv6 optional)
- Recommended: DuckDNS for free dynamic DNS
  - Example: `instance1.duckdns.org`

### Required Accounts

**Twilio** (WhatsApp + Voice)
- Account SID and Auth Token
- WhatsApp-enabled phone number
- WhatsApp template approved
- Minimum €20 credit required

**Google** (Sheets API)
- Google Cloud project
- Sheets API enabled
- OAuth2 credentials OR Service Account
- Spreadsheet shared with account email

**Telegram** (Alert notifications)
- Bot token from @BotFather
- Chat ID for notifications

---

## Quick Deployment

### 1. Clone Repository
```bash
git clone <your-repo-url> vorzimmerdrache
cd vorzimmerdrache
```

### 2. Configure Environment Variables
```bash
cp .env.example .env
nano .env
```

Update these critical variables:
- `DOMAIN`: Your domain name
- `SSL_EMAIL`: Email for Let's Encrypt certificates
- `N8N_ENCRYPTION_KEY`: Generate with `openssl rand -hex 16`
- `TWILIO_ACCOUNT_SID`: From Twilio console
- `TWILIO_AUTH_TOKEN`: From Twilio console
- `TWILIO_PHONE_NUMBER`: Your Twilio number
- `TWILIO_WHATSAPP_SENDER`: WhatsApp-enabled number
- `TELEGRAM_BOT_TOKEN`: From @BotFather
- `TELEGRAM_CHAT_ID`: Your Telegram chat ID
- Google credentials (see Service Accounts section below)

### 3. Run Deploy Script
```bash
chmod +x scripts/deploy-1gb.sh
./scripts/deploy-1gb.sh
```

### 4. Access n8n
```bash
# Script will output your URL
https://your-domain.com/
```

Default n8n login (if configured):
- Check `.env` for `N8N_BASIC_AUTH_USER` and `N8N_BASIC_AUTH_PASSWORD`

---

## Detailed Configuration

### Environment Variables

#### Required Variables
```bash
# SSL and Domain
SSL_EMAIL=admin@example.com              # Email for Let's Encrypt
DOMAIN=instance1.duckdns.org             # Your domain
N8N_ENCRYPTION_KEY=...                   # Generate: openssl rand -hex 16

# n8n Configuration
N8N_HOST=${DOMAIN}                       # Same as DOMAIN
N8N_PORT=5678                            # Default n8n port
N8N_PROTOCOL=https                        # HTTPS with Traefik
WEBHOOK_URL=https://${DOMAIN}/           # Base URL for webhooks
NODE_ENV=production                      # Production mode
GENERIC_TIMEZONE=Europe/Berlin           # Your timezone
```

#### Twilio Configuration
```bash
TWILIO_ACCOUNT_SID=AC...                 # From Twilio console
TWILIO_AUTH_TOKEN=...                    # From Twilio console
TWILIO_PHONE_NUMBER=+491234567890        # Your Twilio number
TWILIO_WHATSAPP_SENDER=whatsapp:+49...   # WhatsApp-enabled number
TWILIO_WHATSAPP_TEMPLATE_SID=WH...       # Template SID from Twilio
```

#### Telegram Configuration
```bash
TELEGRAM_BOT_TOKEN=1234567890:ABC...     # From @BotFather
TELEGRAM_CHAT_ID=123456789               # Your chat ID (send msg to @userinfobot)
```

#### Google Sheets OAuth2
```bash
GOOGLE_SHEETS_SPREADSHEET_ID=1U73YUGk... # From spreadsheet URL
GOOGLE_SHEETS_SHEET_NAME=Leads           # Sheet/tab name
GOOGLE_SHEETS_RANGE=Sheet1!A1:F100       # Data range
GOOGLE_OAUTH_CLIENT_ID=...apps.googleusercontent.com
GOOGLE_OAUTH_CLIENT_SECRET=...
GOOGLE_OAUTH_REFRESH_TOKEN=...          # Long-lived token
GOOGLE_OAUTH_ACCESS_TOKEN=...           # Short-lived, auto-refreshed
```

#### Google Sheets Service Account (Alternative)
```bash
GOOGLE_SHEETS_SPREADSHEET_ID=1U73YUGk... # From spreadsheet URL
GOOGLE_SHEETS_SHEET_NAME=Leads           # Sheet/tab name
GOOGLE_SHEETS_RANGE=Sheet1!A1:F100       # Data range
GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
# Paste entire JSON key as single-line string
```

#### SMS Opt-in (Optional)
```bash
SMS_OPT_IN_WEBHOOK_URL=https://.../webhook/sms-response
```

### Docker Compose Architecture

#### Services

**Traefik** (Reverse Proxy)
- Image: `traefik:v2.11`
- Memory Limit: 256MB
- Memory Reservation: 64MB
- Ports: 80 (HTTP), 443 (HTTPS)
- Purpose: SSL termination, routing, load balancing

**n8n** (Workflow Automation)
- Image: `docker.n8n.io/n8nio/n8n`
- Memory Limit: 512MB
- Memory Reservation: 128MB
- Database: SQLite (internal, no external DB)
- Purpose: Workflow execution, webhook handling

#### Total Resource Usage
- **Total Container RAM**: ~300MB
- **OS Overhead**: ~200MB
- **Free RAM**: ~500MB for spikes

#### Health Checks
```yaml
Traefik: Built-in (container restart)
n8n: wget http://localhost:5678/ every 30s
  - Timeout: 10s
  - Retries: 3
  - Start period: 60s
```

#### Volume Management
```yaml
letsencrypt:  SSL certificates (Let's Encrypt)
n8n_data:     n8n SQLite database + workflows + credentials
```

### Service Accounts

#### Google Sheets: OAuth2 vs Service Account

**OAuth2 (Original Setup)**
- ✅ Easy to set up
- ✅ Works with shared/personal spreadsheets
- ❌ Tokens expire (needs refresh mechanism)
- ❌ Not ideal for headless servers

**Service Account (Recommended)**
- ✅ No token expiration
- ✅ Better for headless servers
- ✅ More secure (credentials in JSON file)
- ❌ Requires sharing spreadsheet with service account email

#### Service Account Setup Steps

**1. Enable Google Sheets API**
```bash
# Go to: https://console.cloud.google.com/apis/library
# Search: "Google Sheets API"
# Click "Enable"
```

**2. Create Service Account**
```bash
# Go to: https://console.cloud.google.com/iam-admin/serviceaccounts
# Click "Create Service Account"
# Name: "Vorzimmerdrache-n8n"
# Click "Create and Continue"
# Skip roles (optional)
# Click "Done"
```

**3. Generate JSON Key**
```bash
# Click on your new service account
# Go to "Keys" tab
# Click "Add Key" → "Create new key"
# Key type: JSON
# Download the JSON file
# Copy contents to .env:
GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON='{"type":"service_account",...}'
# Important: Use single quotes, escape inner quotes if needed
```

**4. Share the Spreadsheet**
```bash
# Open your spreadsheet
# Click "Share"
# Add service account email (from JSON file, "client_email" field)
# Set as "Editor"
# Click "Send"
```

**5. Configure n8n**
```bash
# Add credentials to .env (done in step 3)
# Import workflows/roof-mode.json
# Update Google Sheets node with Service Account credentials
# Use JSON from GOOGLE_SHEETS_SERVICE_ACCOUNT_JSON
```

#### Twilio API Setup

**1. Get Account Credentials**
```bash
# Go to: https://console.twilio.com/
# Dashboard → Project Info
# Copy Account SID and Auth Token
```

**2. Get WhatsApp Number**
```bash
# Messaging → Try it out → Send a WhatsApp message
# Get a sandbox number OR purchase a WhatsApp-enabled number
# Copy number to .env as TWILIO_WHATSAPP_SENDER
# Format: whatsapp:+491234567890
```

**3. Approve WhatsApp Template**
```bash
# Messaging → Settings → WhatsApp templates
# Create template (must be approved before use)
# Template name and SID → Copy to .env
```

**4. Get Voice Number**
```bash
# Phone Numbers → Buy a Number
# Search for German number (+49)
# Select and purchase
# Copy number to .env as TWILIO_PHONE_NUMBER
# Format: +491234567890
```

#### Telegram Bot Setup

**1. Create Bot**
```bash
# Open Telegram
# Search for: @BotFather
# Send: /newbot
# Follow prompts to name your bot
# Copy bot token to .env as TELEGRAM_BOT_TOKEN
```

**2. Get Chat ID**
```bash
# Open Telegram
# Search for: @userinfobot
# Start chat
# Bot will reply with your Chat ID
# Copy to .env as TELEGRAM_CHAT_ID
```

**3. Test Bot**
```bash
# In Telegram, search for your bot by username
# Send a message to verify it works
```

---

## Troubleshooting

### Common Issues and Solutions

#### Issue: n8n won't start
**Symptoms**: Container keeps restarting, logs show errors
**Solutions**:
```bash
# Check logs
docker compose logs n8n

# Verify .env syntax (no spaces around =)
# Check N8N_ENCRYPTION_KEY is exactly 32 chars

# Restart with clean state
docker compose down -v
docker compose up -d
```

#### Issue: Let's Encrypt certificate fails
**Symptoms**: Traefik shows 404, SSL certificate errors
**Solutions**:
```bash
# Check DNS is pointing to correct IP
dig +short your-domain.com

# Verify port 80 is reachable from internet
# Run from local machine:
curl http://your-domain.com/

# Check Traefik logs
docker compose logs traefik

# Clear Let's Encrypt cache and retry
rm -rf letsencrypt/acme.json
docker compose restart traefik
```

#### Issue: Twilio webhooks not triggering
**Symptoms**: n8n workflows don't run on calls/messages
**Solutions**:
```bash
# Verify webhook URL is correct
# Should be: https://your-domain.com/webhook/twilio

# Check n8n is accessible
curl https://your-domain.com/

# Verify n8n webhook node is active
# Open n8n UI → Check workflow status

# Check Twilio webhook logs in Twilio console
# Monitor → Debugger
```

#### Issue: Google Sheets API authentication fails
**Symptoms**: Workflow fails at Google Sheets node
**Solutions**:
```bash
# Verify spreadsheet ID is correct
# Check in browser URL: docs.google.com/spreadsheets/d/SPREADSHEET_ID

# Verify sheet name and range
# Sheet name must match exactly (case-sensitive)

# OAuth2: Check tokens are not expired
# Regenerate at: https://developers.google.com/oauthplayground/

# Service Account: Verify JSON is valid
# Test with: echo "$JSON" | python3 -m json.tool

# Verify spreadsheet is shared with correct email
# OAuth2: Use OAuth client email
# Service Account: Use "client_email" from JSON
```

#### Issue: Telegram bot not sending messages
**Symptoms**: No Telegram alerts
**Solutions**:
```bash
# Verify bot token is correct
# Send message to bot in Telegram to test

# Verify chat ID is correct
# Check with @userinfobot

# Test API directly:
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=Test message"
```

### Docker Errors

#### Container out of memory
**Symptoms**: OOMKilled, containers restart
**Solutions**:
```bash
# Check memory usage
docker stats

# Increase memory limits in docker-compose.yml
# Or use docker-compose-low-memory.yml

# Reduce n8n execution data retention
# Set: EXECUTIONS_DATA_MAX_AGE=72 (hours)
```

#### Container won't stop
**Solutions**:
```bash
# Force stop
docker compose kill

# Remove containers
docker compose rm -f

# Clean up system
docker system prune -a
```

#### Volume mounting issues
**Symptoms**: Permission denied, volume errors
**Solutions**:
```bash
# Check volume permissions
ls -la ./letsencrypt
ls -la n8n_data

# Fix permissions
sudo chown -R 1000:1000 ./letsencrypt
sudo chown -R 1000:1000 ./n8n_data

# Or recreate volumes
docker compose down -v
docker compose up -d
```

### n8n Startup Problems

#### n8n UI not loading
**Solutions**:
```bash
# Check n8n is healthy
docker compose ps

# Check n8n logs
docker compose logs -f n8n

# Verify Traefik is routing correctly
docker compose logs traefik

# Check n8n port mapping
docker port vorzimmerdrache-n8n-1
```

#### Workflows not executing
**Solutions**:
```bash
# Verify workflow is active (green toggle)
# Check execution history in n8n UI
# Check webhook URL is correct
# Verify webhook node has "Response Mode: On Last Node"
```

#### Database locked errors
**Solutions**:
```bash
# SQLite doesn't support concurrent writes well
# Restart n8n to release locks
docker compose restart n8n

# Consider switching to PostgreSQL for production
# See docker-compose-low-memory.yml
```

### Traefik SSL Certificate Issues

#### Certificate not renewing
**Symptoms**: Certificate expired, SSL warnings
**Solutions**:
```bash
# Check acme.json
cat letsencrypt/acme.json

# Verify email is correct in .env
grep SSL_EMAIL .env

# Manually trigger renewal by restarting Traefik
docker compose restart traefik

# Clear and retry (last resort)
rm -rf letsencrypt/acme.json
docker compose restart traefik
```

#### Rate limiting from Let's Encrypt
**Symptoms**: Certificate creation fails
**Solutions**:
```bash
# Wait 1 hour (rate limit: 5 certs/domain/hour)
# Use staging environment for testing
# Uncomment in docker-compose.yml:
# --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

### Memory Pressure on 1GB VPS

#### System slow, high load
**Solutions**:
```bash
# Check memory usage
free -h

# Check container memory
docker stats

# Restart services to free memory
docker compose restart

# Use low-memory compose file
docker compose -f docker-compose-low-memory.yml up -d

# Enable n8n execution pruning
# Already enabled in default config:
# EXECUTIONS_DATA_PRUNE=true
# EXECUTIONS_DATA_MAX_AGE=168
```

#### OOM (Out of Memory) Killer
**Symptoms**: Processes killed, system unstable
**Solutions**:
```bash
# Add swap space (1GB recommended)
sudo fallocate -l 1G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Reduce n8n memory limit
# Edit docker-compose.yml:
# n8n memory: 512M → 384M

# Disable unnecessary services
# Example: If not using SMS opt-in, remove webhook endpoints
```

#### Docker eating memory
**Solutions**:
```bash
# Clean up unused images
docker image prune -a

# Clean up build cache
docker builder prune

# Remove stopped containers
docker container prune

# Limit Docker daemon memory
# Edit /etc/docker/daemon.json:
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
sudo systemctl restart docker
```

---

## Monitoring

### Check Logs

#### All Services
```bash
# All logs (last 100 lines)
docker compose logs --tail=100

# Follow logs in real-time
docker compose logs -f

# Specific service
docker compose logs -f n8n
docker compose logs -f traefik
```

#### n8n Logs
```bash
# Last 50 lines
docker compose logs --tail=50 n8n

# Since 1 hour ago
docker compose logs --since=1h n8n

# Filter for errors
docker compose logs n8n | grep -i error
```

#### Traefik Logs
```bash
# Check SSL certificate issues
docker compose logs traefik | grep -i certificate

# Check routing issues
docker compose logs traefik | grep -i router
```

### Health Endpoints

#### n8n Health Check
```bash
# Local check
curl http://localhost:5678/healthz

# External check
curl https://your-domain.com/healthz
```

#### Container Status
```bash
# Show all containers with health
docker compose ps

# Detailed info
docker inspect vorzimmerdrache-n8n-1 | grep -A 10 Health
```

### Resource Monitoring

#### System Resources
```bash
# CPU, memory, disk
htop

# Memory usage
free -h

# Disk usage
df -h

# Docker stats
docker stats
```

#### Container-Specific
```bash
# n8n memory usage
docker stats vorzimmerdrache-n8n-1 --no-stream

# Traefik memory usage
docker stats vorzimmerdrache-traefik-1 --no-stream

# Disk usage of volumes
du -sh ./letsencrypt ./n8n_data
```

#### Monitor Script (Create `scripts/monitor.sh`)
```bash
#!/bin/bash
echo "=== System Memory ==="
free -h

echo -e "\n=== Docker Containers ==="
docker compose ps

echo -e "\n=== Docker Stats ==="
docker stats --no-stream

echo -e "\n=== Disk Usage ==="
df -h

echo -e "\n=== Recent Logs (Errors) ==="
docker compose logs --tail=20 | grep -i error || echo "No errors found"
```

```bash
chmod +x scripts/monitor.sh
./scripts/monitor.sh
```

### Alerts

#### Telegram Alerts (via n8n)
- Already configured in workflows
- Alerts sent for: new calls, errors, system issues
- Check n8n workflow: `workflows/roof-mode.json`

#### n8n Internal Monitoring
- Access n8n UI → Settings → Monitoring
- Enable workflow execution tracking
- Set up email notifications (optional)

---

## Security Notes

### Traefik API Security

#### Dashboard Exposure (Default: Disabled)
```yaml
# Traefik dashboard is NOT exposed by default
# To enable (NOT recommended on production):
# Add to docker-compose.yml traefik command:
# --api.insecure=true
# --api.dashboard=true
```

#### Docker Socket Security
```yaml
# Docker socket is mounted read-only
# volumes:
#   - "/var/run/docker.sock:/var/run/docker.sock:ro"
# Prevents container from modifying Docker config
```

#### API Rate Limiting
```bash
# Traefik doesn't have built-in rate limiting
# Use n8n workflow to limit webhook processing
# Example: Max 100 calls/hour per phone number
```

### Webhook Validation

#### Twilio Signature Validation
```bash
# n8n Twilio node validates signatures automatically
# Ensure TWILIO_AUTH_TOKEN is set correctly
# Verify webhook URL matches Twilio configuration
```

#### Custom Webhook Security
```bash
# For custom webhooks, add API key validation
# In n8n workflow: Add "Set" node with check:
# IF $webhook.headers["x-api-key"] !== $env.WEBHOOK_API_KEY
#   THEN reject request
```

#### HTTPS Only
```bash
# All webhooks should use HTTPS
# n8n configured with N8N_PROTOCOL=https
# Traefik redirects HTTP to HTTPS automatically
```

### Volume Backups

#### n8n Data Backup
```bash
# Create backup script: scripts/backup.sh
#!/bin/bash
BACKUP_DIR="/backup/n8n"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

# Backup n8n data
docker run --rm \
  -v vorzimmerdrache_n8n_data:/data \
  -v $BACKUP_DIR:/backup \
  alpine tar czf /backup/n8n_data_$DATE.tar.gz -C /data .

# Backup letsencrypt
tar czf $BACKUP_DIR/letsencrypt_$DATE.tar.gz ./letsencrypt

# Keep last 7 days
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup completed: n8n_data_$DATE.tar.gz"
```

```bash
chmod +x scripts/backup.sh
./scripts/backup.sh
```

#### Automated Backups (Cron)
```bash
# Add to crontab (daily at 2 AM):
crontab -e

# Add line:
0 2 * * * /path/to/vorzimmerdrache/scripts/backup.sh
```

#### Restore from Backup
```bash
# Restore n8n data
docker run --rm \
  -v vorzimmerdrache_n8n_data:/data \
  -v /backup/n8n:/backup \
  alpine tar xzf /backup/n8n_data_20240126_020000.tar.gz -C /data

# Restore letsencrypt
tar xzf /backup/letsencrypt_20240126_020000.tar.gz -C ./

# Restart services
docker compose restart
```

#### Backup to Remote (Optional)
```bash
# Use rclone to backup to cloud storage
rclone copy /backup/n8n remote:backups/vorzimmerdrache/n8n
rclone copy /backup/letsencrypt remote:backups/vorzimmerdrache/letsencrypt
```

### Additional Security Measures

#### Firewall Configuration
```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

#### SSH Security
```bash
# Disable password authentication
# Edit /etc/ssh/sshd_config:
PasswordAuthentication no
PubkeyAuthentication yes

# Change default SSH port
Port 2222

# Restart SSH
sudo systemctl restart sshd
```

#### Regular Updates
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Update Docker
curl -fsSL https://get.docker.com | sh

# Update Docker images
docker compose pull
docker compose up -d
```

#### Secret Management
```bash
# Never commit .env to git
# Add to .gitignore:
echo ".env" >> .gitignore

# Use environment-specific .env files
# .env.production for production
# .env.staging for staging

# Rotate secrets regularly
# Every 90 days:
# - Generate new N8N_ENCRYPTION_KEY
# - Rotate Twilio Auth Token
# - Rotate Telegram Bot Token
```

---

## Quick Reference

### Useful Commands
```bash
# Start services
docker compose up -d

# Stop services
docker compose down

# Restart services
docker compose restart

# View logs
docker compose logs -f

# Check status
docker compose ps

# Update services
docker compose pull && docker compose up -d

# Backup
./scripts/backup.sh

# Monitor
./scripts/monitor.sh
```

### File Locations
```bash
# Main config
.env                    # Environment variables
docker-compose.yml      # Docker services

# Data
letsencrypt/            # SSL certificates
n8n_data/               # n8n database and files

# Scripts
scripts/deploy-1gb.sh   # Deployment script
scripts/backup.sh       # Backup script
scripts/monitor.sh      # Monitoring script

# Workflows
workflows/roof-mode.json      # Main workflow
workflows/sms-opt-in.json     # SMS opt-in workflow
```

### URLs
```bash
n8n UI:          https://your-domain.com/
n8n Webhook:     https://your-domain.com/webhook/twilio
SMS Opt-in:      https://your-domain.com/webhook/sms-response
```

### Support Resources
- n8n Docs: https://docs.n8n.io
- Twilio Docs: https://www.twilio.com/docs
- Traefik Docs: https://doc.traefik.io/traefik
- Google Sheets API: https://developers.google.com/sheets/api
- Telegram Bot API: https://core.telegram.org/bots/api
