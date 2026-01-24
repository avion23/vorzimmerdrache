#!/bin/bash

ENV_FILE=".env"

check_dependencies() {
    local missing_deps=()
    
    command -v openssl >/dev/null 2>&1 || missing_deps+=("openssl")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Missing required dependencies: ${missing_deps[*]}"
        echo "Install them with:"
        echo "  sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}"
        exit 1
    fi
}

check_dependencies
AUTO_GEN=0
REQUIRED_VALID=0
REQUIRED_TOTAL=0
OPTIONAL_VALID=0
OPTIONAL_TOTAL=0
ERRORS=0
WARNINGS=0
AUTO_GENERATED=()

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Validate .env file for Vorzimmerdrache deployment.

Options:
    --fix      Auto-generate missing secrets and update .env
    --help     Show this help message

Exit codes:
    0    All required variables valid
    1    Errors found

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --fix)
                AUTO_GEN=1
                shift
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

check_placeholder() {
    local value="$1"
    local name="$2"
    
    if [[ "$value" == "<"*">" ]]; then
        return 0
    fi
    
    if [[ "$value" == your_* ]]; then
        return 0
    fi
    
    local placeholders=(
        "yourdomain.com"
        "your@email.com"
        "ACXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
        "+1234567890"
        "sk-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
        "your_twilio_auth_token"
        "your_gemini_api_key"
        "your-telegram-bot-token-from-botfather"
        "your-secret-token-for-webhook-auth"
        "your-waha-api-token"
        "n8n.yourdomain.com"
        "waha.yourdomain.com"
        "AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX"
        "+49123456789"
        "1BxiMvs0XRA5nFMdKvBdBZjGMUUqptbfsNY8Ux9iJ4gE"
        "123456789"
        "default"
    )
    
    for placeholder in "${placeholders[@]}"; do
        if [[ "$value" == "$placeholder" ]]; then
            return 0
        fi
    done
    
    if [[ "$value" == *"..."* ]]; then
        return 0
    fi
    
    return 1
}

