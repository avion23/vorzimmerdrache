# VPS Memory Monitoring & Alerting System

Advanced monitoring for 1-2GB VPS to prevent the "48-hour failure" scenario.

## Components

### 1. monitor.sh
Real-time monitoring with advanced metrics:
- Memory pressure score (0-100 from /proc/pressure/memory)
- OOM kill detection (dmesg parsing)
- Per-container memory usage
- PostgreSQL cache hit ratio
- Swap in/out rates
- Color-coded alerts

### 2. auto-recovery.sh
Automatic recovery actions:
- Detect stuck Waha sessions → restart container
- Detect n8n queue overflow → pause low-priority workflows
- Detect swap thrashing → kill non-essential containers
- Detect container restart loops → handle based on cause

### 3. daily-report.sh
Daily health reports at 8am:
- System uptime
- Memory stats (avg/peak)
- Lead count
- Workflow status
- Container status
- PostgreSQL cache ratio
- Redis stats
- Error/Alert counts

### 4. metrics-exporter.sh
Prometheus-compatible metrics:
- `waha_session_status` - Connected/disconnected sessions
- `n8n_workflow_executions` - Active/waiting/completed/failed
- `lead_count` - Total leads in database
- `memory_pressure_score` - Pressure from PSI
- `container_memory_bytes` - Per-container memory
- `container_cpu_percent` - Per-container CPU
- `postgres_cache_hit_ratio` - PostgreSQL cache efficiency
- `redis_memory_bytes` - Redis memory usage
- `alerts_total` - Alerts by severity

## Setup

1. Configure Telegram alerts:
```bash
cd scripts
cp monitor.conf monitor.conf.local
# Edit TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID
```

2. Install systemd services:
```bash
./install-monitoring.sh install
```

3. Check status:
```bash
./install-monitoring.sh status
```

## Manual Usage

### Monitor
```bash
# Run once
./monitor.sh --once

# Continuous monitoring (30s interval)
./monitor.sh
```

### Auto Recovery
```bash
# Run all checks
./auto-recovery.sh run-all

# Individual checks
./auto-recovery.sh check-waha
./auto-recovery.sh check-queue
./auto-recovery.sh check-swap
./auto-recovery.sh check-loops

# Manual recovery
./auto-recovery.sh restart-waha "Manual trigger"
```

### Daily Report
```bash
# Send via Telegram
./daily-report.sh telegram

# Preview report only
./daily-report.sh | less
```

### Metrics
```bash
# Export all metrics
./metrics-exporter.sh export

# Export specific metrics
./metrics-exporter.sh waha
./metrics-exporter.sh n8n
./metrics-exporter.sh leads
```

## Alert Thresholds

Configure in `monitor.conf`:
- `MEMORY_PRESSURE_THRESHOLD=80` - Critical memory pressure
- `POSTGRES_CACHE_THRESHOLD=90` - Low cache hit ratio
- `SWAP_THRESHOLD_MB=2048` - High swap usage
- `ALERT_RATE_LIMIT_SEC=600` - Max 1 alert per 10min
- `MEMORY_CRITICAL_MB=50` - Critical available memory
- `MEMORY_WARNING_MB=100` - Warning available memory
- `DISK_WARNING_PCT=80` - Disk warning
- `DISK_CRITICAL_PCT=90` - Disk critical

## Systemd Services

- `vps-monitor.service` - Continuous monitoring (30s interval)
- `vps-auto-recovery.timer` - Recovery checks every 5min
- `vps-daily-report.timer` - Daily report at 8am
- `vps-metrics-exporter.timer` - Metrics export every 60s

## Logs

All logs stored in `.alerts/`:
- `alert_state.json` - Alert rate limiting state
- `recovery.log` - Recovery actions
- `memory_stats.log` - Memory history
- `error_count.log` - Error tracking
- `alert_history.log` - Alert history
- `reports/YYYY-MM-DD.txt` - Daily reports
- `metrics/metrics.prom` - Current metrics

## Integration with Grafana

If you have Prometheus + Grafana:

1. Add Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'vps'
    static_configs:
      - targets: ['localhost:9090']
    file_sd_configs:
      - files: ['/opt/vorzimmerdrache/.alerts/metrics/*.prom']
```

2. Import dashboard for:
- Memory pressure over time
- Container memory trends
- Workflow execution rates
- PostgreSQL cache ratio
- Alert frequency
- Lead count growth

## Troubleshooting

### Monitor not starting:
```bash
journalctl -u vps-monitor.service -f
```

### Auto-recovery not running:
```bash
systemctl list-timers "vps-*"
cat .alerts/recovery.log
```

### Telegram alerts not sending:
- Check bot token and chat ID
- Verify bot can send messages to chat
- Check logs: `tail .alerts/alert_history.log`

### Metrics not updating:
```bash
cat .alerts/metrics/metrics.prom
systemctl restart vps-metrics-exporter.timer
```

## Uninstall

```bash
./install-monitoring.sh uninstall
```
