#!/usr/bin/env bash
set -euo pipefail

# Source .env file
echo -e "✅ Loading configuration from .env"
set -a
source .env
set +a

PROXY_URL="${PROXY_URL:-http://localhost:4195}"
TOPIC="${TEST_TOPIC:-test-topic}"
CONTENT_TYPE="application/vnd.kafka.binary.v2+json"
FAILED=0

echo "=========================================="
echo "Bento HTTP-Kafka Proxy Test Suite (Binary)"
echo "=========================================="
echo "Proxy URL: $PROXY_URL"
echo "Test Topic: $TOPIC"
echo ""
echo "Note: This tests Binary payloads only (no Schema Registry)."
echo "For AVRO tests, run: ./test-avro.sh"
echo ""

# Test 1: POST with Binary (string value base64-encoded)
echo ""
echo "Test 1: POST Binary message to /topics/$TOPIC"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: $CONTENT_TYPE" \
    -d '{"records": [{"key": "string-b64", "value": "dGhpcyBpcyBzYW1wbGUgbWVzc2FnZSBlbmNvZGVkIGluIGJhc2U2NA=="}]}')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "✅ Binary message sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "❌ Binary message failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 2: POST with Binary (non-string value base64-encoded)
echo ""
echo "Test 2: POST Binary message to /topics/$TOPIC/partitions/0"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: $CONTENT_TYPE" \
    -d '{"records": [{"key": "binary-b64", "value": "3q2+7w=="}]}')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "✅ Binary message sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "❌ Binary message failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
    echo -e "✅ All tests passed!"
    echo "=========================================="
    echo ""
    echo "To view metrics:"
    echo "  curl $PROXY_URL/bento/metrics"
    echo ""
    echo "To view logs:"
    echo "  docker compose logs -f bento-http-kafka-proxy"
    exit 0
else
    echo -e "❌ $FAILED test(s) failed!"
    echo "=========================================="
    echo ""
    echo "To view logs:"
    echo "  docker compose logs -f bento-http-kafka-proxy"
    exit 1
fi
