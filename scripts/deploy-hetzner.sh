#!/bin/bash
set -euo pipefail

echo "=== Hetzner Cloud Deployment Script ==="
echo ""

COLOR='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${COLOR}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

check_dependencies() {
    log "Checking dependencies..."
    command -v hcloud >/dev/null 2>&1 || { echo "Error: hcloud CLI not installed"; exit 1; }
    command -v ssh >/dev/null 2>&1 || { echo "Error: ssh not installed"; exit 1; }
}

create_server() {
    local SERVER_NAME="${1:-vorzimmerdrache-prod}"
    local SERVER_TYPE="${2:-cx22}"
    local IMAGE="${3:-ubuntu-22.04}"
    local REGION="${4:-nbg1}"
    local SSH_KEY_NAME="${5:-vorzimmerdrache-key}"

    log "Creating Hetzner server..."
    log "Server: $SERVER_NAME"
    log "Type: $SERVER_TYPE"
    log "Region: $REGION"

    hcloud server create \
        --name "$SERVER_NAME" \
        --type "$SERVER_TYPE" \
        --image "$IMAGE" \
        --location "$REGION" \
        --ssh-key "$SSH_KEY_NAME" \
        --enable-firewall \
        --firewall=vorzimmerdrache-firewall || {
            log "Server creation failed or already exists"
            return 1
        }

    SERVER_IP=$(hcloud server ip "$SERVER_NAME")
    log "Server created. IP: $SERVER_IP"
    echo "$SERVER_IP"
}

setup_firewall() {
    log "Setting up firewall rules..."
    
    hcloud firewall create --name vorzimmerdrache-firewall || log "Firewall already exists"

    cat > /tmp/firewall-rules.json <<EOF
[
  {
    "description": "SSH",
    "direction": "in",
    "port": "22",
    "protocol": "tcp",
    "source_ips": ["0.0.0.0/0"]
  },
  {
    "description": "HTTP",
    "direction": "in",
    "port": "80",
    "protocol": "tcp",
    "source_ips": ["0.0.0.0/0"]
  },
  {
    "description": "HTTPS",
    "direction": "in",
    "port": "443",
    "protocol": "tcp",
    "source_ips": ["0.0.0.0/0"]
  },
  {
    "description": "Allow all outbound",
    "direction": "out",
    "port": "any",
    "protocol": "any",
    "source_ips": ["0.0.0.0/0"]
  }
]
EOF

    hcloud firewall add-rule vorzimmerdrache-firewall --description "SSH" --direction in --port 22 --protocol tcp --source-ips 0.0.0.0/0
    hcloud firewall add-rule vorzimmerdrache-firewall --description "HTTP" --direction in --port 80 --protocol tcp --source-ips 0.0.0.0/0
    hcloud firewall add-rule vorzimmerdrache-firewall --description "HTTPS" --direction in --port 443 --protocol tcp --source-ips 0.0.0.0/0
    hcloud firewall add-rule vorzimmerdrache-firewall --description "Outbound" --direction out --port any --protocol any --source-ips 0.0.0.0/0

    log "Firewall rules configured"
}

wait_for_server() {
    local SERVER_IP=$1
    local MAX_ATTEMPTS=30
    local ATTEMPT=0

    log "Waiting for server to be ready..."
    while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 root@$SERVER_IP echo "ready" >/dev/null 2>&1; then
            log "Server is ready!"
            return 0
        fi
        ATTEMPT=$((ATTEMPT + 1))
        echo -n "."
        sleep 10
    done
    echo ""
    log "Timeout waiting for server"
    return 1
}

