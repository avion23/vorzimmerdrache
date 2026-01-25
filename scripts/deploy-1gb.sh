#!/bin/bash
set -e

SERVER="${1:-ralf_waldukat@instance1.duckdns.org}"
DOMAIN="${2:-instance1.duckdns.org}"

echo "🚀 Deploying Vorzimmerdrache (1GB Ultra-Light)..."
echo "Server: $SERVER"
echo "Domain: $DOMAIN"
echo ""

ssh "$SERVER" bash <<EOF
set -e

# Create directory
mkdir -p /opt/vorzimmerdrache
cd /opt/vorzimmerdrache

# Generate .env if not exists
if [ ! -f .env ]; then
  cat > .env <<ENVEOF
SSL_EMAIL=admin@${DOMAIN}
DOMAIN=${DOMAIN}
N8N_ENCRYPTION_KEY=\$(openssl rand -hex 32)
ENVEOF
  echo "✓ Generated .env file"
fi

# Create letsencrypt directory
mkdir -p letsencrypt

echo "📦 Pulling Docker images..."
docker pull traefik:v2.10
docker pull docker.n8n.io/n8nio/n8n

echo "🛑 Stopping existing containers..."
docker compose down 2>/dev/null || true

echo "🚀 Starting services..."
docker compose up -d

echo ""
echo "⏳ Waiting for n8n to start (30s)..."
sleep 30

echo ""
echo "✓ Deployment complete!"
echo ""
echo "Access: https://${DOMAIN}/"
echo "Next:"
echo "  1. Configure Twilio credentials in n8n UI"
echo "  2. Import roof-mode workflow"
echo "  3. Setup Google Sheets API node"
echo "  4. Update .env with your values"
echo ""

docker compose ps
EOF
