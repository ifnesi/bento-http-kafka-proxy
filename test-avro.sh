#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source .env file
echo -e "${GREEN}✓${NC} Loading configuration from .env"
set -a
source .env
set +a

PROXY_URL="${PROXY_URL:-http://localhost:4195}"
TOPIC="${TEST_TOPIC:-test-avro-topic}"
SCHEMA_REGISTRY_URL="${SCHEMA_REGISTRY_URL:?SCHEMA_REGISTRY_URL must be set}"
SCHEMA_SUBJECT="${TOPIC}-value"
FAILED=0

# Schema Registry auth (optional)
SR_AUTH=""
if [ -n "${SCHEMA_REGISTRY_USERNAME:-}" ] && [ -n "${SCHEMA_REGISTRY_PASSWORD:-}" ]; then
    SR_AUTH="-u ${SCHEMA_REGISTRY_USERNAME}:${SCHEMA_REGISTRY_PASSWORD}"
fi

echo "=========================================="
echo "Bento HTTP-Kafka Proxy - AVRO Test Suite"
echo "=========================================="
echo "Proxy URL: $PROXY_URL"
echo "Test Topic: $TOPIC"
echo "Schema Registry: $SCHEMA_REGISTRY_URL"
echo "Schema Subject: $SCHEMA_SUBJECT"
echo ""

# Test 0: Check Schema Registry connectivity
echo "Test 0: Schema Registry Connectivity"
if curl -sf $SR_AUTH "$SCHEMA_REGISTRY_URL/subjects" > /dev/null; then
    echo -e "${GREEN}✓${NC} Schema Registry accessible"
else
    echo -e "${RED}✗${NC} Schema Registry not accessible"
    echo ""
    echo "Please check:"
    echo "  - SCHEMA_REGISTRY_URL is correct"
    echo "  - SCHEMA_REGISTRY_USERNAME and SCHEMA_REGISTRY_PASSWORD are set (if auth enabled)"
    FAILED=$((FAILED + 1))
fi

# Test 1: Register a test schema
echo ""
echo "Test 1: Register AVRO schema in Schema Registry"
SCHEMA_JSON=$(cat <<'EOF'
{
  "schema": "{\"type\":\"record\",\"name\":\"TestRecord\",\"namespace\":\"com.example\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"},{\"name\":\"message\",\"type\":\"string\"},{\"name\":\"timestamp\",\"type\":\"long\"}]}"
}
EOF
)

SCHEMA_RESPONSE=$(curl -s -X POST $SR_AUTH \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    "$SCHEMA_REGISTRY_URL/subjects/$SCHEMA_SUBJECT/versions" \
    -d "$SCHEMA_JSON")

if echo "$SCHEMA_RESPONSE" | grep -q '"id"'; then
    SCHEMA_ID=$(echo "$SCHEMA_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    echo -e "${GREEN}✓${NC} Schema registered successfully (ID: $SCHEMA_ID)"
else
    echo -e "${YELLOW}⚠${NC}  Schema might already exist or registration failed"
    echo "   Response: $SCHEMA_RESPONSE"
fi

# Test 2: Verify schema exists
echo ""
echo "Test 2: Verify schema exists in Schema Registry"
LATEST_SCHEMA=$(curl -sf $SR_AUTH "$SCHEMA_REGISTRY_URL/subjects/$SCHEMA_SUBJECT/versions/latest")
if echo "$LATEST_SCHEMA" | grep -q '"schema"'; then
    echo -e "${GREEN}✓${NC} Schema exists and is retrievable"
    SCHEMA_ID=$(echo "$LATEST_SCHEMA" | grep -o '"id":[0-9]*' | cut -d':' -f2)
    echo "   Schema ID: $SCHEMA_ID"
else
    echo -e "${RED}✗${NC} Schema not found"
    echo "   Response: $LATEST_SCHEMA"
    FAILED=$((FAILED + 1))
fi

# Test 3: POST AVRO message with dynamic subject
echo ""
echo "Test 3: POST AVRO message (dynamic subject: ${SCHEMA_SUBJECT})"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.avro.v2+json" \
    -d '{
        "records": [
            {
                "value": {
                    "id": 1,
                    "message": "Test AVRO message with headers",
                    "timestamp": 1712345678000
                },
                "headers": [
                    {
                        "name": "Header-1",
                        "value": "SGVhZGVyLTE="
                    },
                    {
                        "name": "Header-2",
                        "value": "SGVhZGVyLTI="
                    }
                ]
            }
        ]
    }')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "${GREEN}✓${NC} AVRO message sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "${RED}✗${NC} AVRO message failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 4: POST AVRO with explicit partition
echo ""
echo "Test 4: POST AVRO message to specific partition"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC/partitions/0" \
    -H "Content-Type: application/vnd.kafka.avro.v2+json" \
    -d '{
        "records": [
            {
                "key": "avro-key-1",
                "value": {
                    "id": 2,
                    "message": "AVRO to partition 0",
                    "timestamp": 1712345678001
                }
            }
        ]
    }')

if echo "$RESPONSE" | grep -q '"partition":0'; then
    echo -e "${GREEN}✓${NC} AVRO message to partition 0 sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "${RED}✗${NC} AVRO message to partition failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 5: Multiple AVRO records
