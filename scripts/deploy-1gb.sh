#!/bin/bash
set -e

echo "🚀 Deploying Vorzimmerdrache (1GB VPS - Twilio Only)..."
echo ""

DOCKER_COMPOSE_FILE="${1:-docker-compose.yml}"

if [ ! -f "$DOCKER_COMPOSE_FILE" ]; then
  echo "❌ Error: $DOCKER_COMPOSE_FILE not found"
  echo "   Run this script from the project root directory"
  exit 1
fi

echo "✓ Using compose file: $DOCKER_COMPOSE_FILE"
echo ""

if ! command -v docker &> /dev/null; then
  echo "📦 Installing Docker..."
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh
  rm get-docker.sh
  usermod -aG docker $USER || true
  echo "✓ Docker installed"
  echo ""
fi

if [ ! -f /swapfile ]; then
  echo "💾 Creating 4GB swap file..."
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "✓ 4GB swap file created and activated"
  echo ""
else
  echo "✓ Swap file already exists"
  echo ""
fi

if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    echo "📝 Creating .env from .env.example..."
    cp .env.example .env
    echo "✓ Created .env file"
    echo "   ⚠️  IMPORTANT: Edit .env and set your actual values!"
    echo ""
  else
    echo "⚠️  Warning: .env.example not found, creating minimal .env..."
    cat > .env <<ENVEOF
DOMAIN=your-domain.com
SSL_EMAIL=your-email@example.com
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=changeme
N8N_HOST=your-domain.com
WEBHOOK_URL=https://your-domain.com/
TWILIO_ACCOUNT_SID=
TWILIO_AUTH_TOKEN=
TWILIO_PHONE_NUMBER=
GOOGLE_SHEETS_ID=
GOOGLE_SERVICE_ACCOUNT_JSON=
GOOGLE_MAPS_API_KEY=
OPENAI_API_KEY=
GEMINI_API_KEY=
INSTALLER_PHONE_NUMBER=
ENVEOF
    echo "✓ Created minimal .env file"
    echo "   ⚠️  IMPORTANT: Edit .env and set your actual values!"
    echo ""
  fi
fi

echo "📦 Pulling Docker images..."
docker compose -f "$DOCKER_COMPOSE_FILE" pull
echo ""

echo "🛑 Stopping existing containers..."
docker compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true
echo ""

echo "🚀 Starting containers..."
docker compose -f "$DOCKER_COMPOSE_FILE" up -d
echo ""

echo "⏳ Waiting for n8n to start (30s)..."
sleep 30
echo ""

echo "📊 Container status:"
docker compose -f "$DOCKER_COMPOSE_FILE" ps
echo ""

if [ -f .env ]; then
  DOMAIN=$(grep "^DOMAIN=" .env | cut -d'=' -f2)
  echo "🌐 Access URL: https://${DOMAIN}/"
else
  echo "🌐 Access URL: https://your-domain.com/"
fi
echo ""

echo "📋 Next Steps:"
echo "  1. Configure Twilio credentials in .env (TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_PHONE_NUMBER)"
echo "  2. Restart containers: docker compose restart"
echo "  3. Create a Google Sheet for data storage"
echo "  4. Configure Google Sheets API credentials in .env"
echo "  5. Import workflows and configure in n8n UI"
echo ""
echo "✓ Deployment complete!"