deploy_stack() {
    local SERVER_IP=$1

    log "Deploying stack to server..."

    ssh root@$SERVER_IP bash -s << 'ENDSSH'
set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Updating system..."
apt-get update -qq
apt-get upgrade -y -qq

log "Installing dependencies..."
apt-get install -y -qq curl git ufw fail2ban

log "Installing Docker..."
curl -fsSL https://get.docker.com | sh
usermod -aG docker $USER

log "Installing Docker Compose..."
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

log "Configuring firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

log "Setting up swap..."
fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl vm.swappiness=10

log "Creating application directory..."
mkdir -p /opt/vorzimmerdrache
mkdir -p /opt/vorzimmerdrache/backups

log "Optimizing kernel parameters..."
cat >> /etc/sysctl.conf <<EOF
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
vm.overcommit_memory=1
EOF
sysctl -p

log "Server setup complete!"
ENDSSH

    log "Copying files to server..."
    scp -r docker-compose.yml .env.example root@$SERVER_IP:/opt/vorzimmerdrache/
    ssh root@$SERVER_IP "cd /opt/vorzimmerdrache && cp .env.example .env && echo 'Please edit /opt/vorzimmerdrache/.env with your actual values'"

    log "Starting services..."
    ssh root@$SERVER_IP "cd /opt/vorzimmerdrache && docker-compose up -d"

    log "Deployment complete!"
}

setup_ssh_key() {
    local KEY_NAME="${1:-vorzimmerdrache-key}"
    local SSH_KEY_PATH="${2:-$HOME/.ssh/id_ed25519.pub}"

    if [ ! -f "$SSH_KEY_PATH" ]; then
        log "SSH key not found at $SSH_KEY_PATH"
        log "Generate one with: ssh-keygen -t ed25519 -C 'hetzner'"
        return 1
    fi

    log "Adding SSH key to Hetzner..."
    hcloud ssh-key create --name "$KEY_NAME" --public-key-from-file "$SSH_KEY_PATH" || log "SSH key already exists"
}

cleanup() {
    log "Deployment interrupted. Cleaning up..."
    exit 1
}

main() {
    trap cleanup INT TERM

    check_dependencies

    echo ""
    read -p "Create new SSH key? (y/N): " CREATE_KEY
    if [[ "$CREATE_KEY" =~ ^[Yy]$ ]]; then
        read -p "SSH key name [vorzimmerdrache-key]: " KEY_NAME
        KEY_NAME=${KEY_NAME:-vorzimmerdrache-key}
        read -p "Path to SSH public key [$HOME/.ssh/id_ed25519.pub]: " SSH_KEY_PATH
        SSH_KEY_PATH=${SSH_KEY_PATH:-$HOME/.ssh/id_ed25519.pub}
        setup_ssh_key "$KEY_NAME" "$SSH_KEY_PATH"
    fi

    setup_firewall

    read -p "Server name [vorzimmerdrache-prod]: " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-vorzimmerdrache-prod}

    read -p "Server type [cx22-4vcpu-8gb]: " SERVER_TYPE
    SERVER_TYPE=${SERVER_TYPE:-cx22}

    read -p "Region [nbg1]: " REGION
    REGION=${REGION:-nbg1}

    SERVER_IP=$(create_server "$SERVER_NAME" "$SERVER_TYPE" "ubuntu-22.04" "$REGION")

    wait_for_server "$SERVER_IP"

    deploy_stack "$SERVER_IP"

    log ""
    log "=== Deployment Summary ==="
    log "Server: $SERVER_NAME"
    log "IP: $SERVER_IP"
    log "Access: ssh root@$SERVER_IP"
    log "n8n: https://$(grep N8N_HOST .env.example | cut -d= -f2)"
    log "Dashboard: https://$(grep DOMAIN .env.example | cut -d= -f2 | sed 's/^/traefik./')"
    log "Monitoring: https://$(grep DOMAIN .env.example | cut -d= -f2 | sed 's/^/uptime./')"
    log ""
    log "Next steps:"
    log "1. Edit /opt/vorzimmerdrache/.env with actual values"
    log "2. Set up DNS A records pointing to $SERVER_IP"
    log "3. Restart stack: ssh root@$SERVER_IP 'cd /opt/vorzimmerdrache && docker-compose restart'"
}

main "$@"
