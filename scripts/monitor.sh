#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALERT_STATE_DIR="${SCRIPT_DIR}/../.alerts"
STATE_FILE="${ALERT_STATE_DIR}/alert_state.json"
CONFIG_FILE="${SCRIPT_DIR}/monitor.conf"

mkdir -p "$ALERT_STATE_DIR"

[ -f "$CONFIG_FILE" ] || {
    cat > "$CONFIG_FILE" << 'EOF'
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

MEMORY_PRESSURE_THRESHOLD=80
POSTGRES_CACHE_THRESHOLD=90
SWAP_THRESHOLD_MB=2048
ALERT_RATE_LIMIT_SEC=600
MEMORY_CRITICAL_MB=50
MEMORY_WARNING_MB=100
DISK_WARNING_PCT=80
DISK_CRITICAL_PCT=90

ENABLE_AUTO_RECOVERY=true
ESSENTIAL_CONTainers="postgres,redis,n8n,waha,traefik"
EOF
}

source "$CONFIG_FILE"

log() {
    echo -e "\033[0;32m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

warn() {
    echo -e "\033[0;33m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

alert() {
    echo -e "\033[0;31m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

colorize() {
    local severity="$1"
    local message="$2"
    case "$severity" in
        CRITICAL) echo -e "\033[0;31m${message}\033[0m" ;;
        WARNING) echo -e "\033[0;33m${message}\033[0m" ;;
        INFO) echo -e "\033[0;36m${message}\033[0m" ;;
        OK) echo -e "\033[0;32m${message}\033[0m" ;;
        *) echo "$message" ;;
    esac
}

init_alert_state() {
    [ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"
}

check_rate_limit() {
    local alert_key="$1"
    local current_time
    current_time=$(date +%s)
    local last_sent

    last_sent=$(jq -r ".[\"$alert_key\"] // 0" "$STATE_FILE" 2>/dev/null || echo 0)
    local time_diff=$((current_time - last_sent))

    if [ "$time_diff" -lt "$ALERT_RATE_LIMIT_SEC" ]; then
        return 1
    fi

    jq ".[\"$alert_key\"] = $current_time" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
    return 0
}

send_telegram_alert() {
    local severity="$1"
    local message="$2"

    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && return 0

    local alert_key="${severity}:${message%% *}"
    check_rate_limit "$alert_key" || return 0

    local emoji
    case "$severity" in
        CRITICAL) emoji="🚨" ;;
        WARNING) emoji="⚠️" ;;
        INFO) emoji="ℹ️" ;;
    esac

    local hostname
    hostname=$(hostname)
    local formatted_message="${emoji} <b>${severity}</b> - ${hostname}
${message}"

    curl -s -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d chat_id="${TELEGRAM_CHAT_ID}" \
        -d text="${formatted_message}" \
        -d parse_mode="HTML" >/dev/null || true
}

get_memory_pressure() {
    local pressure_file="/proc/pressure/memory"

    if [ ! -f "$pressure_file" ]; then
        echo "0"
        return
    fi

    local some_avg
    some_avg=$(awk 'NR==1 {gsub(/[^0-9.]/, "", $2); print $2}' "$pressure_file")
    local full_avg
    full_avg=$(awk 'NR==1 {gsub(/[^0-9.]/, "", $4); print $4}' "$pressure_file")

    local score
    score=$(awk "BEGIN {printf \"%.0f\", ($some_avg + $full_avg) * 50}")

    echo "$score"
}

check_memory_pressure() {
    local pressure
    pressure=$(get_memory_pressure)
    local severity="OK"
    local message="Memory pressure: ${pressure}%"

    if [ "$pressure" -gt "$MEMORY_PRESSURE_THRESHOLD" ]; then
        severity="CRITICAL"
        alert "$(colorize CRITICAL "$message")"
        send_telegram_alert "CRITICAL" "$message"
    elif [ "$pressure" -gt 60 ]; then
        severity="WARNING"
        warn "$(colorize WARNING "$message")"
        send_telegram_alert "WARNING" "$message"
    else
        log "$(colorize OK "$message")"
    fi

    echo "PRESSURE: ${pressure}%"
}

check_oom_kills() {
    local oom_detected=false
    local oom_output

    oom_output=$(dmesg -T | grep -i "Out of memory\|Kill process" | tail -10 || true)

    if [ -n "$oom_output" ]; then
        oom_detected=true
    fi

    if $oom_detected; then
        alert "$(colorize CRITICAL "OOM kills detected!")"
        echo "OOM: DETECTED"
        send_telegram_alert "CRITICAL" "OOM kills detected. Check dmesg for details."
        echo "$oom_output" | head -5
    else
        log "$(colorize OK "No OOM kills detected")"
        echo "OOM: OK"
    fi
}

get_postgres_cache_ratio() {
    docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c "
        SELECT
            ROUND(
                (sum(blks_hit)::numeric / NULLIF(sum(blks_hit) + sum(blks_read), 0)) * 100,
                2
            ) AS cache_hit_ratio
        FROM pg_stat_database
   ;" 2>/dev/null | awk '{print $1}' || echo "N/A"
}

