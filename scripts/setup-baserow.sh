#!/bin/bash

set -e

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
BASEROW_VERSION="1.24.0"
BASEROW_PORT=8000
BASEROW_ADMIN_EMAIL=""
BASEROW_ADMIN_PASSWORD=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Setup Baserow integration for the CRM.

Options:
    --email EMAIL      Admin email for Baserow
    --password PASS    Admin password for Baserow
    --help             Show this help message

This script will:
  1. Add Baserow service to docker-compose.yml
  2. Initialize Baserow database tables
  3. Generate API token
  4. Configure webhooks to n8n

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --email)
                BASEROW_ADMIN_EMAIL="$2"
                shift 2
                ;;
            --password)
                BASEROW_ADMIN_PASSWORD="$2"
                shift 2
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

check_prerequisites() {
    if [[ ! -f "$COMPOSE_FILE" ]]; then
        echo -e "${RED}Error: $COMPOSE_FILE not found${NC}"
        exit 1
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${RED}Error: $ENV_FILE not found${NC}"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker not installed${NC}"
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl not installed${NC}"
        exit 1
    fi
}

prompt_credentials() {
    if [[ -z "$BASEROW_ADMIN_EMAIL" ]]; then
        read -p "Enter Baserow admin email: " BASEROW_ADMIN_EMAIL
    fi

    if [[ -z "$BASEROW_ADMIN_PASSWORD" ]]; then
        read -s -p "Enter Baserow admin password: " BASEROW_ADMIN_PASSWORD
        echo
    fi

    if [[ -z "$BASEROW_ADMIN_EMAIL" ]] || [[ -z "$BASEROW_ADMIN_PASSWORD" ]]; then
        echo -e "${RED}Error: Email and password are required${NC}"
        exit 1
    fi
}

