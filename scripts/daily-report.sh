#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPORT_LOG="${SCRIPT_DIR}/../.alerts/daily_reports.log"
CONFIG_FILE="${SCRIPT_DIR}/monitor.conf"

mkdir -p "$(dirname "$REPORT_LOG")"
source "$CONFIG_FILE" 2>/dev/null || true

calculate_uptime() {
    local uptime_seconds
    uptime_seconds=$(cat /proc/uptime | awk '{print $1}' | cut -d. -f1)

    local days=$((uptime_seconds / 86400))
    local hours=$(((uptime_seconds % 86400) / 3600))
    local minutes=$(((uptime_seconds % 3600) / 60))

    echo "${days}d ${hours}h ${minutes}m"
}

get_memory_stats() {
    local total used available percent peak
    read -r total available < <(free -m | awk '/^Mem:/ {print $2, $7}')
    used=$((total - available))
    percent=$((used * 100 / total))

    local stats_log="${SCRIPT_DIR}/../.alerts/memory_stats.log"
    if [ -f "$stats_log" ]; then
        peak=$(awk 'BEGIN {max=0} {if($2>max) max=$2} END {print max}' "$stats_log")
    else
        peak=$used
    fi

    jq -n \
        --arg total "${total}MB" \
        --arg used "${used}MB" \
        --arg available "${available}MB" \
        --arg percent "${percent}%" \
        --arg peak "${peak}MB" \
        '{
            total: $total,
            used: $used,
            available: $available,
            percent: $percent,
            peak: $peak
        }'
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

    echo "$count"
}

get_workflows_stats() {
    local total active failed paused

    if docker exec n8n n8n export:workflow --all --output=- 2>/dev/null | jq -e '.' >/dev/null; then
        total=$(docker exec n8n n8n export:workflow --all --output=- 2>/dev/null | jq 'length' || echo 0)
        active=$(docker exec n8n n8n export:workflow --all --output=- 2>/dev/null | jq '[.[] | select(.active == true)] | length' || echo 0)
        failed=$(docker exec n8n n8n export:workflow --all --output=- 2>/dev/null | jq '[.[] | select(.active == false)] | length' || echo 0)
        paused=$((active - failed))
    else
        total=0
        active=0
        failed=0
        paused=0
    fi

    jq -n \
        --arg total "$total" \
        --arg active "$active" \
        --arg failed "$failed" \
        --arg paused "$paused" \
        '{
            total: $total,
            active: $active,
            failed: $failed,
            paused: $paused
        }'
}

get_error_count() {
    local error_log="${SCRIPT_DIR}/../.alerts/error_count.log"
    local today
    today=$(date +%Y-%m-%d)

    if [ -f "$error_log" ]; then
        grep "$today" "$error_log" | wc -l
    else
        echo 0
    fi
}

get_container_status() {
    local running stopped restarting total
    running=$(docker ps --format "{{.Names}}" | wc -l | tr -d ' ')
    stopped=$(docker ps -a --filter "status=exited" --format "{{.Names}}" | wc -l | tr -d ' ')
    restarting=$(docker ps -a --filter "status=restarting" --format "{{.Names}}" | wc -l | tr -d ' ')
    total=$(docker ps -a --format "{{.Names}}" | wc -l | tr -d ' ')

    jq -n \
        --arg running "$running" \
        --arg stopped "$stopped" \
        --arg restarting "$restarting" \
        --arg total "$total" \
        '{
            running: $running,
            stopped: $stopped,
            restarting: $restarting,
            total: $total
        }'
}

get_postgres_stats() {
    local cache_ratio connections
    cache_ratio=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT ROUND((sum(blks_hit)::numeric / NULLIF(sum(blks_hit) + sum(blks_read), 0)) * 100, 2)
        FROM pg_stat_database;
    " 2>/dev/null | awk '{print $1}' || echo "N/A")

    connections=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT COUNT(*) FROM pg_stat_activity;
    " 2>/dev/null | awk '{print $1}' || echo "N/A")

    jq -n \
        --arg cache "$cache_ratio" \
        --arg connections "$connections" \
        '{
            cache_hit_ratio: $cache,
            active_connections: $connections
        }'
}

get_redis_stats() {
    local memory_keys
    memory=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" INFO memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r' || echo "N/A")
    keys=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" DBSIZE 2>/dev/null || echo "N/A")

    jq -n \
        --arg memory "$memory" \
        --arg keys "$keys" \
        '{
            memory_usage: $memory,
            total_keys: $keys
        }'
}