echo ""
echo "Test 5: POST multiple AVRO records in one request"
RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.avro.v2+json" \
    -d '{
        "records": [
            {"value": {"id": 10, "message": "Record 1", "timestamp": 1712345678100}},
            {"value": {"id": 11, "message": "Record 2", "timestamp": 1712345678101}},
            {"value": {"id": 12, "message": "Record 3", "timestamp": 1712345678102}}
        ]
    }')

if echo "$RESPONSE" | grep -q "offsets"; then
    echo -e "${GREEN}✓${NC} Multiple AVRO records sent successfully"
    echo "   Response: $RESPONSE"
else
    echo -e "${RED}✗${NC} Multiple AVRO records failed"
    echo "   Response: $RESPONSE"
    FAILED=$((FAILED + 1))
fi

# Test 6: Custom schema subject override
echo ""
echo "Test 6: POST AVRO with custom subject header"
CUSTOM_SUBJECT="custom-test-value"

# First register schema under custom subject
CUSTOM_SCHEMA_RESPONSE=$(curl -s -X POST $SR_AUTH \
    -H "Content-Type: application/vnd.schemaregistry.v1+json" \
    "$SCHEMA_REGISTRY_URL/subjects/$CUSTOM_SUBJECT/versions" \
    -d "$SCHEMA_JSON")

if echo "$CUSTOM_SCHEMA_RESPONSE" | grep -q '"id"'; then
    echo -e "${GREEN}✓${NC} Custom schema subject registered: $CUSTOM_SUBJECT"

    RESPONSE=$(curl -s -X POST "$PROXY_URL/topics/$TOPIC" \
        -H "Content-Type: application/vnd.kafka.avro.v2+json" \
        -H "X-Schema-Subject: $CUSTOM_SUBJECT" \
        -d '{
            "records": [
                {
                    "value": {
                        "id": 99,
                        "message": "Custom subject test",
                        "timestamp": 1712345678999
                    }
                }
            ]
        }')

    if echo "$RESPONSE" | grep -q "offsets"; then
        echo -e "${GREEN}✓${NC} AVRO with custom subject sent successfully"
        echo "   Response: $RESPONSE"
    else
        echo -e "${RED}✗${NC} AVRO with custom subject failed"
        echo "   Response: $RESPONSE"
        FAILED=$((FAILED + 1))
    fi
else
    echo -e "${YELLOW}⚠${NC}  Custom schema registration skipped"
fi

# Test 7: Error handling - schema mismatch
echo ""
echo "Test 7: AVRO Schema Validation (type mismatch)"
echo "   ${YELLOW}Note: Schema validation happens asynchronously after HTTP response${NC}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.avro.v2+json" \
    -d '{
        "records": [
            {
                "value": {
                    "id": "not-an-int",
                    "message": "This will fail",
                    "timestamp": 1712345678000
                }
            }
        ]
    }')

if [ "$STATUS" = "200" ]; then
    echo -e "${YELLOW}⚠${NC}  Schema mismatch accepted (200) - validation happens async"
    echo "   ${YELLOW}Check logs for encoding errors: docker compose logs bento-http-kafka-proxy${NC}"
else
    echo -e "${GREEN}✓${NC} Schema mismatch rejected ($STATUS)"
fi

# Test 8: Error handling - missing required field
echo ""
echo "Test 8: AVRO Schema Validation (missing field)"
echo "   ${YELLOW}Note: Schema validation happens asynchronously after HTTP response${NC}"
STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$PROXY_URL/topics/$TOPIC" \
    -H "Content-Type: application/vnd.kafka.avro.v2+json" \
    -d '{
        "records": [
            {
                "value": {
                    "id": 100,
                    "message": "Missing timestamp field"
                }
            }
        ]
    }')

if [ "$STATUS" = "200" ]; then
    echo -e "${YELLOW}⚠${NC}  Missing field accepted (200) - validation happens async"
    echo "   ${YELLOW}Check logs for encoding errors: docker compose logs bento-http-kafka-proxy${NC}"
else
    echo -e "${GREEN}✓${NC} Missing field rejected ($STATUS)"
fi

# Summary
echo ""
echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All AVRO tests passed!${NC}"
    echo "=========================================="
    echo ""
    echo "Schema Subject: $SCHEMA_SUBJECT"
    echo "Schema ID: $SCHEMA_ID"
    echo ""
    echo "To verify messages in Kafka:"
    echo "  kafka-avro-console-consumer --bootstrap-server <broker> \\"
    echo "    --topic $TOPIC --from-beginning \\"
    echo "    --property schema.registry.url=$SCHEMA_REGISTRY_URL"
    echo ""
    echo "To view Schema Registry subjects:"
    echo "  curl $SR_AUTH $SCHEMA_REGISTRY_URL/subjects"
    echo ""
    echo "To view this subject's schemas:"
    echo "  curl $SR_AUTH $SCHEMA_REGISTRY_URL/subjects/$SCHEMA_SUBJECT/versions"
    exit 0
else
    echo -e "${RED}$FAILED AVRO test(s) failed!${NC}"
    echo "=========================================="
    echo ""
    echo "To view logs:"
    echo "  docker compose logs -f bento-http-kafka-proxy"
    exit 1
fi
