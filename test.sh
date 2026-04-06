#!/usr/bin/env bash
set -euo pipefail

# Source .env file
echo -e "✅ Loading configuration from .env"
set -a
source .env
set +a

PROXY_URL="${PROXY_URL:-http://localhost:4195}"
TOPIC="${TEST_TOPIC:-test-topic}"
FAILED=0

echo "=========================================="
echo "Bento HTTP-Kafka Proxy Test Suite (JSON)"
echo "=========================================="
echo "Proxy URL: $PROXY_URL"
echo "Test Topic: $TOPIC"
echo ""
echo "Note: This tests JSON payloads only (no Schema Registry)."
echo "For AVRO tests, run: ./test-avro.sh"
echo ""

# Test 1: Health Check
echo "Test 1: Health Checks"
if curl -sf "$PROXY_URL/bento/ping" > /dev/null; then
    echo -e "✅ Ping endpoint OK"
else
    echo -e "❌ Ping endpoint FAILED"
    FAILED=$((FAILED + 1))
fi

if curl -sf "$PROXY_URL/bento/ready" > /dev/null; then
    echo -e "✅ Ready endpoint OK"
else
    echo -e "❌ Ready endpoint FAILED"
    FAILED=$((FAILED + 1))
fi

# Test 2: Metrics endpoint
echo ""
echo "Test 2: Metrics Endpoint"
if curl -sf "$PROXY_URL/bento/metrics" | grep -q "input_received"; then
    echo -e "✅ Metrics endpoint OK"
else
    echo -e "❌ Metrics endpoint FAILED"
    FAILED=$((FAILED + 1))
fi

# Test 3: POST with JSON (basic)
echo ""
echo "Test 3: POST JSON message to /topics/$TOPIC"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '{"records": [{"key": "test-key-1", "value": {"msg": "test message 1"}}]}')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "✅ JSON message sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "❌ JSON message failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 4: POST with explicit partition
echo ""
echo "Test 4: POST JSON message to /topics/$TOPIC/partitions/0"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC/partitions/0" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '{"records": [{"value": {"msg": "partition 0 message"}}]}')

if echo "$RESPONSE" | grep -q '"partition":0'; then
    echo -e "✅ Partition-specific message sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "❌ Partition-specific message failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 5: Multiple records in one request
echo ""
echo "Test 5: POST multiple records"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '{
        "records": [
            {"key": "key-1", "value": {"id": 1, "name": "Alice"}},
            {"key": "key-2", "value": {"id": 2, "name": "Bob"}},
            {"key": "key-3", "value": {"id": 3, "name": "Charlie"}},
            {"key": "key-4", "value": {"id": 3, "name": "Test message with headers"}, "headers": [{"name": "Header-1","value": "SGVhZGVyLTE="},{"name": "Header-2","value": "SGVhZGVyLTI="}]}
        ]
    }')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "✅ Multiple records sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "❌ Multiple records failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 6: Error handling - empty body
echo ""
echo "Test 6: Error Handling - Empty body (should return 400)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '')

if [ "$STATUS" = "400" ]; then
    echo -e "✅ Empty body correctly rejected (400)"
else
    echo -e "❌ Empty body test failed (expected 400, got $STATUS)"
    FAILED=$((FAILED + 1))
fi

# Test 7: Error handling - missing records array
echo ""
echo "Test 7: Error Handling - Missing records array (should return 400)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '{"data": [{"value": "test"}]}')

if [ "$STATUS" = "400" ]; then
    echo -e "✅ Missing records array correctly rejected (400)"
else
    echo -e "❌ Missing records array test failed (expected 400, got $STATUS)"
    FAILED=$((FAILED + 1))
fi

# Test 8: Error handling - unsupported content type
echo ""
echo "Test 8: Error Handling - Unsupported content type (should return 415)"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: text/plain" \
    -d '{"records": [{"value": "test"}]}')

if [ "$STATUS" = "415" ]; then
    echo -e "✅ Unsupported content type correctly rejected (415)"
else
    echo -e "❌ Unsupported content type test failed (expected 415, got $STATUS)"
    FAILED=$((FAILED + 1))
fi

# Test 9: Different content-type variations
echo ""
echo "Test 9: Content-Type variations"

# application/json
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/json" \
    -d '{"records": [{"value": {"test": true}}]}')

if [ "$STATUS" = "200" ]; then
    echo -e "✅ application/json accepted"
else
    echo -e "❌ application/json returned $STATUS (expected 200)"
    FAILED=$((FAILED + 1))
fi

# application/vnd.kafka.json.v2+json
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.json.v2+json" \
    -d '{"records": [{"value": {"test": true}}]}')

if [ "$STATUS" = "200" ]; then
    echo -e "✅ application/vnd.kafka.json.v2+json accepted"
else
    echo -e "❌ application/vnd.kafka.json.v2+json returned $STATUS (expected 200)"
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