get_alert_count() {
    local alert_log="${SCRIPT_DIR}/../.alerts/alert_history.log"
    local today
    today=$(date +%Y-%m-%d)

    if [ -f "$alert_log" ]; then
        local total critical warning
        total=$(grep "$today" "$alert_log" | wc -l | tr -d ' ')
        critical=$(grep "$today.*CRITICAL" "$alert_log" | wc -l | tr -d ' ')
        warning=$(grep "$today.*WARNING" "$alert_log" | wc -l | tr -d ' ')

        jq -n \
            --arg total "$total" \
            --arg critical "$critical" \
            --arg warning "$warning" \
            '{
                total: $total,
                critical: $critical,
                warning: $warning
            }'
    else
        jq -n '{total: 0, critical: 0, warning: 0}'
    fi
}

format_telegram_report() {
    local date hostname uptime memory lead_count workflows containers postgres redis errors alerts

    date=$(date +'%Y-%m-%d')
    hostname=$(hostname)
    uptime=$(calculate_uptime)

    memory=$(get_memory_stats)
    lead_count=$(get_lead_count)
    workflows=$(get_workflows_stats)
    containers=$(get_container_status)
    postgres=$(get_postgres_stats)
    redis=$(get_redis_stats)
    errors=$(get_error_count)
    alerts=$(get_alert_count)

    local report
    report="<b>📊 Daily Health Report</b>
<b>Date:</b> $date
<b>Server:</b> $hostname

<b>⏱️ Uptime:</b> $uptime

<b>💾 Memory:</b>
  Used: $(echo "$memory" | jq -r '.used') / $(echo "$memory" | jq -r '.total') ($(echo "$memory" | jq -r '.percent'))
  Available: $(echo "$memory" | jq -r '.available')
  Peak Today: $(echo "$memory" | jq -r '.peak')

<b>👥 Leads:</b> $lead_count

<b>⚙️ Workflows:</b>
  Total: $(echo "$workflows" | jq -r '.total')
  Active: $(echo "$workflows" | jq -r '.active')
  Failed: $(echo "$workflows" | jq -r '.failed')
  Paused: $(echo "$workflows" | jq -r '.paused')

<b>🐳 Containers:</b>
  Running: $(echo "$containers" | jq -r '.running')/$(echo "$containers" | jq -r '.total')
  Stopped: $(echo "$containers" | jq -r '.stopped')
  Restarting: $(echo "$containers" | jq -r '.restarting')

<b>🗄️ PostgreSQL:</b>
  Cache Hit Ratio: $(echo "$postgres" | jq -r '.cache_hit_ratio')
  Active Connections: $(echo "$postgres" | jq -r '.active_connections')

<b>📦 Redis:</b>
  Memory Usage: $(echo "$redis" | jq -r '.memory_usage')
  Total Keys: $(echo "$redis" | jq -r '.total_keys')

<b>❌ Errors Today:</b> $errors

<b>⚠️ Alerts Today:</b>
  Total: $(echo "$alerts" | jq -r '.total')
  Critical: $(echo "$alerts" | jq -r '.critical')
  Warning: $(echo "$alerts" | jq -r '.warning')
"

    echo "$report"
}

send_report_telegram() {
    local report="$1"

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Telegram credentials not configured"
        return 1
    fi

    curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${report}" \
        -d parse_mode="HTML" >/dev/null || {
        echo "Failed to send Telegram report"
        return 1
    }

    echo "Report sent via Telegram"
}

save_report_log() {
    local report="$1"
    local report_file="${SCRIPT_DIR}/../.alerts/reports/$(date +%Y-%m-%d).txt"

    mkdir -p "$(dirname "$report_file")"
    echo "$report" > "$report_file"

    echo "Report saved to $report_file"
}

main() {
    local report
    report=$(format_telegram_report)

    echo "$report"
    echo ""

    save_report_log "$report"

    case "${1:-}" in
        telegram)
            send_report_telegram "$report"
            ;;
        email)
            echo "Email reports not yet implemented"
            ;;
        both)
            send_report_telegram "$report"
            echo "Email reports not yet implemented"
            ;;
        *)
            echo "Usage: $0 {telegram|email|both}"
            exit 1
            ;;
    esac
}

main "$@"
