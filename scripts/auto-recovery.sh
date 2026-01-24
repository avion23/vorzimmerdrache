#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_LOG="${SCRIPT_DIR}/../.alerts/recovery.log"
CONFIG_FILE="${SCRIPT_DIR}/monitor.conf"

mkdir -p "$(dirname "$RECOVERY_LOG")"
source "$CONFIG_FILE" 2>/dev/null || true

log_recovery() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$RECOVERY_LOG"
}

check_waha_sessions() {
    local stuck_sessions=()
    local timeout_hours=1

    log_recovery "Checking Waha sessions for stuck state..."

    local sessions
    sessions=$(docker exec waha ls /app/.sessions 2>/dev/null || true)

    for session in $sessions; do
        local session_file="/app/.sessions/${session}/session.json"
        if docker exec waha test -f "$session_file" 2>/dev/null; then
            local last_modified
            last_modified=$(docker exec waha stat -c %Y "$session_file" 2>/dev/null || echo 0)
            local current_time
            current_time=$(date +%s)
            local age_hours=$(( (current_time - last_modified) / 3600 ))

            if [ "$age_hours" -gt "$timeout_hours" ]; then
                stuck_sessions+=("$session (stuck for ${age_hours}h)")
            fi
        fi
    done

    if [ ${#stuck_sessions[@]} -gt 0 ]; then
        log_recovery "Stuck Waha sessions detected: ${stuck_sessions[*]}"
        return 1
    fi

    return 0
}

restart_waha_container() {
    local reason="${1:-Stuck session detected}"

    log_recovery "Restarting Waha container: $reason"

    docker restart waha 2>/dev/null || {
        log_recovery "Failed to restart Waha container"
        return 1
    }

    sleep 10

    if docker ps | grep -q "waha.*Up"; then
        log_recovery "Waha container restarted successfully"
        return 0
    else
        log_recovery "Waha container failed to start after restart"
        return 1
    fi
}

check_n8n_queue() {
    local max_queue_size=1000

    log_recovery "Checking n8n queue size..."

    local queue_size
    queue_size=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LLEN "bull:n8n:wait" 2>/dev/null || echo "0")

    if [ "$queue_size" -gt "$max_queue_size" ]; then
        log_recovery "n8n queue overflow: ${queue_size} jobs pending"
        return 1
    fi

    return 0
}

pause_low_priority_workflows() {
    local high_priority_threshold=500

    log_recovery "Checking workflow priority..."

    local queue_size
    queue_size=$(docker exec redis redis-cli -a "${REDIS_PASSWORD}" LLEN "bull:n8n:wait" 2>/dev/null || echo "0")

    if [ "$queue_size" -gt "$high_priority_threshold" ]; then
        log_recovery "Queue size critical: ${queue_size} - Pausing low-priority workflows"

        docker exec n8n n8n export:workflow --all --output=/tmp/workflows.json 2>/dev/null || true

        local paused_count=0
        local workflow_ids
        workflow_ids=$(docker exec n8n n8n export:workflow --all --output=- 2>/dev/null | jq -r '.[].id' | head -10 || true)

        for id in $workflow_ids; do
            docker exec n8n n8n workflow:activate --id="$id" --pause 2>/dev/null && ((paused_count++)) || true
        done

        log_recovery "Paused ${paused_count} low-priority workflows"
    fi
}

check_swap_thrashing() {
    local swapin_threshold=5000

    local swapin_rate swapout_rate
    read -r swapin_rate swapout_rate < <(
        if [ -f /tmp/swap_stats_prev ]; then
            read -r swapin_prev swapout_prev < /tmp/swap_stats_prev
        else
            swapin_prev=0
            swapout_prev=0
        fi

        read -r swapin_cur swapout_cur < <(grep -E '^swapin|^swapout' /proc/vmstat | awk '{print $2}')
        echo "$swapin_cur $swapout_cur" > /tmp/swap_stats_prev

        echo "$(( (swapin_cur - swapin_prev) / 30 )) $(( (swapout_cur - swapout_prev) / 30 ))"
    )

    if [ "$swapin_rate" -gt "$swapin_threshold" ]; then
        log_recovery "Swap thrashing detected: ${swapin_rate}KB/s swap-in"
        return 1
    fi

    return 0
}

kill_non_essential_containers() {
    local essential_containers="${ESSENTIAL_CONTAINERS:-postgres,redis,n8n,waha,traefik}"

    log_recovery "Killing non-essential containers due to swap thrashing"

    local non_essential=()
    local container_names
    container_names=$(docker ps --format "{{.Names}}")

    for container in $container_names; do
        if [[ ! ",${essential_containers}," == *",${container},"* ]]; then
            non_essential+=("$container")
        fi
    done

    for container in "${non_essential[@]}"; do
        log_recovery "Stopping non-essential container: $container"
        docker stop "$container" 2>/dev/null || true
    done

    log_recovery "Stopped ${#non_essential[@]} non-essential containers"
}

detect_container_restart_loops() {
    local restart_threshold=5
    local time_window_sec=300

    log_recovery "Checking for container restart loops..."

    local looping_containers=()
    local container_names
    container_names=$(docker ps --format "{{.Names}}")

    for container in $container_names; do
        local restart_count
        restart_count=$(docker inspect -f '{{.RestartCount}}' "$container" 2>/dev/null || echo 0)

        if [ "$restart_count" -gt "$restart_threshold" ]; then
            looping_containers+=("$container (${restart_count} restarts)")
        fi
    done

    if [ ${#looping_containers[@]} -gt 0 ]; then
        log_recovery "Containers in restart loop: ${looping_containers[*]}"
        return 1
    fi

    return 0
}

handle_container_loop() {
    local container="$1"

    log_recovery "Handling restart loop for container: $container"

    local restart_count
    restart_count=$(docker inspect -f '{{.RestartCount}}' "$container" 2>/dev/null || echo 0)

    if [ "$restart_count" -gt 10 ]; then
        log_recovery "Container $container has too many restarts. Stopping."
        docker stop "$container" 2>/dev/null || true
        return 1
    fi

    local logs
    logs=$(docker logs --tail 50 "$container" 2>/dev/null || true)

    if echo "$logs" | grep -qi "out of memory\|killed process"; then
        log_recovery "Container $container killed by OOM. Adjusting limits..."
        docker update --memory-reservation="512m" "$container" 2>/dev/null || true
        docker restart "$container" 2>/dev/null || true
    else
        log_recovery "Container $container generic restart"
        docker restart "$container" 2>/dev/null || true
    fi
}

run_recovery_checks() {
    local recovery_performed=false

    log_recovery "Starting auto-recovery checks..."

    if check_waha_sessions; then
        log_recovery "Waha sessions OK"
    else
        if [ "${ENABLE_AUTO_RECOVERY:-false}" = "true" ]; then
            restart_waha_container "Stuck session detected"
            recovery_performed=true
        fi
    fi

    if check_n8n_queue; then
        log_recovery "n8n queue OK"
    else
        if [ "${ENABLE_AUTO_RECOVERY:-false}" = "true" ]; then
            pause_low_priority_workflows
            recovery_performed=true
        fi
    fi

    if check_swap_thrashing; then
        log_recovery "Swap activity OK"
    else
        if [ "${ENABLE_AUTO_RECOVERY:-false}" = "true" ]; then
            kill_non_essential_containers
            recovery_performed=true
        fi
    fi

    if detect_container_restart_loops; then
        log_recovery "Container restart status OK"
    else
        if [ "${ENABLE_AUTO_RECOVERY:-false}" = "true" ]; then
            local looping_containers
            looping_containers=$(docker ps --format "{{.Names}}" | while read -r c; do
                local rc
                rc=$(docker inspect -f '{{.RestartCount}}' "$c" 2>/dev/null || echo 0)
                if [ "$rc" -gt 5 ]; then
                    echo "$c"
                fi
            done)

            for container in $looping_containers; do
                handle_container_loop "$container"
            done
            recovery_performed=true
        fi
    fi

    if $recovery_performed; then
        log_recovery "Recovery actions performed"
        return 0
    else
        log_recovery "No recovery needed"
        return 1
    fi
}

main() {
    case "${1:-}" in
        check-waha)
            check_waha_sessions
            ;;
        restart-waha)
            restart_waha_container "${2:-Manual trigger}"
            ;;
        check-queue)
            check_n8n_queue
            ;;
        check-swap)
            check_swap_thrashing
            ;;
        check-loops)
            detect_container_restart_loops
            ;;
        run-all)
            run_recovery_checks
            ;;
        *)
            echo "Usage: $0 {check-waha|restart-waha|check-queue|check-swap|check-loops|run-all}"
            exit 1
            ;;
    esac
}

main "$@"
