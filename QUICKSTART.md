# Quick Start Guide: Catalogue Service with Redis Caching

This guide will help you quickly deploy and test the Redis-optimized catalogue service.

## Prerequisites

- Docker and Docker Compose installed
- Git (optional, for cloning)
- curl (for testing)

## Single Docker Compose File
We now use **one consolidated `docker-compose.yml`** that includes everything you need.

## Quick Deployment

### 1. Start the Services

```bash
# Start all services (catalogue, database, Redis)
docker-compose up -d

# Check service status
docker-compose ps

# Wait for services to be healthy (about 30-60 seconds)
docker-compose logs catalogue
```

Expected output should show cache warming starting:
```
cache_warming=started
cache_warming=tags_completed count=9
cache_warming=listings_completed
```

### 2. Test the Service

```bash
# Basic health check
curl http://localhost:8080/health

# Test product listing (should show cache miss first, then hits)
curl "http://localhost:8080/catalogue?size=6"

# Test individual product
curl "http://localhost:8080/catalogue/6d62d909-f957-430e-8689-b5129c0bb75e"
```

### 3. Monitor Cache Performance

```bash
# Watch real-time logs for cache hits/misses
docker-compose logs -f catalogue

# Look for entries like:
# cache_hit=true operation=List duration_ms=2
# cache_hit=false operation=List source=database duration_ms=45
```

## Performance Testing

### Quick Manual Test
```bash
# First request (cache miss)
time curl -s "http://localhost:8080/catalogue?size=6" > /dev/null

# Second request (cache hit)  
time curl -s "http://localhost:8080/catalogue?size=6" > /dev/null
```

### Automated Performance Test
```bash
# Run comprehensive performance tests
./scripts/test-performance.sh

# Custom test parameters
./scripts/test-performance.sh --url http://localhost:8080 --concurrent 20 --total 2000
```

Expected results after cache warming:
- **Cache hit ratio**: 80%+
- **Cached response times**: 1-4ms
- **Database response times**: 20-50ms
- **Overall improvement**: 15-20x faster

## API Endpoints

| Endpoint | Description | Cache Key Pattern |
|----------|-------------|-------------------|
| `GET /catalogue` | List products with pagination/filtering | `catalogue:products:*` |
| `GET /catalogue/{id}` | Get individual product | `catalogue:product:{id}` |
| `GET /catalogue/size` | Count products | `catalogue:count:*` |
| `GET /tags` | Available tags | `catalogue:tags:all` |
| `GET /health` | Service health | Not cached |

### Example API Calls

```bash
# List all products (first page, 6 items)
curl "http://localhost:8080/catalogue?size=6"

# Filter by tag
curl "http://localhost:8080/catalogue?tags=brown&size=6"

# Get product count
curl "http://localhost:8080/catalogue/size"

# Get count for specific tag
curl "http://localhost:8080/catalogue/size?tags=geek"

# Get all available tags
curl "http://localhost:8080/tags"

# Health check (includes cache metrics)
curl "http://localhost:8080/health"
```

## Cache Metrics

Check cache performance in service logs:
```bash
docker-compose logs catalogue | grep "hit_ratio"
```

Every 5 minutes you'll see metrics like:
```
metrics=cache_performance total_requests=1250 cache_hits=1063 cache_misses=187 hit_ratio_percent=85.04 avg_response_time_ms=3.2
```

## Inspecting Redis Cache (Optional)

If you need to inspect the Redis cache directly:

```bash
# Connect to Redis CLI
docker-compose exec redis redis-cli

# List all catalogue cache keys
KEYS catalogue:*

# Get a specific cached product
GET "catalogue:product:6d62d909-f957-430e-8689-b5129c0bb75e"

# Check cache statistics
INFO memory
INFO stats

# Exit Redis CLI
exit
```

## Troubleshooting

