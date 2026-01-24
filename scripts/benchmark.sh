#!/bin/bash
set -e

cd "$(dirname "$0")/.."

echo "=== Vorzimmerdrache Performance Benchmark ==="
echo

COLOR_RESET='\033[0m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_RED='\033[0;31m'
COLOR_BLUE='\033[0;34m'

log_success() {
  echo -e "${COLOR_GREEN}✓${COLOR_RESET} $1"
}

log_info() {
  echo -e "${COLOR_BLUE}ℹ${COLOR_RESET} $1"
}

log_warning() {
  echo -e "${COLOR_YELLOW}⚠${COLOR_RESET} $1"
}

log_error() {
  echo -e "${COLOR_RED}✗${COLOR_RESET} $1"
}

check_dependencies() {
  log_info "Checking dependencies..."

  command -v curl >/dev/null 2>&1 || { log_error "curl required but not installed"; exit 1; }
  command -v docker >/dev/null 2>&1 || { log_error "docker required but not installed"; exit 1; }
  command -v jq >/dev/null 2>&1 || { log_warning "jq not installed, JSON parsing limited"; }

  log_success "Dependencies OK"
}

benchmark_n8n_webhook() {
  log_info "Testing n8n webhook endpoint..."

  N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-http://localhost:5678}"
  WEBHOOK_PATH="${WEBHOOK_PATH:-webhook/pv-lead}"

  local payload='{
    "name": "Test User",
    "phone": "+4917123456789",
    "email": "test@example.com",
    "address": "Musterstraße 123, 10115 Berlin"
  }'

  local start_time=$(date +%s%3N)
  local response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${N8N_WEBHOOK_URL}/${WEBHOOK_PATH}")
  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  local http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n-1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log_success "Webhook responded in ${duration}ms (HTTP $http_code)"
    echo "$body" | jq -r '.' 2>/dev/null || echo "$body"
    return 0
  else
    log_error "Webhook failed in ${duration}ms (HTTP $http_code)"
    echo "$body"
    return 1
  fi
}

benchmark_crm_lookup() {
  log_info "Testing CRM lookup performance..."

  if [ -f ".env" ]; then
    source .env
  fi

  if [ -n "$POSTGRES_HOST" ]; then
    local start_time=$(date +%s%3N)
    
    docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -c \
      "SELECT name, status, email FROM leads WHERE phone = '+4917123456789' LIMIT 1;" > /dev/null 2>&1
    
    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    if [ $? -eq 0 ]; then
      log_success "CRM lookup completed in ${duration}ms"
      return 0
    else
      log_error "CRM lookup failed"
      return 1
    fi
  else
    log_warning "POSTGRES_HOST not set, skipping CRM lookup"
    return 0
  fi
}

benchmark_redis_cache() {
  log_info "Testing Redis cache performance..."

  local key="benchmark_test_key_$(date +%s)"
  local value="benchmark_test_value"

  local start_time=$(date +%s%3N)
  docker exec redis redis-cli -a "${REDIS_PASSWORD:-}" SET "$key" "$value" > /dev/null 2>&1
  local end_time=$(date +%s%3N)
  local set_duration=$((end_time - start_time))

  start_time=$(date +%s%3N)
  docker exec redis redis-cli -a "${REDIS_PASSWORD:-}" GET "$key" > /dev/null 2>&1
  end_time=$(date +%s%3N)
  local get_duration=$((end_time - start_time))

  if [ $? -eq 0 ]; then
    log_success "Redis SET: ${set_duration}ms, GET: ${get_duration}ms"
    return 0
  else
    log_error "Redis cache test failed"
    return 1
  fi
}

