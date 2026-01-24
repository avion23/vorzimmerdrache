#!/bin/bash
set -euo pipefail

log() {
    echo -e "\033[0;32m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

warn() {
    echo -e "\033[0;33m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

alert() {
    echo -e "\033[0;31m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

check_swap() {
    local TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
    local USED=$(free -m | awk '/^Swap:/ {print $3}')
    local PERCENT=0

    if [ "$TOTAL" -gt 0 ]; then
        PERCENT=$((USED * 100 / TOTAL))
    fi

    echo "SWAP: ${USED}M/${TOTAL}M (${PERCENT}%)"

    if [ "$PERCENT" -gt 50 ]; then
        warn "High swap usage: ${PERCENT}%"
    fi
}

check_memory() {
    local TOTAL=$(free -m | awk '/^Mem:/ {print $2}')
    local AVAILABLE=$(free -m | awk '/^Mem:/ {print $7}')
    local PERCENT=$(( (TOTAL - AVAILABLE) * 100 / TOTAL ))

    echo "RAM:  $((TOTAL - AVAILABLE))M/${TOTAL}M (${PERCENT}%)"

    if [ "$AVAILABLE" -lt 50 ]; then
        alert "CRITICAL: Low memory - ${AVAILABLE}MB available"
        return 1
    elif [ "$AVAILABLE" -lt 100 ]; then
        warn "WARNING: Low memory - ${AVAILABLE}MB available"
    fi

    return 0
}

check_containers() {
    log "Container Memory Usage:"
    docker stats --no-stream --format "{{.Name}}: {{.MemUsage}} ({{.MemPerc}})" || echo "Docker not running"
}

check_oom() {
    if dmesg | grep -q "Out of memory"; then
        alert "OOM kill detected recently"
        dmesg | grep "Out of memory" | tail -5
        return 1
    fi
}

check_disk() {
    local USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    echo "DISK: ${USAGE}% used"

    if [ "$USAGE" -gt 90 ]; then
        alert "CRITICAL: Disk space low - ${USAGE}% used"
        return 1
    elif [ "$USAGE" -gt 80 ]; then
        warn "WARNING: Disk space low - ${USAGE}% used"
    fi
}

main() {
    log "=== Memory Monitor ==="

    check_memory
    check_swap
    check_disk
    check_oom

    echo ""
    check_containers

    log "Press Ctrl+C to exit, monitoring every 30s..."

    if [ "${1:-}" != "--once" ]; then
        while true; do
            sleep 30
            echo ""
            log "=== $(date) ==="
            check_memory || true
            check_swap
            check_disk
            check_containers
        done
    fi
}

main "$@"
