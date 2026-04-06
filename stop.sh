#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "Bento HTTP-Kafka Proxy Stop Script        "
echo "=========================================="
echo ""

# Stop Docker containers if running
echo "🛑 Stopping Docker containers..."

docker compose down

# Check if Docker Compose command succeeded
if [ $? -ne 0 ]; then
    echo "❌ Failed to start the application with Docker Compose"
    exit 1
fi

echo "✅ Docker container stopped"
echo ""
