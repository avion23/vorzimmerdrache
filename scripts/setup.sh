#!/bin/bash
# Unified setup script for Vorzimmerdrache
# Usage: ./setup.sh [deploy|test|verify|all]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
N8N_HOST="${N8N_HOST:-instance1.duckdns.org}"
N8N_BASE_URL="${N8N_BASE_URL:-https://$N8N_HOST}"
N8N_API_URL="$N8N_BASE_URL/api/v1"
WORKFLOW_DIR="$PROJECT_DIR/workflows"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}✓${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

check_prerequisites() {
    echo "=== Checking Prerequisites ==="
    
    # Check .env file
    if [ ! -f "$PROJECT_DIR/.env" ] && [ ! -f "$PROJECT_DIR/.env.local" ]; then
        log_error "No .env file found"
        echo "   Copy .env.example to .env and configure your credentials"
        exit 1
    fi
    log_info "Environment file exists"
    
    # Check N8N_API_KEY
    if [ -z "$N8N_API_KEY" ]; then
        if [ -f "$PROJECT_DIR/.env.local" ]; then
            export $(grep -v '^#' "$PROJECT_DIR/.env.local" | xargs 2>/dev/null || true)
        fi
    fi
    
    if [ -z "$N8N_API_KEY" ]; then
        log_error "N8N_API_KEY not set"
        echo "   Set it with: export N8N_API_KEY=your_api_key"
        exit 1
    fi
    log_info "N8N_API_KEY configured"
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_warn "jq not installed (optional, for better JSON output)"
    else
        log_info "jq available"
    fi
    
    echo ""
}

deploy_workflows() {
    echo "=== Deploying Workflows ==="
    
    local deployed=0
    local failed=0
    
    for workflow in "$WORKFLOW_DIR"/*.json; do
        if [ -f "$workflow" ]; then
            local name=$(basename "$workflow" .json)
            echo "   Deploying: $name"
            
            # Clean workflow JSON - remove UI-specific fields
            local cleaned=$(jq '{
                name: .name,
                nodes: [.nodes[] | del(.id, .position, .webhookId)],
                connections: .connections,
                settings: .settings
            }' "$workflow")
            
            # Import workflow via API
            local response=$(curl -s -X POST "$N8N_API_URL/workflows" \
                -H "X-N8N-API-KEY: $N8N_API_KEY" \
                -H "Content-Type: application/json" \
                -d "$cleaned")
            
            if echo "$response" | grep -q '"id"'; then
                log_info "Deployed: $name"
                deployed=$((deployed + 1))
            else
                log_error "Failed to deploy: $name"
                echo "   Response: $response"
                failed=$((failed + 1))
            fi
        fi
    done
    
    echo ""
    log_info "Deployed: $deployed workflows"
    if [ $failed -gt 0 ]; then
        log_error "Failed: $failed workflows"
    fi
    echo ""
}

test_webhooks() {
    echo "=== Testing Webhooks ==="
    
    # Test SMS webhook
    echo "   Testing SMS webhook..."
    local sms_result=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
        "$N8N_BASE_URL/webhook/sms-response" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "From=%2B49151123456789&Body=JA" 2>/dev/null || echo "HTTP_CODE:000")
    
    local sms_http=$(echo "$sms_result" | grep "HTTP_CODE:" | cut -d: -f2)
    if [ "$sms_http" = "200" ]; then
        log_info "SMS webhook responding (HTTP $sms_http)"
    else
        log_warn "SMS webhook issue (HTTP $sms_http)"
    fi
    
    # Test Voice webhook
    echo "   Testing Voice webhook..."
    local voice_result=$(curl -s -w "\nHTTP_CODE:%{http_code}" -X POST \
        "$N8N_BASE_URL/webhook/incoming-call" \
        -H "Content-Type: application/json" \
        -d '{"From":"+49151123456789","CallStatus":"ringing"}' 2>/dev/null || echo "HTTP_CODE:000")
    
    local voice_http=$(echo "$voice_result" | grep "HTTP_CODE:" | cut -d: -f2)
    if [ "$voice_http" = "200" ] || [ "$voice_http" = "201" ]; then
        log_info "Voice webhook responding (HTTP $voice_http)"
    else
        log_warn "Voice webhook issue (HTTP $voice_http)"
    fi
    
    echo ""
}

verify_setup() {
    echo "=== Verifying Setup ==="
    
    # Check active workflows
    echo "   Active workflows:"
    local workflows=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_API_URL/workflows" 2>/dev/null)
    
    if command -v jq &> /dev/null; then
        echo "$workflows" | jq -r '.data[] | select(.active == true) | "     ✓ \(.name)"' 2>/dev/null || echo "     (none)"
    else
        echo "$workflows" | grep -o '"name":"[^"]*","active":true' | sed 's/"name":"/     ✓ /;s/","active":true//' 2>/dev/null || echo "     (none)"
    fi
    
    echo ""
    log_info "Webhook URLs:"
    echo "   Voice: $N8N_BASE_URL/webhook/incoming-call"
    echo "   SMS:   $N8N_BASE_URL/webhook/sms-response"
    echo ""
}

show_help() {
    cat << EOF
Vorzimmerdrache Setup Script

Usage: ./setup.sh [command]

Commands:
  deploy    Deploy all workflows to n8n
  test      Test webhook endpoints
  verify    Verify setup and show status
  all       Run all steps (default)
  help      Show this help message

Environment Variables:
  N8N_HOST      n8n host (default: instance1.duckdns.org)
  N8N_API_KEY   n8n API key (required)

Examples:
  ./setup.sh                    # Run all steps
  ./setup.sh deploy             # Deploy only
  N8N_HOST=myhost.com ./setup.sh test

EOF
}

# Main
main() {
    local command="${1:-all}"
    
    case "$command" in
        deploy)
            check_prerequisites
            deploy_workflows
            ;;
        test)
            test_webhooks
            ;;
        verify)
            verify_setup
            ;;
        all)
            check_prerequisites
            deploy_workflows
            test_webhooks
            verify_setup
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    echo "Next steps:"
    echo "  1. Configure Twilio webhooks to point to your n8n instance"
    echo "  2. Test with real SMS/call"
    echo "  3. Monitor at: $N8N_BASE_URL/executions"
}

main "$@"
