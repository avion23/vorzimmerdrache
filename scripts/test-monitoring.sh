#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo -e "\033[0;32m[TEST]\033[0m $1"
}

warn() {
    echo -e "\033[0;33m[WARN]\033[0m $1"
}

fail() {
    echo -e "\033[0;31m[FAIL]\033[0m $1"
}

test_bash_syntax() {
    log "Testing bash syntax for all scripts..."
    local scripts=(
        "monitor.sh"
        "auto-recovery.sh"
        "daily-report.sh"
        "metrics-exporter.sh"
        "install-monitoring.sh"
    )

    local all_passed=true
    for script in "${scripts[@]}"; do
        if bash -n "${SCRIPT_DIR}/${script}"; then
            log "✓ $script syntax OK"
        else
            fail "✗ $script syntax error"
            all_passed=false
        fi
    done

    $all_passed || exit 1
}

test_directories() {
    log "Testing directory creation..."

    local dirs=(
        ".alerts"
        ".alerts/metrics"
        ".alerts/reports"
        "systemd"
    )

    for dir in "${dirs[@]}"; do
        local full_path="${SCRIPT_DIR}/../${dir}"
        if mkdir -p "$full_path" 2>/dev/null; then
            log "✓ Directory created: $dir"
        else
            fail "✗ Cannot create directory: $dir"
        fi
    done
}

test_memory_pressure() {
    log "Testing memory pressure detection..."

    if [ -f "/proc/pressure/memory" ]; then
        local pressure
        pressure=$("${SCRIPT_DIR}/metrics-exporter.sh" 2>/dev/null | grep "memory_pressure_score" | awk '{print $2}')
        if [ -n "$pressure" ]; then
            log "✓ Memory pressure: $pressure"
        else
            warn "Could not read memory pressure"
        fi
    else
        warn "PSI not available (kernel < 4.20 or disabled)"
    fi
}

test_container_metrics() {
    log "Testing container metrics..."

    if docker ps >/dev/null 2>&1; then
        if "${SCRIPT_DIR}/metrics-exporter.sh" export 2>/dev/null | grep -q "container_memory_bytes"; then
            log "✓ Container metrics available"
        else
            warn "Could not extract container metrics"
        fi
    else
        warn "Docker not running - container metrics unavailable"
    fi
}

test_alert_config() {
    log "Testing alert configuration..."

    local config_file="${SCRIPT_DIR}/monitor.conf"
    if [ ! -f "$config_file" ]; then
        warn "Config file not found, will create on first run"
        return
    fi

    local required_vars=(
        "TELEGRAM_BOT_TOKEN"
        "TELEGRAM_CHAT_ID"
        "MEMORY_PRESSURE_THRESHOLD"
    )

    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=" "$config_file"; then
            log "✓ Config variable: $var"
        else
            warn "Missing config variable: $var"
        fi
    done
}

test_metrics_export() {
    log "Testing metrics export..."

    local metrics_file="${SCRIPT_DIR}/../.alerts/metrics/test.prom"

    "${SCRIPT_DIR}/metrics-exporter.sh" export > "$metrics_file" 2>/dev/null || true

    if [ -f "$metrics_file" ] && [ -s "$metrics_file" ]; then
        local count
        count=$(grep -c "^#" "$metrics_file" || echo 0)
        local metric_count
        metric_count=$(grep -c "^[a-z_]" "$metrics_file" || echo 0)

        log "✓ Metrics exported: $metric_count metrics, $count comments"
        rm "$metrics_file"
    else
        warn "Metrics export failed or empty"
    fi
}

test_health_report() {
    log "Testing health report generation..."

    local report_file="${SCRIPT_DIR}/../.alerts/reports/test_report.txt"

    "${SCRIPT_DIR}/daily-report.sh" 2>/dev/null | head -20 > "$report_file" || true

    if [ -f "$report_file" ] && [ -s "$report_file" ]; then
        if grep -q "Daily Health Report" "$report_file"; then
            log "✓ Health report generated"
            rm "$report_file"
        else
            warn "Health report format unexpected"
        fi
    else
        warn "Health report generation failed"
    fi
}

test_systemd_templates() {
    log "Testing systemd service templates..."

    local systemd_dir="${SCRIPT_DIR}/systemd"
    mkdir -p "$systemd_dir"

    "${SCRIPT_DIR}/install-monitoring.sh" 2>/dev/null || true

    local services=(
        "vps-monitor.service"
        "vps-auto-recovery.service"
        "vps-daily-report.service"
        "vps-metrics-exporter.service"
    )

    local found=0
    for service in "${services[@]}"; do
        if [ -f "${systemd_dir}/${service}" ]; then
            found=$((found + 1))
        fi
    done

    if [ "$found" -eq "${#services[@]}" ]; then
        log "✓ All systemd services created"
    else
        warn "Only $found/${#services[@]} systemd services created"
    fi
}

print_summary() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║               Monitoring System Test Summary                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Next steps:"
    echo "1. Configure Telegram alerts in scripts/monitor.conf"
    echo "2. Install systemd services: ./scripts/install-monitoring.sh install"
    echo "3. Test monitor: ./scripts/monitor.sh --once"
    echo "4. Check metrics: ./scripts/metrics-exporter.sh export"
    echo ""
    echo "For full documentation, see: scripts/MONITORING.md"
    echo ""
}

main() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║          VPS Monitoring System - Self-Test                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""

    test_bash_syntax
    test_directories
    test_memory_pressure
    test_container_metrics
    test_alert_config
    test_metrics_export
    test_health_report
    test_systemd_templates

    print_summary
}

main "$@"
