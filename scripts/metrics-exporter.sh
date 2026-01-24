#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_DIR="${SCRIPT_DIR}/../.alerts/metrics"

mkdir -p "$METRICS_DIR"

get_waha_session_status() {
    local connected=0 disconnected=0
    local sessions

    sessions=$(docker exec waha ls /app/.sessions 2>/dev/null || true)

    for session in $sessions; do
        local status_file="/app/.sessions/${session}/status.json"
        if docker exec waha test -f "$status_file" 2>/dev/null; then
            local status
            status=$(docker exec waha cat "$status_file" 2>/dev/null | jq -r '.status // "disconnected"' || echo "disconnected")

            if [ "$status" = "CONNECTED" ]; then
                connected=$((connected + 1))
            else
                disconnected=$((disconnected + 1))
            fi
        fi
    done

    echo "waha_session_status{status=\"connected\"} $connected"
    echo "waha_session_status{status=\"disconnected\"} $disconnected"
}

get_n8n_workflow_executions() {
    local active completed failed waiting

    if docker exec redis redis-cli -a "${REDIS_PASSWORD}" KEYS "bull:n8n:*" 2>/dev/null | grep -q .; then
        active=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" SCARD "bull:n8n:active" 2>/dev/null || echo 0)
        waiting=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LLEN "bull:n8n:wait" 2>/dev/null || echo 0)
        completed=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LLEN "bull:n8n:completed" 2>/dev/null || echo 0)
        failed=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LLEN "bull:n8n:failed" 2>/dev/null || echo 0)
    else
        active=0
        waiting=0
        completed=0
        failed=0
    fi

    echo "n8n_workflow_executions{status=\"active\"} $active"
    echo "n8n_workflow_executions{status=\"waiting\"} $waiting"
    echo "n8n_workflow_executions{status=\"completed\"} $completed"
    echo "n8n_workflow_executions{status=\"failed\"} $failed"
}

get_lead_count() {
    local count=0

    if docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE '%lead%';
    " 2>/dev/null | grep -q "[0-9]"; then

        local tables
        tables=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
            SELECT table_name FROM information_schema.tables WHERE table_name LIKE '%lead%';
        " 2>/dev/null | tr -d ' ' || true)

        for table in $tables; do
            local table_count
            table_count=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
                SELECT COUNT(*) FROM ${table};
            " 2>/dev/null | xargs || echo 0)
            count=$((count + table_count))
        done
    fi

    echo "lead_count $count"
}

get_memory_pressure() {
    local pressure_file="/proc/pressure/memory"

    if [ ! -f "$pressure_file" ]; then
        echo "memory_pressure_score 0"
        return
    fi

    local some_avg full_avg score
    some_avg=$(awk 'NR==1 {gsub(/[^0-9.]/, "", $2); print $2}' "$pressure_file")
    full_avg=$(awk 'NR==1 {gsub(/[^0-9.]/, "", $4); print $4}' "$pressure_file")
    score=$(awk "BEGIN {printf \"%.0f\", ($some_avg + $full_avg) * 50}")

    echo "memory_pressure_score $score"
}

get_container_memory() {
    docker stats --no-stream --format "{{.Name}} {{.MemUsage}}" 2>/dev/null | while read -r line; do
        local name mem_usage mem_percent
        read -r name mem_usage mem_percent <<< "$line"

        local mem_mb
        mem_mb=$(echo "$mem_usage" | sed 's/ MiB//' | awk '{print $1}')
        local percent
        percent=$(echo "$mem_percent" | sed 's/%//')

        name=$(echo "$name" | sed 's/^//')
        name=$(echo "$name" | sed 's/\./_/g')

        echo "container_memory_bytes{container=\"$name\"} $((mem_mb * 1024 * 1024))"
        echo "container_memory_percent{container=\"$name\"} $percent"
    done
}

get_container_cpu() {
    docker stats --no-stream --format "{{.Name}} {{.CPUPerc}}" 2>/dev/null | while read -r line; do
        local name cpu_percent
        read -r name cpu_percent <<< "$line"

        cpu_percent=$(echo "$cpu_percent" | sed 's/%//')
        name=$(echo "$name" | sed 's/^//')
        name=$(echo "$name" | sed 's/\./_/g')

        echo "container_cpu_percent{container=\"$name\"} $cpu_percent"
    done
}

get_postgres_metrics() {
    local cache_ratio connections size

    cache_ratio=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT ROUND((sum(blks_hit)::numeric / NULLIF(sum(blks_hit) + sum(blks_read), 0)) * 100, 2)
        FROM pg_stat_database;
    " 2>/dev/null | awk '{print $1}' || echo 0)

    connections=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT COUNT(*) FROM pg_stat_activity;
    " 2>/dev/null | awk '{print $1}' || echo 0)

    size=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT pg_database_size('${POSTGRES_DB:-n8n}');
    " 2>/dev/null | awk '{print $1}' || echo 0)

    echo "postgres_cache_hit_ratio $cache_ratio"
    echo "postgres_active_connections $connections"
    echo "postgres_database_size_bytes $size"
}

