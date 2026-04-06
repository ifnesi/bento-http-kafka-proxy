#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Bento HTTP-Kafka Proxy Startup"
echo "=========================================="
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠${NC}  .env file not found!"

    if [ -f .env.example ]; then
        echo -e "${GREEN}✓${NC} Copying .env.example to .env"
        cp .env.example .env
        echo ""
        echo -e "${YELLOW}⚠${NC}  IMPORTANT: Please edit .env with your credentials:"
        echo ""
        echo "  Required variables to update:"
        echo "    - KAFKA_BROKERS"
        echo "    - KAFKA_API_KEY"
        echo "    - KAFKA_API_SECRET"
        echo "    - SCHEMA_REGISTRY_URL"
        echo ""
        echo "  Run: nano .env"
        echo ""
        exit 1
    else
        echo -e "${RED}✗${NC} .env.example file not found!"
        echo "Cannot create .env file. Please create it manually."
        exit 1
    fi
fi

# Source .env file
echo -e "${GREEN}✓${NC} Loading configuration from .env"
set -a
source .env
set +a

# Validate required environment variables
REQUIRED_VARS=("KAFKA_BROKERS" "KAFKA_API_KEY" "KAFKA_API_SECRET" "SCHEMA_REGISTRY_URL")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var:-}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}✗${NC} Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "    - $var"
    done
    echo ""
    echo "Please edit .env and set these variables."
    exit 1
fi

echo -e "${GREEN}✓${NC} Configuration validated"
echo ""

# Start with docker compose
echo "Starting Bento HTTP-Kafka Proxy with Docker Compose..."
echo ""

docker compose up -d

echo ""
echo "=========================================="
echo -e "${GREEN}✓${NC} Bento HTTP-Kafka Proxy started successfully!"
echo "=========================================="
echo ""
echo "Health endpoints:"
echo "  - Ping:    http://localhost:${HTTP_PROXY_PORT:-4195}/bento/ping"
echo "  - Ready:   http://localhost:${HTTP_PROXY_PORT:-4195}/bento/ready"
echo "  - Metrics: http://localhost:${HTTP_PROXY_PORT:-4195}/bento/metrics"
echo ""
echo "View logs:"
echo "  docker compose logs -f"
echo ""
echo "Stop proxy:"
echo "  docker compose down"
echo ""
