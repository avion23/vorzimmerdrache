#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

SYSTEMD_DIR="${SCRIPT_DIR}/systemd"
mkdir -p "$SYSTEMD_DIR"

create_monitor_service() {
    cat > "${SYSTEMD_DIR}/vps-monitor.service" << 'EOF'
[Unit]
Description=VPS Memory Monitor
After=docker.service
Requires=docker.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/vorzimmerdrache/scripts
ExecStart=/opt/vorzimmerdrache/scripts/monitor.sh
Restart=always
RestartSec=30
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    echo "Created vps-monitor.service"
}

create_auto_recovery_service() {
    cat > "${SYSTEMD_DIR}/vps-auto-recovery.service" << 'EOF'
[Unit]
Description=VPS Auto Recovery
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/vorzimmerdrache/scripts
ExecStart=/opt/vorzimmerdrache/scripts/auto-recovery.sh run-all

[Install]
WantedBy=multi-user.target
EOF

    cat > "${SYSTEMD_DIR}/vps-auto-recovery.timer" << 'EOF'
[Unit]
Description=Run VPS Auto Recovery every 5 minutes

[Timer]
OnCalendar=*:0/5
Persistent=true

[Install]
WantedBy=timers.target
EOF

    echo "Created vps-auto-recovery.service and timer"
}

create_daily_report_timer() {
    cat > "${SYSTEMD_DIR}/vps-daily-report.service" << 'EOF'
[Unit]
Description=VPS Daily Health Report
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/vorzimmerdrache/scripts
ExecStart=/opt/vorzimmerdrache/scripts/daily-report.sh telegram

[Install]
WantedBy=multi-user.target
EOF

    cat > "${SYSTEMD_DIR}/vps-daily-report.timer" << 'EOF'
[Unit]
Description=Run VPS Daily Health Report at 8:00 AM daily

[Timer]
OnCalendar=*-*-* 08:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

    echo "Created vps-daily-report.service and timer"
}

create_metrics_exporter_service() {
    cat > "${SYSTEMD_DIR}/vps-metrics-exporter.service" << 'EOF'
[Unit]
Description=VPS Metrics Exporter
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=root
WorkingDirectory=/opt/vorzimmerdrache/scripts
ExecStart=/opt/vorzimmerdrache/scripts/metrics-exporter.sh export

[Install]
WantedBy=multi-user.target
EOF

    cat > "${SYSTEMD_DIR}/vps-metrics-exporter.timer" << 'EOF'
[Unit]
Description=Run VPS Metrics Exporter every 60 seconds

[Timer]
OnCalendar=*:0/1
Persistent=true

[Install]
WantedBy=timers.target
EOF

    echo "Created vps-metrics-exporter.service and timer"
}

install_services() {
    echo "Installing systemd services..."

    sudo cp "${SYSTEMD_DIR}"/*.service /etc/systemd/system/
    sudo cp "${SYSTEMD_DIR}"/*.timer /etc/systemd/system/

    sudo systemctl daemon-reload

    sudo systemctl enable vps-monitor.service
    sudo systemctl start vps-monitor.service

    sudo systemctl enable vps-auto-recovery.timer
    sudo systemctl start vps-auto-recovery.timer

    sudo systemctl enable vps-daily-report.timer
    sudo systemctl start vps-daily-report.timer

    sudo systemctl enable vps-metrics-exporter.timer
    sudo systemctl start vps-metrics-exporter.timer

    echo "Services installed and started!"
}

show_status() {
    echo ""
    echo "Service Status:"
    echo "==============="
    sudo systemctl status vps-monitor.service --no-pager | head -10
    echo ""
    sudo systemctl list-timers "vps-*" --no-pager
}

main() {
    create_monitor_service
    create_auto_recovery_service
    create_daily_report_timer
    create_metrics_exporter_service

    case "${1:-}" in
        install)
            install_services
            show_status
            ;;
        status)
            show_status
            ;;
        uninstall)
            echo "Uninstalling services..."
            sudo systemctl disable --now vps-monitor.service
            sudo systemctl disable --now vps-auto-recovery.timer
            sudo systemctl disable --now vps-daily-report.timer
            sudo systemctl disable --now vps-metrics-exporter.timer
            sudo rm /etc/systemd/system/vps-*.service /etc/systemd/system/vps-*.timer
            sudo systemctl daemon-reload
            echo "Services uninstalled"
            ;;
        *)
            echo "Usage: $0 {install|status|uninstall}"
            exit 1
            ;;
    esac
}

main "$@"
