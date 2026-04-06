# Kafka HTTP-to-Kafka REST Proxy with Bento

A lightweight HTTP proxy that bridges [Confluent‑style REST Proxy](https://docs.confluent.io/platform/current/kafka-rest/api.html#post--topics-(string-topic_name)-partitions-(int-partition_id)) `/topics/...` produce requests from HTTP directly into Kafka, supporting both JSON and AVRO payloads with [Confluent Schema Registry](https://docs.confluent.io/platform/current/schema-registry/index.html).

## Features

- ✅ **Confluent REST Proxy API Compatible** - Drop-in replacement for `/topics/{topic}` and `/topics/{topic}/partitions/{partition}` endpoints
- ✅ **JSON & AVRO Support** - Automatic Schema Registry encoding with dynamic subject resolution
- ✅ **Production Hardened** - Compression, batching, retries, request size limits, proper error handling
- ✅ **Observability Ready** - Prometheus metrics, structured JSON logging, health checks
- ✅ **Secure by Default** - TLS, SASL authentication, Schema Registry auth support
- ✅ **High Performance** - Snappy compression, batching (100 msgs or 1MB or 100ms), async processing
- ✅ **Docker & Docker Compose** - Ready-to-run containerized deployment

---

## Architecture

Clients POST to:

- `POST /topics/{topic}`
- `POST /topics/{topic}/partitions/{partition}`

The request body must follow [Confluent REST Proxy v2’s](https://docs.confluent.io/platform/current/kafka-rest/api.html#post--topics-(string-topic_name)-partitions-(int-partition_id)) `records` format:

```json
{
  "records": [
    { "key": "msg-1", "value": { "foo": "bar" } },
    { "value": { "baz": "qux" }, "partition": 1 }
  ]
}
```

[Bento http_server](https://warpstreamlabs.github.io/bento/docs/components/inputs/http_server/):

1. Parses the HTTP request path and body.
2. Extracts topic and optional partition (from path or `partition` field).
3. Optionally encodes the `value` as AVRO using Schema Registry, with a dynamic subject derived from the topic (e.g. `orders-value`).
4. Publishes each record as a Kafka message.
5. Returns a synchronous JSON response compatible with the Confluent REST Proxy response shape.

---

## Dynamic Schema Registry subject

The Schema Registry subject is computed dynamically:

- Default: `${topic}-value`
  - e.g. `POST /topics/orders/...` → subject `orders-value`
- Override: via HTTP header `X-Schema-Subject`
  - `X-Schema-Subject: retail.orders.v1-value` → uses that subject instead

This lets you keep the same Bento config for many topics while still mapping to separate Schema Registry subjects.

---

## Input formats

The proxy accepts:

- JSON only:
  - `Content-Type: application/vnd.kafka.json.v2+json`
  - `Content-Type: application/json`
- AVRO with Schema Registry:
  - `Content-Type: application/vnd.kafka.avro.v2+json`

For AVRO, `schema_registry_encode` reaches out to Schema Registry, resolves the latest schema for the derived subject, and encodes the JSON payload against it.

---

## Response format

On success, Bento returns a `200` response with body like:

```json
{
  "key_schema_id": null,
  "value_schema_id": 1,
  "offsets": [
    { "partition": 0, "offset": -1, "error_code": null, "error": null }
  ]
}
```

On error, the HTTP status is set appropriately (e.g. `400`, `415`, `422`, `500`) and a Confluent‑style error JSON is returned explaining the issue.

> **Note:** `offset: -1` is a placeholder; the config cannot expose the real broker‑assigned offset into the HTTP body, but the message is still produced correctly to Kafka.

---

## Configuration

Environment variables (see `.env.example` for a complete template):

### HTTP Server
| Variable                | Default   | Description  |
|-------------------------|-----------|--------------|
| `HTTP_PROXY_HOST`       | `0.0.0.0` | Bind address |
| `HTTP_PROXY_PORT`       | `4195`    | HTTP port    |

### Kafka
| Variable                | Required | Description                                                                    |
|-------------------------|----------|--------------------------------------------------------------------------------|
| `KAFKA_BROKERS`         |    ✅    | Kafka bootstrap brokers (e.g., `pkc-xxxxx.us-east-1.aws.confluent.cloud:9092`) |
| `KAFKA_TLS_ENABLED`     |    ❌    | Enable TLS (default: `true`)                                                   |
| `KAFKA_SASL_MECHANISM`  |    ❌    | SASL mechanism (default: `PLAIN`)                                              |
| `KAFKA_API_KEY`         |    ✅    | SASL username (API key)                                                        |
| `KAFKA_API_SECRET`      |    ✅    | SASL password (API secret)                                                     |

### Schema Registry
| Variable                              | Required | Description                                                                    |
|---------------------------------------|----------|--------------------------------------------------------------------------------|
| `SCHEMA_REGISTRY_URL`                 |    ✅    | Schema Registry URL (e.g., `https://psrc-xxxxx.us-east-1.aws.confluent.cloud`) |
| `SCHEMA_REGISTRY_USERNAME`            |    ❌    | Schema Registry API key (required for Confluent Cloud)                         |
| `SCHEMA_REGISTRY_PASSWORD`            |    ❌    | Schema Registry API secret (required for Confluent Cloud)                      |

### Logging
| Variable                | Default | Description                                 |
|-------------------------|---------|---------------------------------------------|
| `LOG_LEVEL`             | `INFO`  | Log level: `DEBUG`, `INFO`, `WARN`, `ERROR` |

### Performance Tuning
| Variable                | Default    | Description                                                    |
|-------------------------|------------|----------------------------------------------------------------|
| `KAFKA_MAX_IN_FLIGHT`   | `10`       | Max concurrent writes to Kafka (1-50)                          |
| `KAFKA_BATCH_COUNT`     | `100`      | Max messages per batch                                         |
| `KAFKA_BATCH_SIZE`      | `1000000`  | Max batch size in bytes (1MB default)                          |
| `KAFKA_BATCH_PERIOD`    | `100ms`    | Max time to wait before flushing batch                         |
| `KAFKA_COMPRESSION`     | `snappy`   | Compression algorithm: `none`, `snappy`, `lz4`, `gzip`, `zstd` |

---

## Quick Start

### 1. Configure environment

```bash
# The start script will auto-create .env from .env.example
# Or manually copy and edit:
cp .env.example .env
nano .env  # Update KAFKA_BROKERS, KAFKA_API_KEY, KAFKA_API_SECRET, SCHEMA_REGISTRY_URL
```

### 2. Start the proxy

```bash
# Using the start script (recommended - validates config)
./start.sh

The start script will:
- Check if `.env` exists (creates from `.env.example` if missing)
- Validate required environment variables
- Start the proxy with Docker Compose

# Or directly with Docker Compose
docker compose up -d
```

### 3. Verify it's running

```bash
# Health check
curl http://localhost:4195/bento/ping

# Readiness check
curl http://localhost:4195/bento/ready

# Prometheus metrics
curl http://localhost:4195/bento/metrics

# Run JSON test suite (automatically loads config from .env)
./test.sh

# Run AVRO test suite (automatically loads config from .env, requires Schema Registry)
./test-avro.sh
```

---

## Common Commands

```bash
# View logs
docker compose logs -f

# Check for AVRO encoding errors (async validation failures)
docker compose logs bento-http-kafka-proxy | grep -E "error.*schema|error.*avro|processor_error"

# Stop the proxy
# Using the stop script (recommended)
./stop.sh

# Or directly with Docker Compose
docker compose down

# Restart
docker compose restart

# View metrics
curl http://localhost:4195/bento/metrics

# Send test message (JSON)
curl -X POST http://localhost:4195/topics/test-topic \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{"records": [{"value": {"test": "message"}}]}'

# Run tests
./test.sh         # JSON tests (no Schema Registry needed)
./test-avro.sh    # AVRO tests (requires Schema Registry)
```

---

## Example requests

### JSON produce to `/topics/orders`

```bash
curl -X POST http://localhost:4195/topics/orders \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{
    "records": [
      { "key": "order-1", "value": { "id": 1, "status": "NEW" } }
    ]
  }'
```

### JSON with explicit partition

```bash
curl -X POST http://localhost:4195/topics/orders/partitions/1 \
  -H "Content-Type: application/vnd.kafka.json.v2+json" \
  -d '{
    "records": [
      { "key": "order-2", "value": { "id": 2, "status": "PENDING" } }
    ]
  }'
```

### AVRO with dynamic subject `${topic}-value`

```bash
curl -X POST http://localhost:4195/topics/orders \
  -H "Content-Type: application/vnd.kafka.avro.v2+json" \
  -d '{
    "records": [
      { "value": { "id": 1, "status": "NEW" } }
    ]
  }'
```

### AVRO with explicit subject override

```bash
curl -X POST http://localhost:4195/topics/orders \
  -H "Content-Type: application/vnd.kafka.avro.v2+json" \
  -H "X-Schema-Subject: retail.orders.v1-value" \
  -d '{
    "records": [
      { "value": { "id": 1, "status": "NEW" } }
    ]
  }'
```

---

## Testing

### JSON Test Suite (`test.sh`)

Tests JSON payloads without Schema Registry:

```bash
# Configuration is loaded from .env automatically
./test.sh
```

**Tests included:**
- Health checks (`/bento/ping`, `/bento/ready`)
- Metrics endpoint
- JSON message to topic
- JSON message to specific partition
- Multiple records in one request
- Error handling (empty body, missing records array, unsupported content-type)
- Content-Type variations (`application/json`, `application/vnd.kafka.json.v2+json`)

All tests validate proper HTTP status codes (200, 400, 415) and response format.

### AVRO Test Suite (`test-avro.sh`)

Tests AVRO serialization with Schema Registry:

```bash
# Credentials are loaded from .env automatically
# Ensure .env has SCHEMA_REGISTRY_URL and credentials set
./test-avro.sh
```

**Tests included:**
- Schema Registry connectivity
- Register AVRO schema
- AVRO message with dynamic subject (`{topic}-value`)
- AVRO message to specific partition
- Multiple AVRO records
- Custom schema subject override (via `X-Schema-Subject` header)
- Schema validation errors (type mismatch, missing fields)*

\* **Note on AVRO validation**: Schema type mismatches and missing required fields are detected asynchronously after the HTTP response is sent. The proxy returns `200 OK` immediately to avoid timeout, but schema encoding errors are logged. Monitor logs for Schema Registry encoding failures in production.

---

## Production Deployment

### Performance Configuration

The proxy ships with balanced defaults suitable for most production workloads:

- **Compression**: Snappy (configurable via `KAFKA_COMPRESSION`)
- **Batching**: 100 messages, 1MB, or 100ms - whichever comes first (configurable via `KAFKA_BATCH_*`)
- **Concurrency**: `max_in_flight: 10` for parallel Kafka writes (configurable via `KAFKA_MAX_IN_FLIGHT`)
- **Request Limits**: 10MB max request size, 10,000 records per request
- **Timeouts**: 30s HTTP timeout, 30s Kafka write timeout

See [Performance Tuning](#performance-tuning) section for high-throughput and low-latency configurations.

### Security Best Practices

1. **Never expose port 4195 directly to the internet** - Always front with:
   - NGINX/Envoy with TLS termination
   - API Gateway with authentication
   - Service mesh (Istio, Linkerd)

2. **TLS Configuration**
   ```bash
   # Kafka TLS (enabled by default)
   KAFKA_TLS_ENABLED=true
   
   # Schema Registry uses TLS automatically for HTTPS URLs
   SCHEMA_REGISTRY_URL=https://psrc-xxxxx.us-east-1.aws.confluent.cloud
   ```

3. **Secrets Management**
   - Use Docker Secrets, Vault, or cloud secret managers
   - Never commit `.env` files to version control
   - Rotate credentials regularly

4. **Schema Registry Auth**
   ```bash
   # For Confluent Cloud
   SCHEMA_REGISTRY_URL=https://psrc-xxxxx.us-east-1.aws.confluent.cloud
   SCHEMA_REGISTRY_USERNAME=your-sr-api-key
   SCHEMA_REGISTRY_PASSWORD=your-sr-api-secret
   ```

### Monitoring & Observability

#### Health Checks

```bash
# Liveness probe - is the process alive?
curl http://localhost:4195/bento/ping

# Readiness probe - can it accept traffic?
curl http://localhost:4195/bento/ready
```

#### Prometheus Metrics

Available at `http://localhost:4195/bento/metrics`:

Key metrics to monitor:
- `input_received` - HTTP requests received
- `input_latency_ns` - Input processing latency
- `output_sent` - Messages sent to Kafka
- `output_error` - Kafka write failures
- `processor_error` - Processing errors (validation, encoding)
  - **Important**: Watch this for AVRO schema validation failures (type mismatches, missing fields)
  - These errors occur after `200 OK` response is sent

Example Prometheus scrape config:
```yaml
scrape_configs:
  - job_name: 'bento-http-kafka-proxy'
    static_configs:
      - targets: ['localhost:4195']
    metrics_path: '/bento/metrics'
```

#### Structured Logging

Logs are JSON-formatted for easy parsing:
```json
{
  "@service": "bento-http-kafka-proxy",
  "@timestamp": "2026-04-06T10:15:30Z",
  "level": "info",
  "message": "Listening for HTTP requests",
  "component": "http_server"
}
```

Set `LOG_LEVEL=DEBUG` for troubleshooting.

### Error Handling

The proxy maps errors to appropriate HTTP status codes:

| Status | Trigger                                                                                           |
|--------|---------------------------------------------------------------------------------------------------|
| `400 Bad Request`            | Empty body, missing topic, empty records array, >10K records, invalid JSON  |
| `401 Unauthorized`           | Kafka/SR authentication failure (logged, not returned to client)            |
| `413 Payload Too Large`      | Request > 10MB                                                              |
| `415 Unsupported Media Type` | Invalid Content-Type (not JSON or AVRO)                                     |
| `422 Unprocessable Entity`   | Schema Registry connection errors during validation                         |
| `504 Gateway Timeout`        | Kafka write timeout, HTTP request timeout                                   |
| `500 Internal Server Error`  | Other processing errors                                                     |

**Note on AVRO validation errors**: Detailed schema validation (type mismatches, missing fields) occurs asynchronously and won't fail the HTTP request. These errors are logged for monitoring. See [Limitations](#limitations--notes) for details.

### Limitations & Notes

1. **Offset Placeholder**: The HTTP response always returns `offset: -1` as a placeholder. The message IS written to Kafka successfully, but Bento cannot expose the broker-assigned offset in the sync response.

2. **Kafka Headers Not Supported**: The Confluent REST Proxy format includes a `headers` array in record payloads:
   ```json
   {
     "records": [{
       "value": {...},
       "headers": [{"name": "Header-1", "value": "base64-encoded-value"}]
     }]
   }
   ```
   **Headers are silently ignored** due to a Bento/Bloblang limitation - it cannot dynamically set metadata keys from variable names. Only the message `key` and `value` are sent to Kafka. The request will return `200 OK` but headers will be dropped. If you need header support, use Confluent's official REST Proxy.

3. **AVRO Schema Validation (Async)**: Detailed schema validation (type mismatches, missing required fields) happens asynchronously during AVRO encoding, after the HTTP response is sent. The proxy returns `200 OK` immediately to prevent timeout while waiting for Schema Registry. Invalid schemas will:
   - Return `200 OK` to the HTTP client
   - Fail during encoding and be logged as errors
   - Trigger the output fallback error handler
   - **Monitor `processor_error` and `output_error` metrics in production**

4. **Schema Must Exist**: For AVRO, schemas must exist in Schema Registry before sending messages (or enable auto-registration in SR).

5. **No Consumer Support**: This proxy only supports producing messages (Confluent REST Proxy POST endpoints).

6. **Synchronous Only**: Each HTTP request waits for Kafka acknowledgment before responding (at-least-once delivery).

---

## Troubleshooting

### Common Issues

#### 1. "Authentication failed" errors

```bash
# Verify Kafka credentials
docker compose exec bento-http-kafka-proxy sh -c 'echo $KAFKA_USERNAME'

# Test connectivity
docker compose logs bento-http-kafka-proxy | grep -i auth
```

**Solution**: Double-check `KAFKA_API_KEY` and `KAFKA_API_SECRET` are correct.

#### 2. "Schema not found" or AVRO encoding errors

```bash
# Verify schema exists
curl -u "$SCHEMA_REGISTRY_USERNAME:$SCHEMA_REGISTRY_PASSWORD" \
  "$SCHEMA_REGISTRY_URL/subjects/orders-value/versions/latest"

# Check logs for schema encoding errors (async validation)
docker compose logs bento-http-kafka-proxy | grep -i "schema\|avro\|encoding"
```

**Solution**: 
- Register schema first, or use `X-Schema-Subject` header to override subject name
- For type mismatches/missing fields: These return `200 OK` but fail during encoding (check logs)
- Monitor `processor_error` metric for encoding failures

#### 3. Connection timeouts to Kafka

```bash
# Check broker connectivity
docker compose exec bento-http-kafka-proxy sh -c \
  'nc -zv pkc-xxxxx.us-east-1.aws.confluent.cloud 9092'
```

**Solution**: Verify firewall rules, security groups allow outbound on port 9092.

#### 4. High latency

- Check batch settings in `bento-http-kafka-proxy.yaml`
- Monitor `latency_ns` metric
- Consider increasing `max_in_flight` for higher throughput
- Enable DEBUG logging to identify bottlenecks:
  ```bash
  LOG_LEVEL=DEBUG docker compose up
  ```

### Debugging Tips

1. **Enable debug logging**:
   ```bash
   LOG_LEVEL=DEBUG docker compose restart
   ```

2. **Test with curl verbose mode**:
   ```bash
   curl -v -X POST http://localhost:4195/topics/test-topic \
     -H "Content-Type: application/vnd.kafka.json.v2+json" \
     -d '{"records": [{"value": {"test": true}}]}'
   ```

3. **Check Bento health**:
   ```bash
   # Should return "pong"
   curl http://localhost:4195/bento/ping
   
   # Check all metrics
   curl http://localhost:4195/bento/metrics | grep -E "^[^#]" | grep -E "(error|sent|received)"
   ```

4. **Inspect Docker logs**:
   ```bash
   docker compose logs -f --tail=100 bento-http-kafka-proxy
   ```

## Advanced Configuration

### Rate Limiting

Add to `bento-http-kafka-proxy.yaml`:
```yaml
input:
  http_server:
    rate_limit: "100/s"  # 100 requests per second
```

### TLS Termination in Bento

To enable TLS directly in Bento (not recommended, use reverse proxy instead):
```yaml
http:
  cert_file: "/path/to/cert.pem"
  key_file: "/path/to/key.pem"
```

### Custom Partitioning

The proxy uses `murmur2_hash` partitioner by default for Java clients (Kafka's default). For manual partition assignment, use the partition field in the request or the path parameter.

### Multiple Environments

Create environment-specific config files:
```bash
docker compose --env-file .env.production up -d
```

## Performance Tuning

Performance settings are configurable via environment variables (defaults are balanced for general use).

### Balanced (Default) - Good for most use cases

```bash
# Already set as defaults, no changes needed
KAFKA_MAX_IN_FLIGHT=10
KAFKA_BATCH_COUNT=100
KAFKA_BATCH_SIZE=1000000      # 1MB
KAFKA_BATCH_PERIOD=100ms
KAFKA_COMPRESSION=snappy
```

### High Throughput (>10K msgs/sec)

```bash
# Add to .env or export before starting
KAFKA_MAX_IN_FLIGHT=50        # Increase parallelism
KAFKA_BATCH_COUNT=500         # Larger batches
KAFKA_BATCH_SIZE=5000000      # 5MB
KAFKA_BATCH_PERIOD=200ms      # Longer wait
KAFKA_COMPRESSION=lz4         # Faster than snappy

# Then restart
docker compose restart
```

### Low Latency (<10ms p99)

```bash
# Add to .env or export before starting
KAFKA_MAX_IN_FLIGHT=1         # Strict ordering, lower latency
KAFKA_BATCH_COUNT=10          # Smaller batches
KAFKA_BATCH_SIZE=100000       # 100KB
KAFKA_BATCH_PERIOD=10ms       # Quick flush
KAFKA_COMPRESSION=none        # Skip compression overhead

# Then restart
docker compose restart
```

### Resource Limits

Adjust in `docker-compose.yaml`:
```yaml
deploy:
  resources:
    limits:
      cpus: '2'        # 2 CPU cores
      memory: 1G       # 1GB RAM
```

## Scaling

### Horizontal Scaling

Deploy multiple instances behind a load balancer:
```bash
docker compose up -d --scale bento-http-kafka-proxy=3
```

Configure your load balancer (NGINX, HAProxy, AWS ALB) to distribute across instances.

### Vertical Scaling

Increase resources for high-volume single instance:
- 2+ CPU cores
- 1-2GB RAM
- SSD storage for Docker volumes

## License & Support

This is a reference implementation. For production support, consider:
- [Confluent Platform's official REST Proxy](https://docs.confluent.io/platform/current/kafka-rest/index.html)
- [Bento Documentation](https://warpstreamlabs.github.io/bento/)
- Community support via GitHub Issues