get_redis_metrics() {
    local memory keys connected_clients

    memory=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory 2>/dev/null | grep used_memory: | cut -d: -f2 | tr -d '\r' || echo 0)
    keys=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" DBSIZE 2>/dev/null || echo 0)
    connected_clients=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO clients 2>/dev/null | grep connected_clients: | cut -d: -f2 | tr -d '\r' || echo 0)

    echo "redis_memory_bytes $memory"
    echo "redis_total_keys $keys"
    echo "redis_connected_clients $connected_clients"
}

get_swap_metrics() {
    local total used swapin_rate swapout_rate

    read -r total used < <(free -m | awk '/^Swap:/ {print $2, $3}')

    if [ -f /tmp/swap_stats_prev ]; then
        read -r swapin_prev swapout_prev < /tmp/swap_stats_prev
    else
        swapin_prev=0
        swapout_prev=0
    fi

    read -r swapin_cur swapout_cur < <(grep -E '^swapin|^swapout' /proc/vmstat | awk '{print $2}')
    echo "$swapin_cur $swapout_cur" > /tmp/swap_stats_prev

    swapin_rate=$(( (swapin_cur - swapin_prev) / 30 ))
    swapout_rate=$(( (swapout_cur - swapout_prev) / 30 ))

    echo "swap_total_bytes $((total * 1024 * 1024))"
    echo "swap_used_bytes $((used * 1024 * 1024))"
    echo "swap_swapin_rate $swapin_rate"
    echo "swap_swapout_rate $swapout_rate"
}

get_alert_metrics() {
    local alert_log="${SCRIPT_DIR}/../.alerts/alert_history.log"
    local today
    today=$(date +%Y-%m-%d)

    local critical warning info
    if [ -f "$alert_log" ]; then
        critical=$(grep "$today.*CRITICAL" "$alert_log" 2>/dev/null | wc -l | tr -d ' ')
        warning=$(grep "$today.*WARNING" "$alert_log" 2>/dev/null | wc -l | tr -d ' ')
        info=$(grep "$today.*INFO" "$alert_log" 2>/dev/null | wc -l | tr -d ' ')
    else
        critical=0
        warning=0
        info=0
    fi

    echo "alerts_total{severity=\"critical\"} $critical"
    echo "alerts_total{severity=\"warning\"} $warning"
    echo "alerts_total{severity=\"info\"} $info"
}

export_metrics() {
    local output_file="${METRICS_DIR}/metrics.prom"

    {
        echo "# HELP waha_session_status Current status of Waha WhatsApp sessions"
        echo "# TYPE waha_session_status gauge"
        get_waha_session_status
        echo ""

        echo "# HELP n8n_workflow_executions Number of workflow executions by status"
        echo "# TYPE n8n_workflow_executions gauge"
        get_n8n_workflow_executions
        echo ""

        echo "# HELP lead_count Total number of leads in database"
        echo "# TYPE lead_count gauge"
        get_lead_count
        echo ""

        echo "# HELP memory_pressure_score Memory pressure score from /proc/pressure/memory"
        echo "# TYPE memory_pressure_score gauge"
        get_memory_pressure
        echo ""

        echo "# HELP container_memory_bytes Memory usage per container in bytes"
        echo "# TYPE container_memory_bytes gauge"
        get_container_memory
        echo ""

        echo "# HELP container_cpu_percent CPU usage per container"
        echo "# TYPE container_cpu_percent gauge"
        get_container_cpu
        echo ""

        echo "# HELP postgres_cache_hit_ratio PostgreSQL cache hit ratio"
        echo "# TYPE postgres_cache_hit_ratio gauge"
        get_postgres_metrics
        echo ""

        echo "# HELP redis_memory_bytes Redis memory usage in bytes"
        echo "# TYPE redis_memory_bytes gauge"
        get_redis_metrics
        echo ""

        echo "# HELP swap_total_bytes Total swap space in bytes"
        echo "# TYPE swap_total_bytes gauge"
        echo "# HELP swap_used_bytes Used swap space in bytes"
        echo "# TYPE swap_used_bytes gauge"
        echo "# HELP swap_swapin_rate Swap-in rate in KB/s"
        echo "# TYPE swap_swapin_rate gauge"
        echo "# HELP swap_swapout_rate Swap-out rate in KB/s"
        echo "# TYPE swap_swapout_rate gauge"
        get_swap_metrics
        echo ""

        echo "# HELP alerts_total Number of alerts by severity"
        echo "# TYPE alerts_total counter"
        get_alert_metrics
        echo ""
    } > "$output_file"

    cat "$output_file"
}

main() {
    case "${1:-}" in
        waha)
            get_waha_session_status
            ;;
        n8n)
            get_n8n_workflow_executions
            ;;
        leads)
            get_lead_count
            ;;
        export)
            export_metrics
            ;;
        *)
            export_metrics
            ;;
    esac
}

main "$@"
