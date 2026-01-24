#!/bin/bash
set -euo pipefail

LOG_DIR="${1:-/var/log/vorzimmerdrache}"
MAX_SIZE="${2:-100M}"
DAYS="${3:-7}"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

compress_old_logs() {
    log "Compressing logs older than 1 day..."
    find "$LOG_DIR" -name "*.log" -mtime +1 -not -name "*.gz" -exec gzip {} \;
}

remove_old_logs() {
    log "Removing logs older than $DAYS days..."
    find "$LOG_DIR" -name "*.log.gz" -mtime +$DAYS -delete
    find "$LOG_DIR" -name "*.log" -mtime +$DAYS -delete
}

rotate_docker_logs() {
    log "Rotating Docker logs..."

    for container in $(docker ps --format '{{.Names}}'); do
        local log_file="$LOG_DIR/${container}.log"
        docker logs --tail 10000 "$container" > "$log_file" 2>/dev/null || true
        docker inspect --format='{{.LogPath}}' "$container" 2>/dev/null | xargs truncate -s 0 2>/dev/null || true
    done
}

clean_large_files() {
    log "Checking for large files..."

    find "$LOG_DIR" -type f -size +$MAX_SIZE -exec sh -c '
        file="$1"
        size=$(du -h "$file" | cut -f1)
        echo "Large file: $file ($size)"
        gzip "$file" 2>/dev/null || true
    ' _ {} \;
}

cleanup_temp_files() {
    log "Cleaning temporary files..."

    find /tmp -name "docker-*" -mtime +1 -delete 2>/dev/null || true
    find /var/tmp -name "docker-*" -mtime +1 -delete 2>/dev/null || true
}

show_summary() {
    log "=== Cleanup Summary ==="
    log "Log directory: $LOG_DIR"
    log "Log retention: $DAYS days"
    log "Max file size: $MAX_SIZE"
    log ""
    log "Disk usage:"
    du -sh "$LOG_DIR" 2>/dev/null || echo "Directory empty"
    log ""
    log "Log files:"
    ls -lh "$LOG_DIR" 2>/dev/null | tail -n +2 || echo "No log files"
}

main() {
    log "=== Log Rotation Script ==="

    rotate_docker_logs
    compress_old_logs
    remove_old_logs
    clean_large_files
    cleanup_temp_files
    show_summary

    log "Cleanup complete"
}

main "$@"
