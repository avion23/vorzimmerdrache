# 1GB VPS Docker Optimization Guide

## Overview

This configuration optimizes n8n, Waha, PostgreSQL, and Redis for a 1GB VPS with ~200MB reserved for the OS.

## Service Resource Allocation

| Service  | Memory Limit | Memory Reservation | CPU Limit |
|----------|--------------|-------------------|-----------|
| n8n      | 400MB        | 150MB             | 0.5 cores |
| Waha     | 200MB        | 80MB              | 0.25 cores |
| PostgreSQL| 150MB       | 50MB              | 0.25 cores |
| Redis    | 50MB         | 20MB              | 0.25 cores |
| **Total**| **800MB**    | **300MB**         | **1.25 cores** |

## OOM Kill Priority

Services ordered by OOM protection (lower = first killed):
- n8n: `-100` (moderate protection)
- Waha: `-100` (moderate protection)
- PostgreSQL: `-500` (high protection)
- Redis: `-500` (high protection)

## Key Optimizations

### n8n

1. **Execution Mode**: Switched from `queue` to `regular` (single worker, less overhead)
2. **Database Pooling**: `DB_POSTGRESDB_POOL_SIZE=5` to limit connections
3. **Payload Limit**: `N8N_PAYLOAD_SIZE_MAX=8` (MB) to prevent large payloads
4. **Concurrency**: `N8N_CONCURRENCY_PRODUCTION_LIMIT=5`
5. **Logging**: Level set to `warn` to reduce I/O
6. **Metrics**: Disabled to reduce CPU/memory

### Waha

1. **Image**: Uses `devlikeapro/waha-plus` (lighter than standard)
2. **Media Download**: `WHATSAPP_DISABLE_MEDIA_DOWNLOAD=true`
3. **Chrome Flags**: Comprehensive headless Chrome optimizations:
   - `--disable-gpu` (no graphics)
   - `--disable-software-rasterizer` (no rasterization)
   - `--disable-dev-shm-usage` (uses tmpfs instead of /dev/shm)
   - `--no-sandbox` (reduces process overhead in container)
   - `--single-process` (reduces memory but slightly slower)
4. **Session Storage**: Persistent volumes (not in RAM)

### PostgreSQL

Configuration in `config/postgresql-low-memory.conf`:

```conf
memory = 128MB
shared_buffers = 32MB
effective_cache_size = 64MB
work_mem = 2MB
max_connections = 20
```

Key settings:
- Reduced shared buffers from default 25% to 32MB
- Lowered max connections from 100 to 20
- Disabled parallel workers
- Set `synchronous_commit=off` for faster writes (potential data loss on crash)
- Reduced logging overhead
- Single autovacuum worker

### Redis

1. **Max Memory**: `--maxmemory 32mb`
2. **Eviction Policy**: `allkeys-lru` (evicts least recently used keys)
3. **Persistence**: AOF enabled with optimized save intervals
4. **Logging**: Minimal

## Startup Order

Services start with health checks to ensure dependencies are ready:

1. **PostgreSQL** → waits for `pg_isready`
2. **Redis** → waits for `redis-cli ping`
3. **Waha** → depends on Redis healthy
4. **n8n** → depends on PostgreSQL & Redis healthy

## Health Checks

All services include health checks with:
- **Interval**: 15-30 seconds
- **Timeout**: 5-10 seconds
- **Retries**: 3-5
- **Start Period**: 10-60 seconds (service-specific)

## Monitoring

Run health checks:

```bash
bash scripts/health-check.sh
```

Checks:
- Service reachability
- Container memory usage vs limits
- System memory usage
- Disk space

## Deploying

```bash
docker-compose -f docker-compose-low-memory.yml up -d
```

## Monitoring Memory

```bash
docker stats --no-stream
docker stats --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
```

## Scaling Up

If you experience OOM kills:

1. Check `dmesg | grep -i kill` for OOM victims
2. Increase limits for victim service
3. Reduce workload/workflow complexity
4. Consider upgrading to 2GB VPS

## Trade-offs

This configuration prioritizes stability over performance:

**Pros**:
- Fits within 1GB RAM
- Survives moderate traffic spikes
- Data persistence maintained

**Cons**:
- Slower workflow execution
- Potential data loss on PostgreSQL crash (sync commit off)
- Single n8n worker (no queue parallelism)
- Larger media payloads may fail

## Recommended Monitoring

Set up cron for health checks:

```bash
*/5 * * * * /path/to/scripts/health-check.sh >> /var/log/health-check.log 2>&1
```