add_baserow_to_compose() {
    echo -e "${BLUE}Adding Baserow to docker-compose.yml...${NC}"

    if grep -q "baserow:" "$COMPOSE_FILE"; then
        echo -e "${YELLOW}Baserow service already exists in docker-compose.yml${NC}"
        return
    fi

    local baserow_service="
  baserow:
    image: baserow/baserow:$BASEROW_VERSION
    container_name: baserow
    restart: unless-stopped
    environment:
      BASEROW_PUBLIC_URL: \${BASEROW_PUBLIC_URL:-http://localhost:8000}
      DATABASE_HOST: postgres
      DATABASE_NAME: \${POSTGRES_DB:-n8n}
      DATABASE_USER: \${POSTGRES_USER:-n8n}
      DATABASE_PASSWORD: \${POSTGRES_PASSWORD}
      REDIS_HOST: redis
      REDIS_PORT: 6379
      REDIS_PASSWORD: \${REDIS_PASSWORD}
      BASEROW_JWT_SIGNING_KEY: \${BASEROW_JWT_SIGNING_KEY}
      BASEROW_WEBHOOKS_ALLOW_PRIVATE_ADDRESS: 'true'
    volumes:
      - baserow_data:/baserow/data
    networks:
      - backend
      - frontend
    labels:
      - \"traefik.enable=true\"
      - \"traefik.http.routers.baserow.rule=Host(\`\${BASEROW_HOST:-baserow.\${DOMAIN}}\`)\"
      - \"traefik.http.routers.baserow.entrypoints=websecure\"
      - \"traefik.http.routers.baserow.tls=true\"
      - \"traefik.http.routers.baserow.tls.certresolver=letsencrypt\"

"

    local volume_entry="  baserow_data:"

    if grep -q "volumes:" "$COMPOSE_FILE"; then
        sed -i.bak "/^volumes:/a\\$volume_entry" "$COMPOSE_FILE"
    else
        echo "$volume_entry" >> "$COMPOSE_FILE"
    fi

    sed -i.bak "/^  backup:/i\\$baserow_service" "$COMPOSE_FILE"
    rm -f "${COMPOSE_FILE}.bak"

    echo -e "${GREEN}Added Baserow service to docker-compose.yml${NC}"
}

generate_jwt_key() {
    if ! grep -q "BASEROW_JWT_SIGNING_KEY" "$ENV_FILE"; then
        local jwt_key=$(openssl rand -hex 32)
        echo "BASEROW_JWT_SIGNING_KEY=$jwt_key" >> "$ENV_FILE"
        echo -e "${GREEN}Generated BASEROW_JWT_SIGNING_KEY${NC}"
    fi

    if ! grep -q "BASEROW_HOST" "$ENV_FILE"; then
        local domain=$(grep "^DOMAIN=" "$ENV_FILE" | cut -d'=' -f2)
        if [[ -n "$domain" ]]; then
            echo "BASEROW_HOST=baserow.$domain" >> "$ENV_FILE"
        else
            echo "BASEROW_HOST=baserow.localhost" >> "$ENV_FILE"
        fi
    fi

    if ! grep -q "BASEROW_PUBLIC_URL" "$ENV_FILE"; then
        local baserow_host=$(grep "^BASEROW_HOST=" "$ENV_FILE" | cut -d'=' -f2)
        echo "BASEROW_PUBLIC_URL=https://$baserow_host" >> "$ENV_FILE"
    fi
}

wait_for_baserow() {
    echo -e "${BLUE}Waiting for Baserow to be ready...${NC}"

    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if curl -f -s "http://localhost:$BASEROW_PORT/api/health/" &> /dev/null; then
            echo -e "${GREEN}Baserow is ready${NC}"
            return
        fi

        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done

    echo -e "\n${RED}Timeout waiting for Baserow${NC}"
    exit 1
}

create_admin_user() {
    echo -e "${BLUE}Creating admin user...${NC}"

    local response=$(curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/user/" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Admin\",
            \"email\": \"$BASEROW_ADMIN_EMAIL\",
            \"password\": \"$BASEROW_ADMIN_PASSWORD\",
            \"authenticate\": true
        }")

    if echo "$response" | grep -q "token"; then
        echo -e "${GREEN}Admin user created successfully${NC}"
        echo "$response" | jq -r '.token' > /tmp/baserow_token.txt
    else
        echo -e "${YELLOW}Admin user may already exist, attempting login...${NC}"

        local login_response=$(curl -s -X POST \
            "http://localhost:$BASEROW_PORT/api/user/token-auth/" \
            -H "Content-Type: application/json" \
            -d "{
                \"email\": \"$BASEROW_ADMIN_EMAIL\",
                \"password\": \"$BASEROW_ADMIN_PASSWORD\"
            }")

        if echo "$login_response" | grep -q "token"; then
            echo -e "${GREEN}Admin login successful${NC}"
            echo "$login_response" | jq -r '.token' > /tmp/baserow_token.txt
        else
            echo -e "${RED}Failed to create or login admin user${NC}"
            echo "Response: $login_response"
            exit 1
        fi
    fi
}

create_workspace() {
    echo -e "${BLUE}Creating workspace...${NC}"

    local token=$(cat /tmp/baserow_token.txt)

    local response=$(curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/workspaces/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "CRM"
        }')

    local workspace_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$workspace_id" ]]; then
        echo -e "${GREEN}Workspace created (ID: $workspace_id)${NC}"
        echo "$workspace_id" > /tmp/baserow_workspace_id.txt
    else
        echo -e "${YELLOW}Workspace may already exist, checking...${NC}"

        local workspaces=$(curl -s -X GET \
            "http://localhost:$BASEROW_PORT/api/workspaces/" \
            -H "Authorization: Token $token")

        workspace_id=$(echo "$workspaces" | jq -r '.[] | select(.name=="CRM") | .id')

        if [[ -n "$workspace_id" ]]; then
            echo -e "${GREEN}Found existing workspace (ID: $workspace_id)${NC}"
            echo "$workspace_id" > /tmp/baserow_workspace_id.txt
        else
            echo -e "${RED}Failed to create or find workspace${NC}"
            exit 1
        fi
    fi
}

create_database() {
    echo -e "${BLUE}Creating database...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local workspace_id=$(cat /tmp/baserow_workspace_id.txt)

    local response=$(curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/applications/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Leads\",
            \"type\": \"database\",
            \"workspace\": $workspace_id
        }")

    local database_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$database_id" ]]; then
        echo -e "${GREEN}Database created (ID: $database_id)${NC}"
        echo "$database_id" > /tmp/baserow_database_id.txt
    else
        echo -e "${YELLOW}Database may already exist, checking...${NC}"

        local apps=$(curl -s -X GET \
            "http://localhost:$BASEROW_PORT/api/applications/" \
            -H "Authorization: Token $token")

        database_id=$(echo "$apps" | jq -r ".[] | select(.name==\"Leads\" and .workspace_id==$workspace_id) | .id")

        if [[ -n "$database_id" ]]; then
            echo -e "${GREEN}Found existing database (ID: $database_id)${NC}"
            echo "$database_id" > /tmp/baserow_database_id.txt
        else
            echo -e "${RED}Failed to create or find database${NC}"
            exit 1
        fi
    fi
}

create_leads_table() {
    echo -e "${BLUE}Creating leads table...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local database_id=$(cat /tmp/baserow_database_id.txt)

    local response=$(curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/tables/database/$database_id/table/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "Leads"
        }')

    local table_id=$(echo "$response" | jq -r '.id // empty')

    if [[ -n "$table_id" ]]; then
        echo -e "${GREEN}Table created (ID: $table_id)${NC}"
        echo "$table_id" > /tmp/baserow_table_id.txt
    else
        echo -e "${YELLOW}Table may already exist, checking...${NC}"

        local tables=$(curl -s -X GET \
            "http://localhost:$BASEROW_PORT/api/database/tables/database/$database_id/tables/" \
            -H "Authorization: Token $token")

        table_id=$(echo "$tables" | jq -r ".[] | select(.name==\"Leads\") | .id")

        if [[ -n "$table_id" ]]; then
            echo -e "${GREEN}Found existing table (ID: $table_id)${NC}"
            echo "$table_id" > /tmp/baserow_table_id.txt
        else
            echo -e "${RED}Failed to create or find table${NC}"
            exit 1
        fi
    fi
}

create_fields() {
    echo -e "${BLUE}Creating table fields...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local table_id=$(cat /tmp/baserow_table_id.txt)

    local fields=(
        '{"name":"ID","type":"text","primary":true}'
        '{"name":"Created At","type":"date","date_include_time":true}'
        '{"name":"Name","type":"text"}'
        '{"name":"Phone","type":"text"}'
        '{"name":"Email","type":"text"}'
        '{"name":"Address","type":"text"}'
        '{"name":"City","type":"text"}'
        '{"name":"Postal Code","type":"text"}'
        '{"name":"State","type":"text"}'
        '{"name":"Latitude","type":"number","number_decimal_places":8}'
        '{"name":"Longitude","type":"number","number_decimal_places":8}'
        '{"name":"Status","type":"single_select"}'
        '{"name":"Priority","type":"number","number_negative":false}'
        '{"name":"Opted In","type":"boolean"}'
        '{"name":"Opted Out","type":"boolean"}'
        '{"name":"Roof Area (sqm)","type":"number","number_negative":false}'
        '{"name":"Estimated kWp","type":"number","number_decimal_places":2}'
        '{"name":"Estimated Annual kWh","type":"number","number_negative":false}'
        '{"name":"Subsidy Eligible","type":"boolean"}'
        '{"name":"Source","type":"text"}'
        '{"name":"Notes","type":"long_text"}'
        '{"name":"Assigned To","type":"text"}'
        '{"name":"Meeting Date","type":"date","date_include_time":true}'
        '{"name":"Attachments","type":"file"}'
    )

    for field_json in "${fields[@]}"; do
        local response=$(curl -s -X POST \
            "http://localhost:$BASEROW_PORT/api/database/fields/table/$table_id/" \
            -H "Authorization: Token $token" \
            -H "Content-Type: application/json" \
            -d "$field_json")

        local field_id=$(echo "$response" | jq -r '.id // empty')
        local field_name=$(echo "$field_json" | jq -r '.name')

        if [[ -n "$field_id" ]]; then
            echo -e "${GREEN}Created field: $field_name${NC}"
        else
            echo -e "${YELLOW}Field may already exist: $field_name${NC}"
        fi
    done

    echo -e "${BLUE}Setting status options...${NC}"

    local status_field_id=$(curl -s -X GET \
        "http://localhost:$BASEROW_PORT/api/database/fields/table/$table_id/" \
        -H "Authorization: Token $token" | jq -r ".[] | select(.name==\"Status\") | .id")

    local status_options=(
        '{"value":"new","color":"blue"}'
        '{"value":"qualified","color":"green"}'
        '{"value":"contacted","color":"orange"}'
        '{"value":"meeting","color":"purple"}'
        '{"value":"offer","color":"cyan"}'
        '{"value":"won","color":"dark-green"}'
        '{"value":"lost","color":"red"}'
    )

    for option_json in "${status_options[@]}"; do
        curl -s -X POST \
            "http://localhost:$BASEROW_PORT/api/database/fields/select-options/" \
            -H "Authorization: Token $token" \
            -H "Content-Type: application/json" \
            -d "$option_json" > /dev/null
    done

    echo -e "${GREEN}Status options configured${NC}"
}

create_api_token() {
    echo -e "${BLUE}Creating API token...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local database_id=$(cat /tmp/baserow_database_id.txt)

    local response=$(curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/tokens/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Sync Token\",
            \"permissions\": \"create,read,update\"
        }")

    local api_token=$(echo "$response" | jq -r '.key // empty')

    if [[ -n "$api_token" ]]; then
        echo -e "${GREEN}API token created${NC}"
        echo "BASEROW_API_TOKEN=$api_token" >> "$ENV_FILE"
        echo "$api_token" > /tmp/baserow_api_token.txt
    else
        echo -e "${YELLOW}Checking for existing token...${NC}"

        local tokens=$(curl -s -X GET \
            "http://localhost:$BASEROW_PORT/api/database/tokens/" \
            -H "Authorization: Token $token")

        api_token=$(echo "$tokens" | jq -r '.[] | select(.name=="Sync Token") | .key')

        if [[ -n "$api_token" ]]; then
            echo -e "${GREEN}Found existing API token${NC}"
            echo "BASEROW_API_TOKEN=$api_token" >> "$ENV_FILE"
            echo "$api_token" > /tmp/baserow_api_token.txt
        else
            echo -e "${RED}Failed to create API token${NC}"
            exit 1
        fi
    fi
}

create_webhook() {
    echo -e "${BLUE}Creating webhook...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local table_id=$(cat /tmp/baserow_table_id.txt)
    local webhook_url=$(grep "^WEBHOOK_URL=" "$ENV_FILE" | cut -d'=' -f2)/webhook/baserow

    curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/webhooks/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"table_id\": $table_id,
            \"url\": \"$webhook_url\",
            \"events\": [\"rows.created\", \"rows.updated\", \"rows.deleted\"],
            \"headers\": {},
            \"request_method\": \"POST\",
            \"include_all\": true
        }" > /dev/null

    echo -e "${GREEN}Webhook configured to: $webhook_url${NC}"
}