### Services Won't Start
```bash
# Check all services
docker-compose ps

# Check specific service logs
docker-compose logs catalogue
docker-compose logs redis
docker-compose logs catalogue-db

# Restart a specific service
docker-compose restart catalogue
```

### Poor Cache Performance
1. **Check Redis connectivity**:
   ```bash
   docker-compose logs redis
   docker-compose exec redis redis-cli ping
   ```

2. **Verify cache warming completed**:
   ```bash
   docker-compose logs catalogue | grep cache_warming
   ```

3. **Check Redis memory usage**:
   ```bash
   docker-compose exec redis redis-cli info memory
   ```

### Database Issues
```bash
# Check database health
docker-compose exec catalogue-db mysqladmin ping

# Check database logs
docker-compose logs catalogue-db
```

### Reset Everything
```bash
# Stop services
docker-compose down

# Remove volumes (fresh start)
docker-compose down -v

# Rebuild and restart
docker-compose up -d --build
```

## Development Mode

For development, you can run the catalogue service locally while using containerized dependencies:

```bash
# Start only dependencies
docker-compose up -d catalogue-db redis

# Run service locally
go run cmd/cataloguesvc/main.go \
  -redis=localhost:6379 \
  -DSN="catalogue_user:default_password@tcp(localhost:3306)/socksdb" \
  -port=8080
```

## Building Custom Images

```bash
# Build with default settings
./scripts/build-redis.sh

# Build with custom tag
./scripts/build-redis.sh --tag v1.0.0

# Build and push to registry
./scripts/build-redis.sh --registry your-registry/catalogue-redis --tag v1.0.0 --push
```

## Production Considerations

When deploying to production:

1. **External Dependencies**: Use managed Redis and MySQL services
2. **Resource Limits**: Set appropriate CPU/memory limits
3. **Monitoring**: Integrate with your monitoring stack
4. **Security**: Enable Redis AUTH, use TLS, network policies
5. **Scaling**: Consider Redis clustering for high availability
6. **Backup**: Implement backup strategies for both Redis and MySQL

---

**Expected Performance**: 15-20x faster response times with 80%+ cache hit ratio and 87% reduction in database load.
```

### 2. Wait for Services to be Ready

```bash
# Check health status
curl http://localhost:8080/health

# You should see Redis and database status as "OK"
```

### 3. Test the Cache Performance

#### Basic Functionality Test
```bash
# Get all products (first request - cache miss)
curl "http://localhost:8080/catalogue?size=6"

# Get all products again (second request - cache hit, should be faster)
curl "http://localhost:8080/catalogue?size=6"

# Get individual product
curl "http://localhost:8080/catalogue/6d62d909-f957-430e-8689-b5129c0bb75e"

# Get product count
curl "http://localhost:8080/catalogue/size"

# Get available tags
curl "http://localhost:8080/tags"
```

#### Performance Comparison
```bash
# Run the automated performance test
chmod +x scripts/test-performance.sh
./scripts/test-performance.sh
```

### 4. Monitor Cache Performance

#### View Service Logs
```bash
# View catalogue service logs (includes cache hit/miss information)
docker-compose -f docker-compose-redis.yml logs -f catalogue-redis
```

#### Inspect Redis Cache (Optional)
```bash
# Start Redis Commander for cache inspection
docker-compose -f docker-compose-redis.yml --profile tools up -d redis-commander

# Access Redis Commander at http://localhost:8081
# Login: admin / redis123
```

#### Check Cache Contents Directly
```bash
# Connect to Redis CLI
docker exec -it catalogue-redis-cache redis-cli

# List all catalogue cache keys
KEYS catalogue:*

# Get a specific cached product
GET "catalogue:product:6d62d909-f957-430e-8689-b5129c0bb75e"

