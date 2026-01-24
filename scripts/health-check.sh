#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

check_service() {
    local service=$1
    local url=$2
    local name=$3
    
    if curl -sf -o /dev/null --max-time 5 "$url"; then
        echo -e "${GREEN}✓${NC} $name ($service)"
        return 0
    else
        echo -e "${RED}✗${NC} $name ($service) - UNREACHABLE"
        return 1
    fi
}

check_container_memory() {
    local container=$1
    local limit=$2
    local name=$3
    
    local mem_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container" 2>/dev/null | cut -d'/' -f1 | tr -d '[:alpha:]' || echo "0")
    local mem_mb=$(echo "$mem_usage" | awk '{print int($1/1024/1024)}')
    
    if [ "$mem_mb" -lt "$limit" ]; then
        echo -e "${GREEN}✓${NC} $name memory: ${mem_mb}MB < ${limit}MB limit"
        return 0
    else
        echo -e "${YELLOW}⚠${NC} $name memory: ${mem_mb}MB >= ${limit}MB limit"
        return 1
    fi
}

echo "Health Check - $(date)"
echo "========================"

total_status=0

echo ""
echo "Service Health:"
check_service "postgres" "http://localhost:5432" "PostgreSQL" || total_status=$((total_status+1))
check_service "redis" "http://localhost:6379" "Redis" || total_status=$((total_status+1))
check_service "n8n" "http://localhost:5678/healthz" "n8n" || total_status=$((total_status+1))
check_service "waha" "http://localhost:3000/api/health" "Waha" || total_status=$((total_status+1))

echo ""
echo "Memory Usage:"
check_container_memory "postgres" 150 "PostgreSQL" || total_status=$((total_status+1))
check_container_memory "redis" 50 "Redis" || total_status=$((total_status+1))
check_container_memory "n8n" 400 "n8n" || total_status=$((total_status+1))
check_container_memory "waha" 200 "Waha" || total_status=$((total_status+1))

echo ""
echo "System Memory:"
system_total=$(free -m | awk '/^Mem:/{print $2}')
system_used=$(free -m | awk '/^Mem:/{print $3}')
system_free=$(free -m | awk '/^Mem:/{print $7}')
system_percent=$(awk "BEGIN {printf \"%.1f\", ($system_used/$system_total)*100}")

echo "Total: ${system_total}MB | Used: ${system_used}MB (${system_percent}%) | Free: ${system_free}MB"

if [ "$system_percent" -gt 90 ]; then
    echo -e "${RED}⚠${NC} System memory critically high: ${system_percent}%"
    total_status=$((total_status+1))
elif [ "$system_percent" -gt 80 ]; then
    echo -e "${YELLOW}⚠${NC} System memory high: ${system_percent}%"
fi

echo ""
echo "Disk Space:"
disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
disk_free=$(df -h / | awk 'NR==2 {print $4}')

echo "Usage: ${disk_usage}% | Free: ${disk_free}"

if [ "$disk_usage" -gt 80 ]; then
    echo -e "${YELLOW}⚠${NC} Disk space high: ${disk_usage}%"
    total_status=$((total_status+1))
fi

echo ""
echo "========================"
if [ $total_status -eq 0 ]; then
    echo -e "${GREEN}All checks passed${NC}"
    exit 0
else
    echo -e "${RED}$total_status check(s) failed${NC}"
    exit 1
fi
