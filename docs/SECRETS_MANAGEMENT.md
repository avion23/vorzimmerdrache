# Secrets Management Guide

This document provides instructions for configuring secrets across GitHub Actions, Hetzner VPS, and the application.

## GitHub Secrets Setup

### Required GitHub Repository Secrets

Configure the following secrets in your GitHub repository (`Settings > Secrets and variables > Actions`):

#### SSH Connection
- `SSH_PRIVATE_KEY` - Private SSH key for VPS access (generate with `ssh-keygen -t ed25519`)
- `VPS_HOST` - Hetzner VPS hostname or IP address
- `VPS_USER` - SSH username (typically `root` or your deploy user)

#### Application Secrets
- `N8N_HOST` - n8n domain (e.g., `n8n.yourdomain.com`)
- `N8N_PORT` - n8n port (default: `5678`)
- `N8N_PROTOCOL` - Protocol (`http` or `https`)
- `N8N_ENCRYPTION_KEY` - 32-character random string (`openssl rand -hex 16`)
- `N8N_BASIC_AUTH_ACTIVE` - Enable basic auth (`true`/`false`)
- `N8N_BASIC_AUTH_USER` - Basic auth username
- `N8N_BASIC_AUTH_PASSWORD` - Basic auth password

- `WEBHOOK_URL` - Full webhook URL (e.g., `https://n8n.yourdomain.com`)
- `POSTGRES_USER` - PostgreSQL username (default: `n8n`)
- `POSTGRES_PASSWORD` - Strong database password
- `POSTGRES_DB` - Database name (default: `n8n`)
- `REDIS_PASSWORD` - Redis password
- `DOMAIN` - Base domain (e.g., `yourdomain.com`)
- `LETSENCRYPT_EMAIL` - Email for Let's Encrypt

- `WAHA_HOST` - Waha domain (e.g., `waha.yourdomain.com`)
- `WAHA_API_TOKEN` - Waha API token (generate: `openssl rand -hex 32`)
- `WAHA_API_URL` - Waha API URL (e.g., `https://waha.yourdomain.com`)
- `TRAEFIK_AUTH` - Traefik auth (`admin:$(openssl passwd -apr1 password)`)

#### Third-Party APIs
- `TELEGRAM_BOT_TOKEN` - From @BotFather
- `INSTALLER_TELEGRAM_CHAT_ID` - Your Telegram chat ID
- `TWILIO_ACCOUNT_SID` - From Twilio console
- `TWILIO_AUTH_TOKEN` - From Twilio console
- `TWILIO_PHONE_NUMBER` - Your Twilio phone number
- `OPENAI_API_KEY` - OpenAI API key
- `GEMINI_API_KEY` - Google Gemini API key
- `GOOGLE_SHEETS_ID` - Google Sheets ID
- `GOOGLE_SERVICE_ACCOUNT_JSON` - Service account JSON (escape quotes)
- `GOOGLE_MAPS_API_KEY` - Google Maps API key
- `INSTALLER_PHONE_NUMBER` - Installer phone number
- `TIMEZONE` - Your timezone (e.g., `Europe/Berlin`)

#### Optional
- `CODECOV_TOKEN` - Codecov token for coverage reports

## SSH Key Configuration

### Generate SSH Key Pair

On your local machine:
```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions_deploy
```

### Add Public Key to VPS

Copy the public key to your Hetzner VPS:
```bash
ssh-copy-id -i ~/.ssh/github_actions_deploy.pub user@your-vps-host
```

Or manually:
```bash
cat ~/.ssh/github_actions_deploy.pub
```

Add to `~/.ssh/authorized_keys` on VPS.

### Add Private Key to GitHub

Copy the private key and add to GitHub as `SSH_PRIVATE_KEY`:
```bash
cat ~/.ssh/github_actions_deploy
```

**Important**: Ensure no line breaks or extra characters.

## VPS Configuration

### Setup Deploy User

Create a dedicated deploy user (optional but recommended):
```bash
sudo useradd -m -s /bin/bash deploy
sudo usermod -aG docker deploy
sudo mkdir -p /app/vorzimmerdrache
sudo chown -R deploy:deploy /app
```

### Configure SSH

Create `.ssh/config` on VPS for the deploy user:
```bash
mkdir -p /home/deploy/.ssh
chmod 700 /home/deploy/.ssh
```

### Setup Project Directory

```bash
cd /app/vorzimmerdrache
git clone https://github.com/yourusername/vorzimmerdrache.git .
```

## Environment File Management

### VPS .env File

The CI/CD workflow creates `.env` from GitHub secrets during deployment.

For manual testing, create `.env` on VPS:
```bash
cp .env.example .env
nano .env
```

Fill in all required values from the secrets list above.

### Local Development .env

Create local `.env`:
```bash
cp .env.example .env
```

Use different values for local testing.

## Security Best Practices

### Secrets Storage

1. **Never commit secrets to git** - Use `.gitignore` to exclude `.env`
2. **Rotate keys regularly** - Update secrets quarterly
3. **Use strong passwords** - At least 32 characters
4. **Limit secret access** - Only grant access to necessary workflows
5. **Audit secrets** - Review GitHub Secrets monthly

### SSH Security

1. **Disable password auth** on VPS:
   ```bash
   sudo nano /etc/ssh/sshd_config
   # Set: PasswordAuthentication no
   sudo systemctl restart sshd
   ```

2. **Use key-based auth only** - SSH keys are more secure
3. **Limit SSH users** - Only allow deploy user from GitHub Actions IP ranges

### Backup Encryption

Encrypt database backups before storing:
```bash
./scripts/setup-backup-encryption.sh
```

### Transit Encryption

- Use HTTPS for all external API calls
- Use TLS for database connections
- Use SSH for all remote operations

## GitHub Actions IP Whitelisting

To limit access to specific IP ranges, add to your VPS firewall:
```bash
# GitHub Actions IPs (check current list at https://api.github.com/meta)
sudo ufw allow from 140.82.112.0/20 to any port 22
sudo ufw allow from 192.30.252.0/22 to any port 22
```

## Verification

Test your setup:

### 1. Test SSH Connection
```bash
ssh -i ~/.ssh/github_actions_deploy user@vps-host
```

### 2. Test GitHub Workflow
Push to a test branch and verify the workflow runs.

### 3. Verify Secrets on VPS
```bash
cat /app/vorzimmerdrache/.env | grep N8N_ENCRYPTION_KEY
```

## Troubleshooting

### SSH Connection Fails
- Verify private key format (no extra spaces)
- Check VPS firewall allows SSH (port 22)
- Verify user exists on VPS

### Secrets Not Found
- Check secret names match exactly (case-sensitive)
- Ensure secrets are in correct repository/organization
- Verify GitHub Actions permissions

### Deploy Fails
- Check deployment logs in GitHub Actions
- SSH into VPS and check `/app/vorzimmerdrache/logs/deploy.log`
- Verify Docker is running on VPS

### Smoke Tests Fail
- Check service health: `docker compose ps`
- Review logs: `docker compose logs n8n`
- Verify .env values are correct

## References

- GitHub Actions Secrets: https://docs.github.com/en/actions/security-guides/encrypted-secrets
- GitHub Actions IPs: https://api.github.com/meta
- SSH Key Management: https://www.ssh.com/academy/ssh/key
- Docker Security: https://docs.docker.com/engine/security/