# Check cache statistics
INFO memory
INFO stats
```

## Expected Performance Results

After cache warming (first few requests), you should see:

### Response Times
- **Cached requests**: 1-4ms (80%+ of requests)
- **Database requests**: 6-50ms (20% of requests)
- **Overall improvement**: 10-20x faster

### Cache Metrics (from logs)
```
cache_hit=true operation=List duration_ms=2
cache_hit=false operation=List duration_ms=35 source=database
metrics cache_performance hit_ratio_percent=85.2 avg_response_time_ms=3.1
```

## Testing Different Scenarios

### 1. Test Cache Warming
```bash
# Restart the service to test cache warming
docker-compose -f docker-compose-redis.yml restart catalogue-redis

# Watch logs to see cache warming in action
docker-compose -f docker-compose-redis.yml logs -f catalogue-redis
```

### 2. Test Cache Invalidation
```bash
# Redis cache will expire after 30 minutes
# Or manually flush cache:
docker exec -it catalogue-redis-cache redis-cli FLUSHDB
```

### 3. Load Testing
```bash
# Run concurrent requests to test cache under load
for i in {1..100}; do
  curl -s "http://localhost:8080/catalogue?size=6" > /dev/null &
done
wait

# Check the logs for hit ratio
docker-compose -f docker-compose-redis.yml logs catalogue-redis | grep "hit_ratio"
```

## API Endpoints

All original endpoints work exactly the same, with caching transparent to clients:

- `GET /catalogue` - List products with optional filtering
- `GET /catalogue/{id}` - Get individual product
- `GET /catalogue/size` - Get product count
- `GET /tags` - Get available tags
- `GET /health` - Service health (includes Redis status)

### Example API Calls

```bash
# Get first page of products
curl "http://localhost:8080/catalogue?size=6&page=1"

# Filter by tags
curl "http://localhost:8080/catalogue?tags=brown&size=6"

# Sort by price
curl "http://localhost:8080/catalogue?order=price&size=6"

# Get specific product
curl "http://localhost:8080/catalogue/a0a4f044-b040-410d-8ead-4de0446aec7e"

# Count products with filter
curl "http://localhost:8080/catalogue/size?tags=brown"
```

## Troubleshooting

### Service Won't Start
```bash
# Check all services
docker-compose -f docker-compose-redis.yml ps

# Check logs
docker-compose -f docker-compose-redis.yml logs

# Restart problematic service
docker-compose -f docker-compose-redis.yml restart catalogue-redis
```

### Redis Connection Issues
```bash
# Test Redis connectivity
docker exec -it catalogue-redis-cache redis-cli ping

# Check Redis logs
docker-compose -f docker-compose-redis.yml logs redis
```

### Poor Cache Performance
```bash
# Check if cache is working
docker exec -it catalogue-redis-cache redis-cli
> KEYS catalogue:*
> INFO stats

# Verify service is using Redis
docker-compose -f docker-compose-redis.yml logs catalogue-redis | grep redis
```

## Cleanup

```bash
# Stop all services
docker-compose -f docker-compose-redis.yml down

# Remove volumes (will delete database and cache data)
docker-compose -f docker-compose-redis.yml down -v

# Remove images
docker rmi catalogue-redis:latest
```

## Building Custom Image

```bash
# Build locally
./scripts/build-redis.sh

# Build and push to registry
./scripts/build-redis.sh --registry your-registry.com/your-project --push
```

## Next Steps

1. **Production Deployment**: Update docker-compose for production with proper secrets management
2. **Monitoring**: Add Prometheus/Grafana for detailed metrics
3. **Scaling**: Deploy multiple catalogue instances behind a load balancer
4. **Cache Tuning**: Adjust TTL and memory limits based on usage patterns

## Performance Validation

To validate the 15-20x performance improvement:

1. Deploy the service
2. Run the performance test script
3. Compare cached vs non-cached response times
4. Monitor cache hit ratio (should be 80%+)
5. Check database load reduction in logs

The cache should provide sub-5ms response times for 80%+ of requests, compared to 20-50ms for database queries.
