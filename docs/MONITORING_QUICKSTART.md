# Monitoring System Quick Start

## Overview
Production-ready memory monitoring and alerting system for 1-2GB VPS, designed to prevent the "48-hour failure" scenario.

## Files Created

| File | Purpose |
|------|---------|
| `scripts/monitor.sh` | Enhanced real-time monitoring with memory pressure, OOM detection, swap rates |
| `scripts/auto-recovery.sh` | Automatic recovery for stuck sessions, queue overflow, swap thrashing |
| `scripts/daily-report.sh` | Daily health report at 8am via Telegram |
| `scripts/metrics-exporter.sh` | Prometheus-compatible metrics exporter |
| `scripts/install-monitoring.sh` | Systemd service installer |
| `scripts/MONITORING.md` | Full documentation |
| `scripts/test-monitoring.sh` | Self-test script |

## Key Features

### 1. Memory Pressure Detection
- Reads from `/proc/pressure/memory` (PSI)
- Scores 0-100 for severity
- Critical threshold: 80%

### 2. OOM Kill Detection
- Parses `dmesg` for "Out of memory" events
- Tracks killed processes
- Alerts immediately

### 3. Swap Monitoring
- Tracks swap in/out rates (not just total)
- Thresholds: 2GB critical
- Detects swap thrashing

### 4. PostgreSQL Health
- Cache hit ratio monitoring (target: >90%)
- Active connections tracking
- Database size metrics

### 5. Container Monitoring
- Per-container memory usage
- Restart loop detection
- Auto-recovery for stuck containers

### 6. Telegram Alerts
- Three severity levels: INFO, WARNING, CRITICAL
- Rate limiting: 1 alert per 10min per type
- Configurable thresholds

## Quick Setup (5 minutes)

### 1. Configure Telegram
```bash
cd scripts
# Edit monitor.conf with your Telegram bot token and chat ID
nano monitor.conf
```

Required variables:
```
TELEGRAM_BOT_TOKEN="your_bot_token"
TELEGRAM_CHAT_ID="your_chat_id"
```

### 2. Install Services
```bash
./install-monitoring.sh install
```

This installs 4 systemd services:
- `vps-monitor.service` - Runs continuously
- `vps-auto-recovery.timer` - Checks every 5min
- `vps-daily-report.timer` - Reports at 8am daily
- `vps-metrics-exporter.timer` - Updates metrics every 60s

### 3. Verify
```bash
# Check service status
./install-monitoring.sh status

# Test monitor manually
./monitor.sh --once

# Test metrics export
./metrics-exporter.sh export
```

## Manual Testing

### Run Monitor Once
```bash
./monitor.sh --once
```

### Run Auto-Recovery
```bash
./auto-recovery.sh run-all
```

### Generate Daily Report
```bash
./daily-report.sh telegram
```

### Export Metrics
```bash
./metrics-exporter.sh export
```

## Prometheus Integration

Add to `prometheus.yml`:
```yaml
scrape_configs:
  - job_name: 'vps'
    file_sd_configs:
      - files: ['/opt/vorzimmerdrache/.alerts/metrics/*.prom']
```

Metrics available:
- `waha_session_status{status="connected|disconnected"}`
- `n8n_workflow_executions{status="active|waiting|completed|failed"}`
- `lead_count`
- `memory_pressure_score`
- `container_memory_bytes{container="name"}`
- `postgres_cache_hit_ratio`
- `redis_memory_bytes`
- `alerts_total{severity="critical|warning|info"}`

## Alert Thresholds (Default)

| Metric | Warning | Critical |
|--------|---------|----------|
| Memory Pressure | 60% | 80% |
| Available Memory | <100MB | <50MB |
| Swap Usage | >1GB | >2GB |
| PostgreSQL Cache | <90% | <80% |
| Disk Usage | >80% | >90% |

## Auto-Recovery Rules

1. **Stuck Waha Sessions**
   - Detect sessions inactive >1 hour
   - Restart waha container

2. **n8n Queue Overflow**
   - Detect >1000 jobs in queue
   - Pause low-priority workflows

3. **Swap Thrashing**
   - Detect >5000KB/s swap-in rate
   - Stop non-essential containers

4. **Container Restart Loops**
   - Detect >5 restarts in 5min
   - Analyze logs for OOM
   - Adjust memory limits if needed

## Troubleshooting

### Monitor not starting
```bash
journalctl -u vps-monitor.service -f
```

### Telegram alerts not sending
```bash
# Check token and chat ID
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"

# View alert history
tail -f .alerts/alert_history.log
```

### Auto-recovery not triggering
```bash
# Check recovery log
tail -f .alerts/recovery.log

# Manually test
./auto-recovery.sh run-all
```

## Uninstall

```bash
./install-monitoring.sh uninstall
```

## Architecture

```
monitor.sh (continuous, 30s interval)
    ├── Memory pressure from PSI
    ├── OOM detection from dmesg
    ├── PostgreSQL cache ratio
    ├── Swap in/out rates
    ├── Container stats
    └── Telegram alerts (rate-limited)

auto-recovery.sh (every 5min)
    ├── Stuck Waha sessions
    ├── n8n queue overflow
    ├── Swap thrashing
    └── Container restart loops

daily-report.sh (8am daily)
    └── Telegram summary report

metrics-exporter.sh (every 60s)
    └── Prometheus format metrics
```

## Customization

Edit `scripts/monitor.conf`:
```bash
# Alert thresholds
MEMORY_PRESSURE_THRESHOLD=80
POSTGRES_CACHE_THRESHOLD=90
SWAP_THRESHOLD_MB=2048

# Rate limiting
ALERT_RATE_LIMIT_SEC=600

# Auto-recovery
ENABLE_AUTO_RECOVERY=true
ESSENTIAL_CONTAINERS="postgres,redis,n8n,waha,traefik"
```

## Full Documentation

See `scripts/MONITORING.md` for complete documentation.
