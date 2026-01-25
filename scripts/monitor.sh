#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

get_memory_status() {
    local mem_info=$(free -m | awk 'NR==2{print $2,$3,$4,$7}')
    local total=$(echo $mem_info | awk '{print $1}')
    local used=$(echo $mem_info | awk '{print $2}')
    local free=$(echo $mem_info | awk '{print $3}')
    local available=$(echo $mem_info | awk '{print $4}')

    if [ "$available" -lt 100 ]; then
        echo -e "${RED}CRITICAL${NC}"
    elif [ "$available" -lt 200 ]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${GREEN}OK${NC}"
    fi
}

get_disk_status() {
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    
    if [ "$disk_usage" -gt 90 ]; then
        echo -e "${RED}CRITICAL${NC}"
    elif [ "$disk_usage" -gt 80 ]; then
        echo -e "${YELLOW}WARNING${NC}"
    else
        echo -e "${GREEN}OK${NC}"
    fi
}

get_swap_status() {
    local swap_info=$(free -m | awk 'NR==3{print $2,$3}')
    local total=$(echo $swap_info | awk '{print $1}')
    local used=$(echo $swap_info | awk '{print $2}')
    
    if [ "$total" -eq 0 ]; then
        echo -e "${GREEN}0Mi/0Mi${NC}"
    elif [ "$used" -gt 0 ]; then
        echo -e "${YELLOW}${used}Mi/${total}Mi${NC}"
    else
        echo -e "${GREEN}${used}Mi/${total}Mi${NC}"
    fi
}

check_oom_kills() {
    local oom_count=$(dmesg | grep -i "out of memory" | grep -c "$(date '+%Y-%m-%d %H')" 2>/dev/null)
    echo "$oom_count"
}

echo "=== Vorzimmerdrache Monitor ==="

mem_info=$(free -m | awk 'NR==2{print $2,$3,$4,$7}')
total_mem=$(echo $mem_info | awk '{print $1}')
used_mem=$(echo $mem_info | awk '{print $2}')
free_mem=$(echo $mem_info | awk '{print $3}')
avail_mem=$(echo $mem_info | awk '{print $4}')
mem_status=$(get_memory_status)

echo -n "Memory: ${used_mem}Mi/${total_mem}Mi (${avail_mem}Mi free) "
echo -e "[$mem_status]"

disk_info=$(df -h / | awk 'NR==2{print $3,$2,$5}')
used_disk=$(echo $disk_info | awk '{print $1}')
total_disk=$(echo $disk_info | awk '{print $2}')
disk_pct=$(echo $disk_info | awk '{print $3}')
disk_status=$(get_disk_status)

echo -n "Disk: ${used_disk}/${total_disk} (${disk_pct} used) "
echo -e "[$disk_status]"

swap_info=$(free -m | awk 'NR==3{print $2,$3}')
total_swap=$(echo $swap_info | awk '{print $1}')
used_swap=$(echo $swap_info | awk '{print $2}')
if [ "$total_swap" -eq 0 ]; then
    swap_status="OK"
    echo -e "Swap: 0Mi/0Mi [${GREEN}OK${NC}]"
else
    if [ "$used_swap" -gt 0 ]; then
        swap_status="${YELLOW}WARNING${NC}"
    else
        swap_status="${GREEN}OK${NC}"
    fi
    echo -e "Swap: ${used_swap}Mi/${total_swap}Mi [$swap_status]"
fi

oom_count=$(check_oom_kills)
if [ "$oom_count" -gt 0 ]; then
    echo -e "OOM kills in last hour: $oom_count [${RED}CRITICAL${NC}]"
else
    echo -e "OOM kills in last hour: $oom_count [${GREEN}OK${NC}]"
fi

echo ""
echo "Docker Status:"

if command -v docker &> /dev/null; then
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Size}}" | tail -n +2 | while read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        size=$(echo "$line" | awk '{print $3}')
        
        if echo "$status" | grep -q "Up"; then
            container_status="${GREEN}OK${NC}"
        else
            container_status="${RED}CRITICAL${NC}"
        fi
        
        echo -e "$name: $status ($size) [$container_status]"
    done
else
    echo "Docker not found"
fi
