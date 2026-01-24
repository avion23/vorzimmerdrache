# Infrastructure Documentation

## Overview

This infrastructure supports a production deployment of the Vorzimmerdrache automation platform using n8n, WhatsApp integration via Waha, and various third-party services.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Reverse Proxy (Traefik)                │
│                   SSL Termination / Load Balancing          │
└────────────────────┬────────────────────────────────────────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
┌───────▼──────┐ ┌──▼─────┐ ┌───▼─────────┐
│     n8n      │ │  Waha  │ │ Uptime Kuma │
│  Automation  │ │WhatsApp │ │  Monitoring │
│  Platform    │ │   API   │ │             │
└───────┬──────┘ └──┬─────┘ └─────────────┘
        │           │
        └─────┬─────┘
              │
    ┌─────────┼─────────┐
    │         │         │
┌───▼──┐  ┌──▼──┐  ┌───▼────┐
│PostgreSQL│Redis│ Backups │
└──────┘  └─────┘  └────────┘
```

## Components

### Core Services

- **n8n**: Workflow automation engine
  - Webhook handling
  - Workflow execution
  - Integration orchestration

- **Waha**: WhatsApp Business API
  - Message sending/receiving
  - Session management
  - Webhook forwarding to n8n

- **PostgreSQL**: Primary database
  - n8n workflow storage
  - Execution history
  - Credentials storage

- **Redis**: Cache and queue
  - Rate limiting
  - Job queue for n8n
  - Session caching

### Infrastructure Services

- **Traefik**: Reverse proxy and load balancer
  - SSL certificate management (Let's Encrypt)
  - Request routing
  - Basic authentication

- **Uptime Kuma**: Monitoring
  - Service health checks
  - Status page
  - Alert notifications

- **PostgreSQL Backup**: Automated backups
  - Daily backups
  - Retention policies
  - Compression

## Deployment Options

### Option 1: Hetzner Cloud VPS (Recommended for Production)

**Pros:**
- Full control over infrastructure
- Cost-effective (€4.89/month for CX22 with 4GB RAM)
- Data residency in Germany (GDPR compliant)
- No vendor lock-in
- Direct access to all system resources
- Easier to scale vertically

**Cons:**
- Requires DevOps maintenance
- Manual scaling
- Self-managed backups (automated via Docker)
- SSL certificate management via Traefik

**Requirements:**
- CX22 server (4GB RAM, 2 vCPU) or CX42 for high traffic
- Ubuntu 22.04
- SSH access
- Domain name with DNS control

**Cost Breakdown (Monthly):**
- CX22 server: €4.89
- Traffic (20GB included): €0-€10 depending on usage
- Domain: €1-€10
- **Total: ~€6-€25/month**

### Option 2: Railway (PaaS Alternative)

**Pros:**
- Zero DevOps overhead
- Auto-scaling
- Built-in monitoring
- Automatic SSL certificates
- GitHub integration
- Managed databases

**Cons:**
- Higher cost
- Vendor lock-in
- Less control over infrastructure
- Cold starts on free tier
- Limited to Railway ecosystem

**Requirements:**
- Railway account
- GitHub repository
- Environment variables configuration

**Cost Breakdown (Monthly):**
- n8n service: $5-20 (depending on usage)
- PostgreSQL: $5-10
- Redis: $5-10
- Waha: $5-10
- **Total: $20-50/month**

### Option 3: n8n Cloud (SaaS)

**Pros:**
- No infrastructure management
- Included hosting and maintenance
- Team collaboration features
- Priority support

**Cons:**
- Most expensive option
- Limited integrations compared to self-hosted
- Workflow execution limits
- No custom WhatsApp API (Waha not available)

**Cost Breakdown (Monthly):**
- Starter: $20
- Pro: $45
- Enterprise: Custom

**Recommendation**: Use n8n Cloud for n8n, self-host Waha on Hetzner

## Setup Instructions

### Hetzner Deployment

1. **Prerequisites:**
   ```bash
   hcloud context create vorzimmerdrache
   ssh-keygen -t ed25519 -C 'hetzner'
   ```

2. **Deploy:**
   ```bash
   chmod +x scripts/deploy-hetzner.sh
   ./scripts/deploy-hetzner.sh
   ```

3. **Configure:**
   ```bash
   ssh root@<server-ip>
   cd /opt/vorzimmerdrache
   nano .env
   ```

4. **Update DNS:**
   - A record: `n8n.yourdomain.com` → `<server-ip>`
   - A record: `waha.yourdomain.com` → `<server-ip>`
   - A record: `uptime.yourdomain.com` → `<server-ip>`

5. **Restart:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```

### Railway Deployment

1. **Install CLI:**
   ```bash
   npm install -g @railway/cli
   railway login
   ```

2. **Deploy:**
   ```bash
   chmod +x scripts/deploy-railway.sh
   ./scripts/deploy-railway.sh
   ```

3. **Configure Variables:**
   - Visit Railway dashboard
   - Add environment variables from `.env.example`
   - Generate secure keys where needed

## Scaling Strategy

### Vertical Scaling (Hetzner)

