#!/bin/bash
# GCP Instance Recovery Script
# Run this inside the GCP instance via browser SSH

set -e

echo "🚑 GCP Instance Recovery & Docker Restart"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# 1. System Health Check
echo "📊 System Health Check"
echo "----------------------"
echo "Uptime: $(uptime)"
echo ""
echo "Memory:"
free -h
echo ""
echo "Disk:"
df -h /
echo ""

# 2. Check Docker
echo "🐳 Docker Status"
echo "----------------"
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not installed!"
    exit 1
fi

if ! $SUDO docker ps &> /dev/null; then
    echo "⚠️  Docker daemon not running, starting..."
    $SUDO systemctl start docker
    sleep 3
fi

echo "✅ Docker is running"
echo ""

# 3. Navigate to project
PROJECT_DIR="/opt/vorzimmerdrache"
if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

cd "$PROJECT_DIR"
echo "📁 Working directory: $(pwd)"
echo ""

# 4. Check existing containers
echo "🔍 Current Docker Containers"
echo "----------------------------"
$SUDO docker compose ps
echo ""

# 5. Stop and remove old containers
echo "🛑 Stopping existing containers..."
$SUDO docker compose down
echo ""

# 6. Pull latest images
echo "📥 Pulling latest images..."
$SUDO docker compose pull
echo ""

# 7. Start fresh containers
echo "🚀 Starting fresh containers..."
$SUDO docker compose up -d
echo ""

# 8. Wait for containers to initialize
echo "⏳ Waiting for containers to initialize (30s)..."
sleep 30
echo ""

# 9. Check container status
echo "✅ Container Status"
echo "-------------------"
$SUDO docker compose ps
echo ""

# 10. Check n8n logs
echo "📋 n8n Logs (last 20 lines)"
echo "---------------------------"
$SUDO docker compose logs --tail=20 n8n
echo ""

# 11. Check Traefik logs
echo "📋 Traefik Logs (last 20 lines)"
echo "--------------------------------"
$SUDO docker compose logs --tail=20 traefik | grep -i -E "certificate|error|warn" || echo "No errors in Traefik logs"
echo ""

# 12. Test n8n availability
echo "🔗 Testing n8n Availability"
echo "---------------------------"
if curl -s -o /dev/null -w "%{http_code}" http://localhost:5678 | grep -q "200\|302"; then
    echo "✅ n8n is responding on localhost:5678"
else
    echo "⚠️  n8n not responding yet (may need more time)"
fi
echo ""

# 13. DuckDNS Update
echo "🦆 DuckDNS Update"
echo "-----------------"
if [ -f ".env" ]; then
    TOKEN=$(grep DUCKDNS_TOKEN .env | cut -d= -f2)
    DOMAIN=$(grep DOMAIN .env | cut -d= -f2 | cut -d. -f1)

    if [ "$TOKEN" != "your-duckdns-token-here" ] && [ -n "$TOKEN" ]; then
        RESULT=$(curl -s "https://www.duckdns.org/update?domains=$DOMAIN&token=$TOKEN&ip=&verbose=true")
        echo "DuckDNS Result: $RESULT"
    else
        echo "⚠️  DuckDNS token not configured"
    fi
fi
echo ""

# 14. Final Status
echo "✅ Recovery Complete!"
echo "===================="
echo ""
echo "Next Steps:"
echo "1. Access n8n UI: https://instance1.duckdns.org"
echo "2. Import workflows from backend/workflows/"
echo "3. Configure credentials (Google Sheets, Twilio, Telegram)"
echo "4. Activate workflows"
echo ""
echo "Troubleshooting:"
echo "- Check logs: docker compose logs -f"
echo "- Restart specific service: docker compose restart n8n"
echo "- Full restart: docker compose down && docker compose up -d"