benchmark_google_maps() {
  log_info "Testing Google Maps API geocoding..."

  if [ -f ".env" ]; then
    source .env
  fi

  if [ -n "$GOOGLE_MAPS_API_KEY" ]; then
    local address="Alexanderplatz,+Berlin"
    local start_time=$(date +%s%3N)

    local response=$(curl -s "https://maps.googleapis.com/maps/api/geocode/json?address=${address}&key=${GOOGLE_MAPS_API_KEY}")

    local end_time=$(date +%s%3N)
    local duration=$((end_time - start_time))

    local status=$(echo "$response" | jq -r '.status' 2>/dev/null || echo "parse_error")

    if [ "$status" = "OK" ]; then
      log_success "Google Maps API responded in ${duration}ms"
      return 0
    else
      log_error "Google Maps API failed: $status (${duration}ms)"
      return 1
    fi
  else
    log_warning "GOOGLE_MAPS_API_KEY not set, skipping Google Maps test"
    return 0
  fi
}

benchmark_full_pipeline() {
  log_info "Running full pipeline benchmark (inbound call → WhatsApp → Telegram)..."

  N8N_WEBHOOK_URL="${N8N_WEBHOOK_URL:-http://localhost:5678}"
  WEBHOOK_PATH="${WEBHOOK_PATH:-webhook/incoming-voice}"

  local test_phone="+4915998765432"
  local start_time=$(date +%s%3N)

  local payload="{
    \"From\": \"${test_phone}\",
    \"To\": \"+4915112345678\",
    \"CallSid\": \"CA$(date +%s%N)\",
    \"FromCity\": \"Berlin\",
    \"FromState\": \"BE\"
  }"

  local response=$(curl -s -w "\n%{http_code}" -X POST \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${N8N_WEBHOOK_URL}/${WEBHOOK_PATH}")

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  local http_code=$(echo "$response" | tail -n1)

  if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
    log_success "Full pipeline completed in ${duration}ms"
    return 0
  else
    log_error "Pipeline failed in ${duration}ms (HTTP $http_code)"
    return 1
  fi
}

check_database_indexes() {
  log_info "Checking database indexes..."

  if [ -f ".env" ]; then
    source .env
  fi

  if [ -n "$POSTGRES_HOST" ]; then
    local indexes=$(docker exec postgres psql -U "${POSTGRES_USER:-n8n}" -d "${POSTGRES_DB:-n8n}" -t -c \
      "SELECT count(*) FROM pg_indexes WHERE tablename = 'leads';")

    local expected_indexes=12

    if [ "$indexes" -ge "$expected_indexes" ]; then
      log_success "Database has $indexes indexes (expected: $expected_indexes)"
      return 0
    else
      log_warning "Database has $indexes indexes (expected: $expected_indexes), run migrations"
      return 1
    fi
  else
    log_warning "POSTGRES_HOST not set, skipping index check"
    return 0
  fi
}

generate_report() {
  echo
  echo "=== Benchmark Summary ==="
  echo
  echo "Run this script regularly to track performance improvements."
  echo
  echo "Target Metrics:"
  echo "  - Full pipeline (inbound → WhatsApp → Telegram): <3000ms"
  echo "  - CRM lookup: <100ms"
  echo "  - Redis cache: <5ms (SET), <5ms (GET)"
  echo "  - Google Maps API: <1000ms"
  echo
  echo "Optimization Tips:"
  echo "  - Add Redis caching for repeated queries"
  echo "  - Ensure all database indexes are created"
  echo "  - Use connection pooling for PostgreSQL"
  echo "  - Enable query performance monitoring"
  echo
}

main() {
  local results=()

  check_dependencies
  echo

  results+=($(benchmark_redis_cache; echo $?))
  echo

  results+=($(benchmark_crm_lookup; echo $?))
  echo

  results+=($(benchmark_google_maps; echo $?))
  echo

  results+=($(benchmark_n8n_webhook; echo $?))
  echo

  results+=($(benchmark_full_pipeline; echo $?))
  echo

  results+=($(check_database_indexes; echo $?))
  echo

  local failed=0
  for result in "${results[@]}"; do
    if [ "$result" -ne 0 ]; then
      ((failed++))
    fi
  done

  generate_report

  if [ "$failed" -eq 0 ]; then
    log_success "All benchmarks passed!"
    exit 0
  else
    log_error "$failed benchmark(s) failed"
    exit 1
  fi
}

main "$@"
