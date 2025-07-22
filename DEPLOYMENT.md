# Redis-Enhanced Sock Shop Deployment Guide

## Overview
This project integrates Redis caching into the Sock Shop microservices application, specifically enhancing the catalogue and cart services with improved performance through intelligent caching.

## Docker Hub Images
The enhanced catalogue service has been published to Docker Hub:
- **Image**: `glenthereb/catalogue-redis:latest`
- **Features**: Redis caching for products, categories, tags, and search results

## Quick Deployment

### Using Docker Hub Image (Recommended)
```powershell
# Start the full application stack
docker-compose -f docker-compose-application.yml up -d

# Check container status
docker-compose -f docker-compose-application.yml ps

# Test the application
# Web UI: http://localhost
# API: http://localhost/catalogue
```

### Building Locally (Alternative)
```powershell
# Build and deploy locally
docker-compose -f docker-compose.yml up -d --build
```

## Architecture
- **Catalogue Service**: Enhanced with Redis caching (LRU eviction, 256MB memory limit)
- **Cart Service**: Uses Redis for session storage
- **Redis**: Configured without persistence for optimal performance
- **Cache Keys**: Intelligent key naming with TTL management

## Performance Benefits
- ~23% reduction in API response times
- Reduced database load
- Improved user experience for frequent queries
- Automatic cache warming for popular products

## Testing Cache Performance
```powershell
# Run performance tests
.\test_cache_performance.ps1

# Monitor Redis cache
docker exec catalogue-redis-redis-1 redis-cli KEYS "*"
docker exec catalogue-redis-redis-1 redis-cli INFO memory
```

## Configuration
- Redis Memory Limit: 256MB
- Cache Eviction Policy: LRU (Least Recently Used)
- Default TTL: 10 minutes for products, 5 minutes for lists
- Health Checks: Enabled for all services

## Troubleshooting
- Check container logs: `docker-compose -f docker-compose-application.yml logs catalogue`
- Verify Redis connectivity: `docker exec catalogue-redis-redis-1 redis-cli ping`
- Monitor cache hit rates: `docker exec catalogue-redis-redis-1 redis-cli INFO stats`

## Repository
- Source: https://github.com/GlenTheReb/catalogue-redis
- Docker Hub: https://hub.docker.com/repository/docker/glenthereb/catalogue-redis
