#!/bin/bash
set -e

DOCKER_COMPOSE_FILE="${1:-docker-compose.yml}"

total_mem=$(free -m | awk '/^Mem:/{print $2}')
if [ "$total_mem" -lt 900 ]; then
    echo "WARNING: System has only ${total_mem}MB RAM (<900MB recommended)"
fi

if ! command -v docker &> /dev/null; then
    apt update && apt install -y docker.io
fi

if [ ! -f .env ]; then
    cp .env.example .env
fi

docker compose -f "$DOCKER_COMPOSE_FILE" pull
docker compose -f "$DOCKER_COMPOSE_FILE" down 2>/dev/null || true
docker system prune -f
docker compose -f "$DOCKER_COMPOSE_FILE" up -d

retries=0
max_retries=12
while [ $retries -lt $max_retries ]; do
    if curl -s -f http://localhost:5678/healthz > /dev/null 2>&1; then
        break
    fi
    retries=$((retries + 1))
    echo "Waiting for n8n to be healthy... ($retries/$max_retries)"
    sleep 5
done

if [ $retries -eq $max_retries ]; then
    echo "ERROR: n8n health check failed after 60 seconds"
    exit 1
fi

docker compose -f "$DOCKER_COMPOSE_FILE" ps

if [ -f .env ]; then
    DOMAIN=$(grep "^DOMAIN=" .env | cut -d'=' -f2)
    echo "https://${DOMAIN}/"
fi