configure_views() {
    echo -e "${BLUE}Configuring views...${NC}"

    local token=$(cat /tmp/baserow_token.txt)
    local table_id=$(cat /tmp/baserow_table_id.txt)
    local status_field_id=$(curl -s -X GET \
        "http://localhost:$BASEROW_PORT/api/database/fields/table/$table_id/" \
        -H "Authorization: Token $token" | jq -r ".[] | select(.name==\"Status\") | .id")
    local meeting_date_field_id=$(curl -s -X GET \
        "http://localhost:$BASEROW_PORT/api/database/fields/table/$table_id/" \
        -H "Authorization: Token $token" | jq -r ".[] | select(.name==\"Meeting Date\") | .id")

    curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/views/table/$table_id/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Lead Pipeline\",
            \"type\": \"kanban\",
            \"card_cover_image_field\": null,
            \"options\": {\"field_options\":{}},
            \"kanban_view_field_id\": $status_field_id
        }" > /dev/null

    curl -s -X POST \
        "http://localhost:$BASEROW_PORT/api/database/views/table/$table_id/" \
        -H "Authorization: Token $token" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"Termine\",
            \"type\": \"calendar\",
            \"date_field_id\": $meeting_date_field_id
        }" > /dev/null

    echo -e "${GREEN}Views configured (Kanban + Calendar)${NC}"
}

print_summary() {
    echo -e "\n${BLUE}=== Baserow Setup Complete ===${NC}"
    echo -e "${GREEN}✓${NC} Baserow service added to docker-compose.yml"
    echo -e "${GREEN}✓${NC} Database tables created"
    echo -e "${GREEN}✓${NC} API token generated and saved to .env"
    echo -e "${GREEN}✓${NC} Webhook configured to n8n"
    echo -e "${GREEN}✓${NC} Views configured (Kanban + Calendar)"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Start the stack: docker-compose up -d"
    echo "2. Access Baserow at: http://localhost:8000 (or your BASEROW_HOST)"
    echo "3. Login with: $BASEROW_ADMIN_EMAIL"
    echo "4. Start sync: npm run sync:baserow:daemon"
    echo ""
}

main() {
    parse_args "$@"
    check_prerequisites
    prompt_credentials

    add_baserow_to_compose
    generate_jwt_key

    echo -e "${BLUE}Starting Baserow container...${NC}"
    docker-compose up -d baserow

    wait_for_baserow
    create_admin_user
    create_workspace
    create_database
    create_leads_table
    create_fields
    create_api_token
    create_webhook
    configure_views

    print_summary
}

main "$@"
