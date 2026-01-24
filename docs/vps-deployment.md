# VPS Deployment Guide for 1GB Instances

## Overview

This guide covers deploying Vorzimmerdrache on a 1GB VPS with automatic swap configuration, Docker optimization, and monitoring.

## System Requirements

- **RAM**: 1GB minimum (2GB recommended)
- **Disk**: 20GB minimum
- **OS**: Ubuntu 22.04 LTS or Debian 11+
- **Access**: Root or sudo privileges

## Memory Allocation

| Service   | Limit | Reservation | OOM Priority |
|-----------|-------|-------------|--------------|
| n8n       | 400MB | 150MB       | -100         |
| Waha      | 200MB | 80MB        | -100         |
| PostgreSQL| 150MB | 50MB        | -500         |
| Redis     | 50MB  | 20MB        | -500         |
| **Total** | 800MB | 300MB       | -            |

**Swap**: 4GB configured automatically to prevent OOM kills

## Quick Deploy

```bash
sudo bash scripts/deploy-1gb-vps.sh
```

Follow prompts:
1. Enter repository URL
2. Confirm deploy directory (default: `/opt/vorzimmerdrache`)
3. Enable systemd service (recommended)

## Manual Deployment

### 1. System Preparation

```bash
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y curl git htop
```

### 2. Configure Swap

```bash
sudo dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

### 3. Tune Kernel Parameters

```bash
sudo sysctl vm.swappiness=10
sudo sysctl vm.vfs_cache_pressure=75
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'vm.vfs_cache_pressure=75' | sudo tee -a /etc/sysctl.conf

echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' | sudo tee -a /etc/rc.local
sudo chmod +x /etc/rc.local
```

### 4. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
sudo systemctl start docker
sudo systemctl enable docker
```

### 5. Deploy Application

```bash
git clone <repo-url> /opt/vorzimmerdrache
cd /opt/vorzimmerdrache
cp .env.example .env

# Generate secure keys
sed -i "s/<generate-32-char-random-key>/$(openssl rand -hex 32)/" .env
sed -i "s/<strong-password>/$(openssl rand -base64 24)/" .env
sed -i "s/<strong-db-password>/$(openssl rand -base64 24)/" .env
sed -i "s/<strong-redis-password>/$(openssl rand -base64 24)/" .env
sed -i "s/<generate-random-api-token>/$(openssl rand -hex 32)/" .env
```

### 6. Configure Environment

Edit `.env` with your values:
```bash
nano .env
```

Required changes:
- `N8N_HOST=n8n.yourdomain.com`
- `POSTGRES_PASSWORD` (already generated)
- `REDIS_PASSWORD` (already generated)
- `WAHA_API_TOKEN` (already generated)
- `DOMAIN=yourdomain.com`

### 7. Start Services

```bash
docker compose -f docker-compose-low-memory.yml up -d
```

Wait for health checks:
```bash
docker compose ps
```

## Monitoring

### Real-time Memory Monitor

```bash
bash scripts/monitor.sh
```

Shows:
- RAM/Swap usage
- Container memory stats
- OOM kill detection
- Disk usage

Exit with Ctrl+C or run once:
```bash
bash scripts/monitor.sh --once
```

### Docker Stats

```bash
docker stats --no-stream
```

### System Overview

```bash
free -h
df -h
htop
```

## Log Management

### Manual Cleanup

```bash
sudo bash scripts/logs-clean.sh
```

Options:
```bash
sudo bash scripts/logs-clean.sh /var/log/vorzimmerdrache 100M 7
```

Parameters:
1. Log directory (default: `/var/log/vorzimmerdrache`)
2. Max file size (default: `100M`)
3. Retention days (default: `7`)

### Automatic Rotation (Cron)

```bash
sudo crontab -e
```

Add:
```cron
0 2 * * * /opt/vorzimmerdrache/scripts/logs-clean.sh >> /var/log/log-cleanup.log 2>&1
*/5 * * * * /opt/vorzimmerdrache/scripts/monitor.sh --once >> /var/log/memory-monitor.log 2>&1
```