check_postgres_cache() {
    local cache_ratio
    cache_ratio=$(get_postgres_cache_ratio)

    if [ "$cache_ratio" = "N/A" ]; then
        warn "PostgreSQL cache ratio: N/A (container not ready)"
        echo "POSTGRES: N/A"
        return
    fi

    local severity="OK"
    local message="PostgreSQL cache hit ratio: ${cache_ratio}%"

    if (( $(echo "$cache_ratio < $POSTGRES_CACHE_THRESHOLD" | bc -l) )); then
        severity="WARNING"
        warn "$(colorize WARNING "$message")"
        send_telegram_alert "WARNING" "$message"
    else
        log "$(colorize OK "$message")"
    fi

    echo "POSTGRES: ${cache_ratio}%"
}

get_swap_rates() {
    local swapin_prev swapout_prev swapin_cur swapout_cur
    local prev_file="/tmp/swap_stats_prev"

    if [ -f "$prev_file" ]; then
        read -r swapin_prev swapout_prev < "$prev_file"
    else
        swapin_prev=0
        swapout_prev=0
    fi

    read -r swapin_cur swapout_cur < <(grep -E '^swapin|^swapout' /proc/vmstat | awk '{print $2}')

    echo "$swapin_cur $swapout_cur" > "$prev_file"

    local swapin_rate swapout_rate time_diff
    time_diff=30
    swapin_rate=$(( (swapin_cur - swapin_prev) / time_diff ))
    swapout_rate=$(( (swapout_cur - swapout_prev) / time_diff ))

    echo "$swapin_rate $swapout_rate"
}

check_swap_rates() {
    local swapin_rate swapout_rate used_mb total_mb
    read -r swapin_rate swapout_rate < <(get_swap_rates)
    read -r total_mb used_mb < <(free -m | awk '/^Swap:/ {print $2, $3}')

    local severity="OK"
    local message="Swap: ${used_mb}MB used (in: ${swapin_rate}KB/s, out: ${swapout_rate}KB/s)"

    if [ "$used_mb" -gt "$SWAP_THRESHOLD_MB" ]; then
        severity="CRITICAL"
        alert "$(colorize CRITICAL "$message")"
        send_telegram_alert "CRITICAL" "$message"
    elif [ "$used_mb" -gt 1024 ] || [ "$swapin_rate" -gt 1000 ]; then
        severity="WARNING"
        warn "$(colorize WARNING "$message")"
        send_telegram_alert "WARNING" "$message"
    else
        log "$(colorize OK "$message")"
    fi

    echo "SWAP: ${used_mb}MB/${total_mb}MB (in: ${swapin_rate}KB/s, out: ${swapout_rate}KB/s)"
}

check_memory() {
    local total available used percent
    read -r total available < <(free -m | awk '/^Mem:/ {print $2, $7}')
    used=$((total - available))
    percent=$((used * 100 / total))

    local severity="OK"
    local message="RAM: ${used}MB/${total}MB (${percent}%)"

    if [ "$available" -lt "$MEMORY_CRITICAL_MB" ]; then
        severity="CRITICAL"
        alert "$(colorize CRITICAL "$message - ${available}MB available")"
        send_telegram_alert "CRITICAL" "$message - ${available}MB available"
    elif [ "$available" -lt "$MEMORY_WARNING_MB" ]; then
        severity="WARNING"
        warn "$(colorize WARNING "$message - ${available}MB available")"
        send_telegram_alert "WARNING" "$message - ${available}MB available"
    else
        log "$(colorize OK "$message")"
    fi

    echo "RAM: ${used}MB/${total}MB (${percent}%)"
}

check_disk() {
    local usage
    usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

    local severity="OK"
    local message="DISK: ${usage}% used"

    if [ "$usage" -gt "$DISK_CRITICAL_PCT" ]; then
        severity="CRITICAL"
        alert "$(colorize CRITICAL "$message")"
        send_telegram_alert "CRITICAL" "$message"
    elif [ "$usage" -gt "$DISK_WARNING_PCT" ]; then
        severity="WARNING"
        warn "$(colorize WARNING "$message")"
        send_telegram_alert "WARNING" "$message"
    else
        log "$(colorize OK "$message")"
    fi

    echo "DISK: ${usage}% used"
}

check_containers() {
    log "Container Memory Usage:"

    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}" 2>/dev/null || {
        echo "Docker not running"
        return 1
    }

    local restarting
    restarting=$(docker ps -a --filter "status=restarting" --format "{{.Names}}" 2>/dev/null || true)

    if [ -n "$restarting" ]; then
        alert "$(colorize CRITICAL "Containers in restart loop: $restarting")"
        send_telegram_alert "CRITICAL" "Containers in restart loop: $restarting"
    fi
}

get_container_memory() {
    docker stats --no-stream --format "{{.Name}}\t{{.MemUsage}}" 2>/dev/null || true
}

print_summary_header() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                    VPS MEMORY MONITOR                         ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

main() {
    init_alert_state
    print_summary_header

    log "System Health Check"
    echo ""

    check_memory_pressure
    check_oom_kills
    check_postgres_cache
    check_swap_rates
    check_memory
    check_disk

    echo ""
    check_containers

    log "Press Ctrl+C to exit, monitoring every 30s..."

    if [ "${1:-}" != "--once" ]; then
        while true; do
            sleep 30
            echo ""
            print_summary_header
            log "=== $(date +'%Y-%m-%d %H:%M:%S') ==="
            echo ""
            check_memory_pressure || true
            check_oom_kills || true
            check_postgres_cache || true
            check_swap_rates || true
            check_memory || true
            check_disk || true
            check_containers || true
        done
    fi
}

main "$@"
