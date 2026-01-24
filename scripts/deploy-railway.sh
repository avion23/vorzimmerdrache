#!/bin/bash
set -euo pipefail

echo "=== Railway Deployment Script ==="
echo ""

COLOR='\033[0;32m'
NC='\033[0m'

log() {
    echo -e "${COLOR}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

check_dependencies() {
    log "Checking dependencies..."
    command -v railway >/dev/null 2>&1 || { 
        log "Railway CLI not installed"
        log "Install with: npm install -g @railway/cli"
        exit 1
    }
}

login() {
    log "Authenticating with Railway..."
    railway login || {
        log "Authentication failed"
        exit 1
    }
}

create_project() {
    local PROJECT_NAME="${1:-vorzimmerdrache}"

    log "Creating Railway project..."
    railway init --name "$PROJECT_NAME" || log "Project already exists or in existing project"
}

create_postgres() {
    log "Creating PostgreSQL service..."
    railway add postgres || log "PostgreSQL service already exists"
}

create_redis() {
    log "Creating Redis service..."
    railway add redis || log "Redis service already exists"
}

create_n8n() {
    log "Creating n8n service..."

    cat > railway.n8n.json <<EOF
{
  "name": "n8n",
  "image": "n8nio/n8n:latest",
  "environment": [
    {
      "key": "N8N_HOST",
      "value": "\${{RAILWAY_PUBLIC_DOMAIN}}"
    },
    {
      "key": "N8N_PORT",
      "value": "5678"
    },
    {
      "key": "N8N_PROTOCOL",
      "value": "https"
    },
    {
      "key": "N8N_ENCRYPTION_KEY",
      "value": "\${{N8N_ENCRYPTION_KEY}}"
    },
    {
      "key": "WEBHOOK_URL",
      "value": "https://\${{RAILWAY_PUBLIC_DOMAIN}}"
    },
    {
      "key": "DB_TYPE",
      "value": "postgresdb"
    },
    {
      "key": "DB_POSTGRESDB_HOST",
      "value": "\${{POSTGRES_HOST}}"
    },
    {
      "key": "DB_POSTGRESDB_PORT",
      "value": "\${{POSTGRES_PORT}}"
    },
    {
      "key": "DB_POSTGRESDB_DATABASE",
      "value": "\${{POSTGRES_DB}}"
    },
    {
      "key": "DB_POSTGRESDB_USER",
      "value": "\${{POSTGRES_USER}}"
    },
    {
      "key": "DB_POSTGRESDB_PASSWORD",
      "value": "\${{POSTGRES_PASSWORD}}"
    },
    {
      "key": "REDIS_HOST",
      "value": "\${{REDIS_HOST}}"
    },
    {
      "key": "REDIS_PORT",
      "value": "\${{REDIS_PORT}}"
    },
    {
      "key": "REDIS_PASSWORD",
      "value": "\${{REDIS_PASSWORD}}"
    }
  ]
}
EOF

    railway add -s n8n || log "n8n service already exists"
}

create_waha() {
    log "Creating Waha WhatsApp API service..."

    cat > railway.waha.json <<EOF
{
  "name": "waha",
  "image": "devlikeapro/waha:latest",
  "environment": [
    {
      "key": "WHATSAPP_HOOK_URL",
      "value": "https://\${{n8n.RAILWAY_PUBLIC_DOMAIN}}/webhook/whatsapp"
    },
    {
      "key": "WHATSAPP_HOOK_EVENTS",
      "value": "message,session.status"
    },
    {
      "key": "WHATSAPP_REDIS_ENABLED",
      "value": "true"
    },
    {
      "key": "WHATSAPP_REDIS_HOST",
      "value": "\${{REDIS_HOST}}"
    },
    {
      "key": "WHATSAPP_REDIS_PORT",
      "value": "\${{REDIS_PORT}}"
    },
    {
      "key": "WAHA_API_KEY",
      "value": "\${{WAHA_API_TOKEN}}"
    }
  ]
}
EOF

    railway add -s waha || log "Waha service already exists"
}

configure_monitoring() {
    log "Setting up monitoring..."
    log "Railway includes built-in metrics. Access via dashboard."
    log "For uptime monitoring, consider external services like UptimeRobot or Better Uptime."
}

set_variables() {
    log "Configuring environment variables..."

    log "Please set the following variables in Railway dashboard:"
    echo ""
    echo "N8N_ENCRYPTION_KEY: $(openssl rand -hex 32)"
    echo "N8N_BASIC_AUTH_USER: admin"
    echo "N8N_BASIC_AUTH_PASSWORD: <your-password>"
    echo ""
    echo "TWILIO_ACCOUNT_SID: <your-sid>"
    echo "TWILIO_AUTH_TOKEN: <your-token>"
    echo "TWILIO_PHONE_NUMBER: <your-number>"
    echo ""
    echo "OPENAI_API_KEY: <your-key> or GEMINI_API_KEY: <your-key>"
    echo ""
    echo "GOOGLE_SHEETS_ID: <sheet-id>"
    echo "GOOGLE_SERVICE_ACCOUNT_JSON: <service-account-json>"
    echo "GOOGLE_MAPS_API_KEY: <your-key>"
    echo ""
    echo "WAHA_API_TOKEN: $(openssl rand -hex 32)"
    echo "INSTALLER_PHONE_NUMBER: <your-number>"
    echo ""
    echo "Or set via CLI: railway variables set NAME=VALUE"
}

deploy() {
    log "Deploying to Railway..."
    railway up
    log "Deployment complete!"
}

setup_backup() {
    log "Setting up backup strategy..."
    log "Railway provides automatic backups for PostgreSQL:"
    log "- Daily snapshots retained for 7 days"
    log "- Weekly snapshots retained for 4 weeks"
    log "- Monthly snapshots retained for 12 months"
    log ""
    log "For n8n workflows, export regularly:"
    log "1. Go to n8n UI > Settings > Export Workflows"
    log "2. Download and store locally"
    log "3. Commit to git repository"
}

main() {
    check_dependencies
    login

    echo ""
    read -p "Project name [vorzimmerdrache]: " PROJECT_NAME
    PROJECT_NAME=${PROJECT_NAME:-vorzimmerdrache}

    create_project "$PROJECT_NAME"
    create_postgres
    create_redis
    create_n8n
    create_waha
    configure_monitoring
    set_variables
    setup_backup

    echo ""
    read -p "Deploy now? (y/N): " DEPLOY_NOW
    if [[ "$DEPLOY_NOW" =~ ^[Yy]$ ]]; then
        deploy
    fi

    log ""
    log "=== Railway Deployment Summary ==="
    log "Project: $PROJECT_NAME"
    log "Dashboard: https://railway.app/project/$PROJECT_NAME"
    log ""
    log "Next steps:"
    log "1. Set environment variables in Railway dashboard"
    log "2. Set up custom domain for n8n"
    log "3. Configure Waha webhook URL with n8n domain"
    log "4. Test services via Railway dashboard"
}

main "$@"