| Traffic Level | Server Type | RAM | vCPU | Cost/Month |
|--------------|-------------|-----|------|------------|
| Low          | CX22        | 4GB | 2    | €4.89      |
| Medium       | CX32        | 8GB | 2    | €9.72      |
| High         | CX42        | 16GB| 4    | €19.44     |

### Horizontal Scaling (Railway)

- Automatic scaling based on CPU/memory usage
- Configure in Railway dashboard per service
- Set minimum/maximum instance counts

## Backup Strategy

### Database Backups (PostgreSQL)

**Automated (via postgres-backup-local):**
- Daily: 7 days retention
- Weekly: 4 weeks retention
- Monthly: 6 months retention
- Stored in `/opt/vorzimmerdrache/backups`

**Manual:**
```bash
docker exec postgres pg_dump -U n8n n8n > backup.sql
```

### n8n Workflows

**Export Regularly:**
1. n8n UI → Settings → Export Workflows
2. Download as JSON
3. Commit to Git repository

**Git-based:**
```bash
git add workflows/
git commit -m "Update workflows"
git push
```

### Google Sheets

**Method 1: Version History:**
- File → Version History → See version history
- Named versions for major changes

**Method 2: Regular Exports:**
- File → Download → Microsoft Excel (.xlsx)
- Store in backup location

**Method 3: Google Takeout:**
- takeout.google.com → Select Google Drive → Create archive

### Waha Sessions

**Backed up in Docker volume:**
- `waha_sessions` volume
- Excluded from automated backup (contains tokens)
- Manual backup if needed:
```bash
docker run --rm -v vorzimmerdrache_waha_sessions:/data -v $(pwd):/backup alpine tar czf /backup/waha-sessions.tar.gz -C /data .
```

## Monitoring

### Uptime Kuma

**Access:** `https://uptime.yourdomain.com`

**Default Credentials:** Set in `.env` (TRAEFIK_AUTH)

**Monitors to Create:**
1. n8n: `https://n8n.yourdomain.com/healthz` (or `healthz` endpoint)
2. Waha: `https://waha.yourdomain.com`
3. PostgreSQL: Check container health
4. Redis: Check container health

**Alert Channels:**
- Email (default)
- Telegram
- Discord
- Slack
- Webhook (n8n)

### n8n Metrics

**Enabled by default:**
- Execution count
- Execution duration
- Error rate
- Active workflows

**Access via Traefik Dashboard:** `https://traefik.yourdomain.com`

## Security

### Network Security

- All services behind Traefik reverse proxy
- Internal network isolation (backend network)
- Firewall rules (Hetzner/UFW)
- Rate limiting via Redis

### Authentication

- n8n: Basic auth (configured in `.env`)
- Traefik Dashboard: Basic auth
- Waha: API token authentication
- Uptime Kuma: Login credentials

### Secrets Management

**Never commit `.env` to Git**
- Use `.env.example` as template
- Store actual values securely
- Rotate keys regularly

**Recommended:**
- Use strong, unique passwords
- Generate 32+ character encryption keys
- Rotate API keys quarterly
- Use vault/secret manager for production

### SSL/TLS

- Automatic via Let's Encrypt (Traefik)
- HSTS enabled by default
- Certificate renewal automatic

## Performance Optimization

### n8n

```env
EXECUTIONS_MODE=queue
CONCURRENCY_PRODUCTION_LIMIT=10
EXECUTIONS_TIMEOUT=300
EXECUTIONS_TIMEOUT_MAX=3600
```

### PostgreSQL

```env
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
```

### Redis

- AOF persistence enabled
- Memory limit configured
- Key expiration policies

## Troubleshooting

### Container Won't Start

```bash
docker-compose logs <service-name>
docker-compose ps
```

### Database Connection Failed

```bash
docker-compose exec postgres psql -U n8n -d n8n -c "SELECT 1"
```

### SSL Certificate Issues

```bash
docker-compose restart traefik
docker logs traefik | grep cert
```

### High Memory Usage

```bash
docker stats
docker-compose down && docker-compose up -d
```

### n8n Webhooks Not Receiving

- Check `WEBHOOK_URL` in `.env`
- Verify Traefik routing rules
- Test webhook endpoint: `curl https://n8n.yourdomain.com/webhook/test`

## Maintenance Tasks

### Weekly

- Check Uptime Kuma alerts
- Review execution logs in n8n
- Verify backup files exist

### Monthly

- Review and rotate API keys
- Update Docker images: `docker-compose pull && docker-compose up -d`
- Review Google Sheets data retention
- Check storage usage

### Quarterly

- Full system update on Hetzner: `apt-get update && apt-get upgrade -y`
- Security audit of logs
- Backup restoration test
- Review cost and usage

## Disaster Recovery

### Restore PostgreSQL

```bash
docker-compose exec postgres psql -U n8n n8n < /backups/latest.sql
```

### Restore n8n Workflows

```bash
# Import via n8n UI
# Settings → Import Workflows → Select JSON file
```

### Server Migration (Hetzner)

1. Create new server
2. Copy `.env` and volumes: `rsync -avz /opt/vorzimmerdrache/ root@new-server:/opt/vorzimmerdrache/`
3. Update DNS
4. Destroy old server

## Contact

For infrastructure issues:
- Check logs: `docker-compose logs -f`
- Monitor uptime: `https://uptime.yourdomain.com`
- Review n8n execution history
