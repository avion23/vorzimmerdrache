#!/bin/bash
set -euo pipefail

log() {
    echo -e "\033[0;32m[$(date +'%Y-%m-%d %H:%M:%S')]\033[0m $1"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        log "Please run as root"
        exit 1
    fi
}

configure_swap() {
    log "Configuring 4GB swap..."

    if swapon --show | grep -q '/swapfile'; then
        log "Swap already configured"
    else
        dd if=/dev/zero of=/swapfile bs=1M count=4096 status=progress
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl vm.vfs_cache_pressure=75
    echo 'vm.vfs_cache_pressure=75' >> /etc/sysctl.conf

    if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
        echo 'never' > /sys/kernel/mm/transparent_hugepage/enabled
        echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled' >> /etc/rc.local
        chmod +x /etc/rc.local 2>/dev/null || true
    fi
}

install_docker() {
    log "Installing Docker..."

    if ! command -v docker >/dev/null 2>&1; then
        apt-get update -qq
        apt-get install -y -qq ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
            tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update -qq
        apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    systemctl start docker
    systemctl enable docker
}

setup_user() {
    local USER="${1:-$SUDO_USER}"
    if [ -n "$USER" ]; then
        usermod -aG docker "$USER"
        log "Added $USER to docker group"
    fi
}

deploy_repo() {
    local REPO_URL="${1}"
    local DEPLOY_DIR="${2:-/opt/vorzimmerdrache}"
    local USER="${3:-$SUDO_USER}"

    log "Deploying repository..."

    apt-get install -y -qq git htop

    if [ -d "$DEPLOY_DIR/.git" ]; then
        cd "$DEPLOY_DIR"
        git pull
    else
        git clone "$REPO_URL" "$DEPLOY_DIR"
    fi

    if [ ! -f "$DEPLOY_DIR/.env" ] && [ -f "$DEPLOY_DIR/.env.example" ]; then
        cp "$DEPLOY_DIR/.env.example" "$DEPLOY_DIR/.env"

        if [ -n "$USER" ]; then
            chown -R "$USER:$USER" "$DEPLOY_DIR"
        fi
    fi

    if [ -f "$DEPLOY_DIR/.env" ]; then
        sed -i "s/<generate-32-char-random-key>/$(openssl rand -hex 32)/g" "$DEPLOY_DIR/.env"
        sed -i "s/<strong-password>/$(openssl rand -base64 24)/g" "$DEPLOY_DIR/.env"
        sed -i "s/<strong-db-password>/$(openssl rand -base64 24)/g" "$DEPLOY_DIR/.env"
        sed -i "s/<strong-redis-password>/$(openssl rand -base64 24)/g" "$DEPLOY_DIR/.env"
        sed -i "s/<generate-random-api-token>/$(openssl rand -hex 32)/g" "$DEPLOY_DIR/.env"

        log "Generated secure keys"
    fi
}

validate_env() {
    local DEPLOY_DIR="${1:-/opt/vorzimmerdrache}"
    local ENV_FILE="$DEPLOY_DIR/.env"

    if [ ! -f "$ENV_FILE" ]; then
        log "Error: .env file not found"
        return 1
    fi

    local REQUIRED_VARS=(
        "N8N_HOST"
        "POSTGRES_PASSWORD"
        "REDIS_PASSWORD"
        "N8N_ENCRYPTION_KEY"
    )

    for var in "${REQUIRED_VARS[@]}"; do
        if grep -q "^${var}=" "$ENV_FILE" | grep -q '<'; then
            log "Warning: $var contains placeholder value"
        fi
    done
}

start_services() {
    local DEPLOY_DIR="${1:-/opt/vorzimmerdrache}"

    log "Starting services..."

    cd "$DEPLOY_DIR"

    if [ -f "docker-compose-low-memory.yml" ]; then
        docker compose -f docker-compose-low-memory.yml up -d
    else
        docker compose up -d
    fi

    log "Waiting for services to be healthy..."
    sleep 30

    docker compose ps
}

create_systemd_service() {
    local DEPLOY_DIR="${1:-/opt/vorzimmerdrache}"
    local USER="${2:-root}"

    cat > /etc/systemd/system/vorzimmerdrache.service <<EOF
[Unit]
Description=Vorzimmerdrache Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$DEPLOY_DIR
ExecStart=/usr/bin/docker compose -f $DEPLOY_DIR/docker-compose-low-memory.yml up -d
ExecStop=/usr/bin/docker compose -f $DEPLOY_DIR/docker-compose-low-memory.yml down
TimeoutStartSec=0
User=$USER

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable vorzimmerdrache.service
    log "Created systemd service"
}

setup_log_rotation() {
    cat > /etc/logrotate.d/vorzimmerdrache <<EOF
/var/log/vorzimmerdrache/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
    sharedscripts
    postrotate
        docker compose -f /opt/vorzimmerdrache/docker-compose-low-memory.yml logs --tail=0 > /dev/null
    endscript
}
EOF

    log "Configured log rotation"
}

show_status() {
    log "=== Deployment Status ==="
    free -h
    echo ""
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    log "Memory usage:"
    docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}"
}

main() {
    check_root

    log "=== VPS Deployment Script for 1GB Instances ==="

    read -p "Repository URL: " REPO_URL
    read -p "Deploy directory [/opt/vorzimmerdrache]: " DEPLOY_DIR
    DEPLOY_DIR=${DEPLOY_DIR:-/opt/vorzimmerdrache}
    read -p "Create systemd service? [Y/n]: " CREATE_SERVICE
    CREATE_SERVICE=${CREATE_SERVICE:-Y}

    configure_swap
    install_docker
    setup_user
    deploy_repo "$REPO_URL" "$DEPLOY_DIR"
    validate_env "$DEPLOY_DIR"
    start_services "$DEPLOY_DIR"

    if [[ "$CREATE_SERVICE" =~ ^[Yy]$ ]]; then
        create_systemd_service "$DEPLOY_DIR"
    fi

    setup_log_rotation
    show_status

    log ""
    log "=== Next Steps ==="
    log "1. Edit $DEPLOY_DIR/.env with your domain and configuration"
    log "2. Set up DNS A records pointing to $(hostname -I | awk '{print $1}')"
    log "3. Restart: docker compose -f $DEPLOY_DIR/docker-compose-low-memory.yml restart"
    log "4. Monitor: bash $DEPLOY_DIR/scripts/monitor.sh"
}

main "$@"
