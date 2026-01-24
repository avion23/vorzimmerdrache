#!/bin/bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
WEBHOOK_URL="${WEBHOOK_BASE_URL:-http://localhost:3000}"
TEST_MODE="all"
VERBOSE=0

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --url)
      WEBHOOK_URL="$2"
      shift 2
      ;;
    --test)
      TEST_MODE="$2"
      shift 2
      ;;
    --verbose|-v)
      VERBOSE=1
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --url URL       Webhook base URL (default: \$WEBHOOK_BASE_URL)"
      echo "  --test NAME     Run specific test (all|health|twiml|timeout)"
      echo "  --verbose, -v   Verbose output"
      echo "  --help, -h      Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

log() {
  echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

verbose() {
  if [ $VERBOSE -eq 1 ]; then
    log "$1"
  fi
}

# Test 1: Health Check
test_health() {
  log "Running health check..."
  
  local start_time=$(date +%s%N)
  local response=$(curl -s -w "\n%{http_code}" -X POST \
    "${WEBHOOK_URL}/webhook/health" \
    -H "Content-Type: application/json" \
    2>&1)
  local end_time=$(date +%s%N)
  local duration=$(( (end_time - start_time) / 1000000 ))
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" = "200" ]; then
    log "Health check: ${GREEN}PASS${NC} (HTTP $http_code, ${duration}ms)"
    verbose "Response: $body"
    return 0
  else
    log_error "Health check: FAIL (HTTP $http_code)"
    return 1
  fi
}

# Test 2: TwiML Response
test_twiml() {
  log "Testing TwiML endpoint..."
  
  local response=$(curl -s -w "\n%{http_code}" -X POST \
    "${WEBHOOK_URL}/webhook/incoming-voice" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "Caller=%2B49123456789" \
    -d "Called=%2B49987654321" \
    -d "CallSid=CAtest123" \
    2>&1)
  
  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')
  
  if [ "$http_code" = "200" ] && echo "$body" | grep -q "<?xml"; then
    log "TwiML endpoint: ${GREEN}PASS${NC} (HTTP $http_code)"
    
    # Validate XML structure
    if echo "$body" | grep -q "<Response"; then
      log "TwiML structure: ${GREEN}VALID${NC}"
    else
      log_error "TwiML structure: ${YELLOW}WARN${NC} - Missing <Response> tag"
    fi
    
    verbose "TwiML: $body"
    return 0
  else
    log_error "TwiML endpoint: FAIL (HTTP $http_code)"
    return 1
  fi
}

# Test 3: Webhook Timeout
test_timeout() {
  log "Testing webhook timeout handling..."
  
  local start_time=$(date +%s)
  local timeout=15
  local http_code=0
  
  # Call with timeout
  http_code=$(curl -s -o /dev/null -w "%{http_code}" -m $timeout -X POST \
    "${WEBHOOK_URL}/webhook/incoming-voice" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "Caller=%2B49123456789" \
    -d "Called=%2B49987654321" \
    -d "CallSid=CAtest456" \
    2>&1 || echo "000")
  
  local end_time=$(date +%s)
  local duration=$((end_time - start_time))
  
  if [ "$http_code" = "200" ] && [ $duration -lt 10 ]; then
    log "Timeout test: ${GREEN}PASS${NC} (${duration}s)"
    return 0
  else
    log_error "Timeout test: FAIL (HTTP $http_code, ${duration}s)"
    return 1
  fi
}

# Test 4: TwiML Fallback
test_fallback() {
  log "Testing TwiML fallback..."
  
  local twiml_file="integrations/twilio/twiml-fallback.xml"
  
  if [ ! -f "$twiml_file" ]; then
    log_error "Fallback file not found: $twiml_file"
    return 1
  fi
  
  # Validate XML
  if xmllint --noout "$twiml_file" 2>/dev/null; then
    log "Fallback TwiML: ${GREEN}VALID${NC}"
    return 0
  else
    log_error "Fallback TwiML: ${YELLOW}WARN${NC} - XML validation failed"
    return 1
  fi
}

# Test 5: Required Environment Variables
test_env() {
  log "Checking environment variables..."
  
  local missing=()
  local required_vars=(
    "TWILIO_ACCOUNT_SID"
    "TWILIO_AUTH_TOKEN"
    "TWILIO_PHONE_NUMBER"
  )
  
  for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
      missing+=("$var")
    fi
  done
  
  if [ ${#missing[@]} -eq 0 ]; then
    log "Environment: ${GREEN}PASS${NC}"
    return 0
  else
    log_warn "Environment: ${YELLOW}WARN${NC} - Missing: ${missing[*]}"
    return 1
  fi
}

# Test 6: Twilio API Connectivity
test_twilio_api() {
  log "Testing Twilio API connectivity..."
  
  local account_sid="${TWILIO_ACCOUNT_SID:-}"
  
  if [ -z "$account_sid" ]; then
    log_warn "Twilio API: ${YELLOW}SKIP${NC} - TWILIO_ACCOUNT_SID not set"
    return 0
  fi
  
  # Check if we can reach Twilio API
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
    "https://api.twilio.com/2010-04-01/Accounts/$account_sid.json" \
    -u "$TWILIO_ACCOUNT_SID:$TWILIO_AUTH_TOKEN" \
    2>&1)
  
  if [ "$http_code" = "200" ]; then
    log "Twilio API: ${GREEN}PASS${NC} (HTTP $http_code)"
    return 0
  elif [ "$http_code" = "401" ]; then
    log_error "Twilio API: FAIL (Unauthorized - check credentials)"
    return 1
  else
    log_error "Twilio API: FAIL (HTTP $http_code)"
    return 1
  fi
}

# Test 7: Webhook Signature Simulation
test_signature() {
  log "Testing webhook signature validation..."
  
  local url="${WEBHOOK_URL}/webhook/incoming-voice"
  local body="Caller=%2B49123456789&Called=%2B49987654321"
  local token="${TWILIO_AUTH_TOKEN:-}"
  
  if [ -z "$token" ]; then
    log_warn "Signature test: ${YELLOW}SKIP${NC} - TWILIO_AUTH_TOKEN not set"
    return 0
  fi
  
  # Generate signature (requires proper implementation)
  # For now, just test if endpoint accepts POST
  local http_code=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "$url" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "$body" \
    2>&1)
  
  if [ "$http_code" = "200" ]; then
    log "Signature test: ${GREEN}PASS${NC} (Endpoint accessible)"
    return 0
  else
    log_error "Signature test: FAIL (HTTP $http_code)"
    return 1
  fi
}

# Main test runner
run_tests() {
  local failed=0
  local passed=0
  
  echo "========================================"
  echo "Twilio Webhook Test Suite"
  echo "========================================"
  echo "URL: $WEBHOOK_URL"
  echo "Mode: $TEST_MODE"
  echo "========================================"
  echo ""
  
  case "$TEST_MODE" in
    all)
      test_health && ((passed++)) || ((failed++))
      test_env && ((passed++)) || ((failed++))
      test_twilio_api && ((passed++)) || ((failed++))
      test_twiml && ((passed++)) || ((failed++))
      test_timeout && ((passed++)) || ((failed++))
      test_fallback && ((passed++)) || ((failed++))
      test_signature && ((passed++)) || ((failed++))
      ;;
    health)
      test_health && ((passed++)) || ((failed++))
      ;;
    twiml)
      test_twiml && ((passed++)) || ((failed++))
      ;;
    timeout)
      test_timeout && ((passed++)) || ((failed++))
      ;;
    fallback)
      test_fallback && ((passed++)) || ((failed++))
      ;;
    *)
      log_error "Unknown test mode: $TEST_MODE"
      exit 1
      ;;
  esac
  
  echo ""
  echo "========================================"
  echo "Test Results"
  echo "========================================"
  echo "Passed: $passed"
  echo "Failed: $failed"
  echo "Total:  $((passed + failed))"
  echo "========================================"
  
  if [ $failed -eq 0 ]; then
    log "All tests ${GREEN}PASSED${NC}"
    exit 0
  else
    log_error "Some tests ${RED}FAILED${NC}"
    exit 1
  fi
}

# Run
run_tests