## Auto-Restart Configuration

### Systemd Service

Created automatically by deployment script or manually:

```bash
sudo nano /etc/systemd/system/vorzimmerdrache.service
```

```ini
[Unit]
Description=Vorzimmerdrache Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/vorzimmerdrache
ExecStart=/usr/bin/docker compose -f /opt/vorzimmerdrache/docker-compose-low-memory.yml up -d
ExecStop=/usr/bin/docker compose -f /opt/vorzimmerdrache/docker-compose-low-memory.yml down
TimeoutStartSec=0
User=root

[Install]
WantedBy=multi-user.target
```

Enable:
```bash
sudo systemctl daemon-reload
sudo systemctl enable vorzimmerdrache.service
```

### Docker Restart Policy

Services already configured with `restart: on-failure` in compose file.

## Troubleshooting

### High Memory Usage

Check swap:
```bash
swapon --show
free -h
```

Check OOM kills:
```bash
dmesg | grep -i kill
```

Restart services:
```bash
docker compose -f docker-compose-low-memory.yml restart
```

### Containers Not Starting

Check logs:
```bash
docker compose logs
docker compose logs <service-name>
```

Check health:
```bash
docker compose ps
```

### Disk Space Full

Run cleanup:
```bash
sudo bash scripts/logs-clean.sh
docker system prune -a
```

Check large files:
```bash
du -sh /var/lib/docker/*
```

## Performance Tuning

### Reduce n8n Concurrency

Edit `.env`:
```bash
N8N_CONCURRENCY_PRODUCTION_LIMIT=3
```

### Reduce PostgreSQL Connections

Edit `config/postgresql-low-memory.conf`:
```conf
max_connections = 10
```

### Disable Redis Persistence

In `docker-compose-low-memory.yml`:
```yaml
command: redis-server --maxmemory 32mb --maxmemory-policy allkeys-lru
```

## Upgrading VPS

If consistently hitting memory limits:

1. Check usage over 24 hours:
```bash
watch -n 30 'free -h && docker stats --no-stream'
```

2. Export data before upgrade:
```bash
docker compose exec postgres pg_dump -U n8n n8n > backup.sql
```

3. Upgrade to 2GB VPS
4. Adjust memory limits in compose file:
```yaml
mem_limit: 800m  # n8n
mem_limit: 400m  # Waha
mem_limit: 300m  # PostgreSQL
mem_limit: 100m  # Redis
```

5. Redeploy:
```bash
docker compose -f docker-compose-low-memory.yml up -d
```

## Security

### Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

### Fail2Ban

```bash
sudo apt-get install -y fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

### Update System

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

## Backup Strategy

### Database Backup

```bash
docker compose exec postgres pg_dump -U n8n n8n > /backups/db-$(date +%Y%m%d).sql
```

### Volume Backup

```bash
docker run --rm -v vorzimmerdrache_postgres_data:/data -v /backups:/backup alpine tar czf /backup/postgres-data-$(date +%Y%m%d).tar.gz -C /data .
```

### Automated Backup

Add to crontab:
```cron
0 3 * * * docker compose exec postgres pg_dump -U n8n n8n > /backups/db-$(date +\%Y\%m\%d).sql
0 4 * * * find /backups -name "*.sql" -mtime +7 -delete
```

## Monitoring Alerts

Set up alerting for:

- Available memory < 50MB
- Swap usage > 50%
- Disk usage > 80%
- Container restarts > 5/hour

Example monitoring script:
```bash
#!/bin/bash
AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')
if [ "$AVAILABLE" -lt 50 ]; then
    echo "CRITICAL: Low memory - $AVAILABLE MB available" | mail -s "Memory Alert" admin@example.com
fi
```

## Additional Resources

- Health checks: `bash scripts/health-check.sh`
- Docker stats: `docker stats --no-stream`
- System logs: `journalctl -u docker -f`
- Application logs: `docker compose logs -f`