validate_hex_key() {
    local value="$1"
    local min_len="${2:-32}"
    
    if [[ ${#value} -lt $min_len ]]; then
        return 1
    fi
    
    if ! [[ "$value" =~ ^[a-fA-F0-9]+$ ]]; then
        return 1
    fi
    
    return 0
}

validate_e164() {
    local value="$1"
    
    if [[ ! "$value" =~ ^\+[1-9][0-9]{1,14}$ ]]; then
        return 1
    fi
    
    return 0
}

validate_twilio_sid() {
    local value="$1"
    
    if [[ ! "$value" =~ ^AC[a-fA-F0-9]{32}$ ]]; then
        return 1
    fi
    
    return 0
}

validate_telegram_bot_token() {
    local value="$1"
    
    if [[ ! "$value" =~ ^[0-9]{8,10}:[A-Za-z0-9_-]{35}$ ]]; then
        return 1
    fi
    
    return 0
}

validate_telegram_chat_id() {
    local value="$1"
    
    if [[ ! "$value" =~ ^-?[0-9]+$ ]]; then
        return 1
    fi
    
    return 0
}

validate_url() {
    local value="$1"
    local allow_localhost="${2:-false}"
    
    if [[ "$allow_localhost" == "true" ]] && [[ "$value" =~ ^(http://localhost|https://localhost) ]]; then
        return 0
    fi
    
    if [[ ! "$value" =~ ^https://[a-zA-Z0-9.-]+(:[0-9]+)?(/.*)?$ ]]; then
        return 1
    fi
    
    return 0
}

validate_json() {
    local value="$1"
    
    if ! echo "$value" | jq empty >/dev/null 2>&1; then
        return 1
    fi
    
    return 0
}

validate_required_var() {
    local name="$1"
    local value="${!name}"
    local validator="$2"
    local description="$3"
    
    ((REQUIRED_TOTAL++))
    
    if [[ -z "$value" ]]; then
        echo -e "${RED}✗${NC} $name: ${description} (not set)"
        ((ERRORS++))
        return 1
    fi
    
    if check_placeholder "$value" "$name"; then
        echo -e "${RED}✗${NC} $name: ${description} (placeholder value)"
        ((ERRORS++))
        return 1
    fi
    
    if [[ -n "$validator" ]]; then
        local validator_func="${validator%% *}"
        local validator_args="${validator#* }"
        if ! $validator_func "$value" $validator_args; then
            echo -e "${RED}✗${NC} $name: ${description} (invalid format)"
            ((ERRORS++))
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓${NC} $name: ${description}"
    ((REQUIRED_VALID++))
    return 0
}

validate_optional_var() {
    local name="$1"
    local value="${!name}"
    local validator="$2"
    local description="$3"
    
    ((OPTIONAL_TOTAL++))
    
    if [[ -z "$value" ]]; then
        echo -e "${YELLOW}○${NC} $name: ${description} (not set)"
        ((WARNINGS++))
        return 0
    fi
    
    if check_placeholder "$value" "$name"; then
        echo -e "${YELLOW}○${NC} $name: ${description} (placeholder value)"
        ((WARNINGS++))
        return 0
    fi
    
    if [[ -n "$validator" ]]; then
        local validator_func="${validator%% *}"
        local validator_args="${validator#* }"
        if ! $validator_func "$value" $validator_args; then
            echo -e "${YELLOW}⚠${NC} $name: ${description} (invalid format)"
            ((WARNINGS++))
            return 0
        fi
    fi
    
    echo -e "${GREEN}✓${NC} $name: ${description}"
    ((OPTIONAL_VALID++))
    return 0
}

generate_hex_key() {
    openssl rand -hex 32
}

fix_missing_vars() {
    if [[ $AUTO_GEN -eq 0 ]]; then
        return
    fi
    
    local temp_file=$(mktemp)
    cp "$ENV_FILE" "$temp_file"
    
    local n8n_key=$(grep "^N8N_ENCRYPTION_KEY=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$n8n_key" || [[ -z "$n8n_key" ]]; then
        local new_key=$(generate_hex_key)
        sed -i.bak "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$new_key/" "$temp_file"
        AUTO_GENERATED+=("N8N_ENCRYPTION_KEY")
        rm -f "${temp_file}.bak"
    fi
    
    local waha_token=$(grep "^WAHA_API_TOKEN=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$waha_token" || [[ -z "$waha_token" ]]; then
        local new_token=$(generate_hex_key)
        sed -i.bak "s/^WAHA_API_TOKEN=.*/WAHA_API_TOKEN=$new_token/" "$temp_file"
        AUTO_GENERATED+=("WAHA_API_TOKEN")
        rm -f "${temp_file}.bak"
    fi
    
    local webhook_secret=$(grep "^TELEGRAM_WEBHOOK_SECRET=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$webhook_secret" || [[ -z "$webhook_secret" ]]; then
        local new_secret=$(generate_hex_key)
        sed -i.bak "s/^TELEGRAM_WEBHOOK_SECRET=.*/TELEGRAM_WEBHOOK_SECRET=$new_secret/" "$temp_file"
        AUTO_GENERATED+=("TELEGRAM_WEBHOOK_SECRET")
        rm -f "${temp_file}.bak"
    fi
    
    local basic_auth_pass=$(grep "^N8N_BASIC_AUTH_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$basic_auth_pass" || [[ -z "$basic_auth_pass" ]]; then
        local new_pass=$(generate_hex_key)
        sed -i.bak "s/^N8N_BASIC_AUTH_PASSWORD=.*/N8N_BASIC_AUTH_PASSWORD=$new_pass/" "$temp_file"
        AUTO_GENERATED+=("N8N_BASIC_AUTH_PASSWORD")
        rm -f "${temp_file}.bak"
    fi
    
    local postgres_pass=$(grep "^POSTGRES_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$postgres_pass" || [[ -z "$postgres_pass" ]]; then
        local new_pass=$(generate_hex_key)
        sed -i.bak "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$new_pass/" "$temp_file"
        AUTO_GENERATED+=("POSTGRES_PASSWORD")
        rm -f "${temp_file}.bak"
    fi
    
    local redis_pass=$(grep "^REDIS_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    if check_placeholder "$redis_pass" || [[ -z "$redis_pass" ]]; then
        local new_pass=$(generate_hex_key)
        sed -i.bak "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$new_pass/" "$temp_file"
        AUTO_GENERATED+=("REDIS_PASSWORD")
        rm -f "${temp_file}.bak"
    fi
    
    mv "$temp_file" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
}

load_env_file() {
    if [[ ! -f "$ENV_FILE" ]]; then
        echo -e "${RED}Error: $ENV_FILE not found${NC}"
        echo "Copy .env.example to .env and configure it first:"
        echo "  cp .env.example .env"
        exit 1
    fi
    
    while IFS='=' read -r key value; do
        if [[ ! "$key" =~ ^# ]] && [[ -n "$key" ]] && [[ "$key" =~ ^[A-Z0-9_]+$ ]]; then
            value="${value//\$(/}"
            value="${value//)/}"
            
            if [[ "$value" =~ ^\".*\"$ ]] || [[ "$value" =~ ^\'.*\'$ ]]; then
                value="${value:1:$((${#value}-2))}"
            fi
            
            export "$key"="$value"
        fi
    done < "$ENV_FILE"
}

validate_all() {
    echo -e "${BLUE}=== Required Variables ===${NC}"
    
    validate_required_var "N8N_ENCRYPTION_KEY" "validate_hex_key 32" "N8N encryption key (32+ hex chars)"
    validate_required_var "N8N_BASIC_AUTH_PASSWORD" "" "N8N admin password"
    validate_required_var "WEBHOOK_URL" "validate_url" "Webhook URL (HTTPS)"
    validate_required_var "POSTGRES_PASSWORD" "" "PostgreSQL password"
    validate_required_var "REDIS_PASSWORD" "" "Redis password"
    validate_required_var "WAHA_API_TOKEN" "" "WAHA API token"
    validate_required_var "TWILIO_ACCOUNT_SID" "validate_twilio_sid" "Twilio Account SID (AC...)"
    validate_required_var "TWILIO_AUTH_TOKEN" "" "Twilio Auth Token"
    validate_required_var "TWILIO_PHONE_NUMBER" "validate_e164" "Twilio phone number (E.164)"
    validate_required_var "OPENAI_API_KEY" "" "OpenAI API key"
    validate_required_var "GOOGLE_SERVICE_ACCOUNT_JSON" "validate_json" "Google Service Account (JSON)"
    validate_required_var "GOOGLE_MAPS_API_KEY" "" "Google Maps API key"
    validate_required_var "GOOGLE_SOLAR_API_KEY" "" "Google Solar API key"
    validate_required_var "INSTALLER_PHONE_NUMBER" "validate_e164" "Installer phone (E.164)"
    validate_required_var "TELEGRAM_BOT_TOKEN" "validate_telegram_bot_token" "Telegram bot token"
    validate_required_var "INSTALLER_TELEGRAM_CHAT_ID" "validate_telegram_chat_id" "Telegram chat ID"
    validate_required_var "TELEGRAM_WEBHOOK_SECRET" "" "Telegram webhook secret"
    
    echo -e "\n${BLUE}=== Optional but Recommended Variables ===${NC}"
    
    validate_optional_var "DOMAIN" "" "Domain name"
    validate_optional_var "LETSENCRYPT_EMAIL" "" "Let's Encrypt email"
    validate_optional_var "TIMEZONE" "" "Timezone (e.g., Europe/Berlin)"
}

prompt_critical_values() {
    if [[ $AUTO_GEN -eq 0 ]]; then
        return
    fi
    
    local needs_input=false
    
    if check_placeholder "$DOMAIN" || [[ "$DOMAIN" == "yourdomain.com" ]]; then
        needs_input=true
    fi
    
    if check_placeholder "$TWILIO_ACCOUNT_SID"; then
        needs_input=true
    fi
    
    if check_placeholder "$TWILIO_AUTH_TOKEN"; then
        needs_input=true
    fi
    
    if check_placeholder "$TELEGRAM_BOT_TOKEN"; then
        needs_input=true
    fi
    
    if [[ "$needs_input" == "true" ]]; then
        echo -e "\n${YELLOW}Critical values missing. Please provide:${NC}"
        
        if check_placeholder "$DOMAIN" || [[ "$DOMAIN" == "yourdomain.com" ]]; then
            read -p "Enter your domain (e.g., example.com): " input_domain
            if [[ -n "$input_domain" ]]; then
                sed -i.bak "s/^DOMAIN=.*/DOMAIN=$input_domain/" "$ENV_FILE"
                sed -i.bak "s|N8N_HOST=.*|N8N_HOST=n8n.$input_domain|" "$ENV_FILE"
                sed -i.bak "s|WEBHOOK_URL=.*|WEBHOOK_URL=https://n8n.$input_domain|" "$ENV_FILE"
                sed -i.bak "s|WAHA_HOST=.*|WAHA_HOST=waha.$input_domain|" "$ENV_FILE"
                sed -i.bak "s|WAHA_API_URL=.*|WAHA_API_URL=https://waha.$input_domain|" "$ENV_FILE"
                rm -f "${ENV_FILE}.bak"
            fi
        fi
        
        if check_placeholder "$TWILIO_ACCOUNT_SID"; then
            read -p "Enter your Twilio Account SID (starts with AC): " input_sid
            if [[ -n "$input_sid" ]]; then
                sed -i.bak "s/^TWILIO_ACCOUNT_SID=.*/TWILIO_ACCOUNT_SID=$input_sid/" "$ENV_FILE"
                rm -f "${ENV_FILE}.bak"
            fi
        fi
        
        if check_placeholder "$TWILIO_AUTH_TOKEN"; then
            read -p "Enter your Twilio Auth Token: " input_token
            if [[ -n "$input_token" ]]; then
                sed -i.bak "s/^TWILIO_AUTH_TOKEN=.*/TWILIO_AUTH_TOKEN=$input_token/" "$ENV_FILE"
                rm -f "${ENV_FILE}.bak"
            fi
        fi
        
        if check_placeholder "$TWILIO_PHONE_NUMBER" || [[ "$TWILIO_PHONE_NUMBER" == "+1234567890" ]]; then
            read -p "Enter your Twilio phone number (e.g., +1234567890): " input_phone
            if [[ -n "$input_phone" ]]; then
                sed -i.bak "s/^TWILIO_PHONE_NUMBER=.*/TWILIO_PHONE_NUMBER=$input_phone/" "$ENV_FILE"
                rm -f "${ENV_FILE}.bak"
            fi
        fi
        
        if check_placeholder "$TELEGRAM_BOT_TOKEN"; then
            read -p "Enter your Telegram bot token (from BotFather): " input_bot
            if [[ -n "$input_bot" ]]; then
                sed -i.bak "s/^TELEGRAM_BOT_TOKEN=.*/TELEGRAM_BOT_TOKEN=$input_bot/" "$ENV_FILE"
                rm -f "${ENV_FILE}.bak"
            fi
        fi
        
        echo -e "\n${GREEN}Updated $ENV_FILE${NC}"
        echo "Please run validation again: $0"
        exit 0
    fi
}

print_summary() {
    echo -e "\n${BLUE}=== Summary ===${NC}"
    echo -e "Required: ${GREEN}$REQUIRED_VALID/$REQUIRED_TOTAL${NC} valid"
    echo -e "Optional: ${GREEN}$OPTIONAL_VALID/$OPTIONAL_TOTAL${NC} valid"
    
    if [[ ${#AUTO_GENERATED[@]} -gt 0 ]]; then
        echo -e "\n${GREEN}Auto-generated: ${AUTO_GENERATED[*]}${NC}"
    fi
    
    if [[ $ERRORS -gt 0 ]]; then
        echo -e "\n${RED}Errors: $ERRORS${NC}"
    fi
    
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    fi
    
    if [[ $AUTO_GEN -eq 0 ]] && [[ $ERRORS -gt 0 ]]; then
        echo -e "\n${YELLOW}Tip: Run '$0 --fix' to auto-generate missing secrets${NC}"
        echo -e "${YELLOW}You'll still need to provide critical values (Twilio, Telegram, Domain)${NC}"
    fi
    
    echo ""
}

main() {
    parse_args "$@"
    load_env_file
    
    if [[ $AUTO_GEN -eq 1 ]]; then
        prompt_critical_values
        fix_missing_vars
    fi
    
    validate_all
    print_summary
    
    if [[ $ERRORS -gt 0 ]]; then
        exit 1
    fi
    
    exit 0
}

main "$@"
