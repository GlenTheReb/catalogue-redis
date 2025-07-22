package catalogue

import (
	"context"
	"time"

	"github.com/go-kit/kit/log"
)

// CachedService wraps the original catalogue service with Redis caching
type CachedService struct {
	next    Service
	cache   CatalogueCache
	logger  log.Logger
	metrics *CacheMetrics
}

// NewCachedService creates a new cached catalogue service
func NewCachedService(next Service, cache CatalogueCache, logger log.Logger) *CachedService {
	return &CachedService{
		next:    next,
		cache:   cache,
		logger:  logger,
		metrics: NewCacheMetrics(logger),
	}
}

// GetMetrics returns the metrics tracker for external access
func (s *CachedService) GetMetrics() *CacheMetrics {
	return s.metrics
}

func (s *CachedService) List(tags []string, order string, pageNum, pageSize int) ([]Sock, error) {
	ctx := context.Background()
	start := time.Now()

	// Try to get from cache first
	socks, found, err := s.cache.GetProducts(ctx, tags, order, pageNum, pageSize)
	if err != nil {
		s.logger.Log("cache_error", err, "operation", "List", "fallback", "database")
		s.metrics.RecordCacheError("List", time.Since(start))
		// On cache error, fall back to database
	} else if found {
		duration := time.Since(start)
		s.metrics.RecordCacheHit("List", duration)
		s.logger.Log(
			"cache_hit", "true",
			"operation", "List",
			"tags", tags,
			"order", order,
			"pageNum", pageNum,
			"pageSize", pageSize,
			"count", len(socks),
			"duration_ms", duration.Milliseconds(),
		)
		return socks, nil
	}

	// Cache miss - get from database
	s.logger.Log("cache_hit", "false", "operation", "List", "source", "database")
	socks, err = s.next.List(tags, order, pageNum, pageSize)
	duration := time.Since(start)
	
	if err != nil {
		s.metrics.RecordCacheMiss("List", duration)
		s.logger.Log(
			"operation", "List",
			"error", err,
			"duration_ms", duration.Milliseconds(),
		)
		return socks, err
	}

	s.metrics.RecordCacheMiss("List", duration)

	// Cache the result (fire-and-forget)
	go func() {
		cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		if cacheErr := s.cache.SetProducts(cacheCtx, tags, order, pageNum, pageSize, socks); cacheErr != nil {
			s.logger.Log("cache_set_error", cacheErr, "operation", "List")
		}
	}()

	s.logger.Log(
		"operation", "List",
		"source", "database",
		"cached", "true",
		"count", len(socks),
		"duration_ms", duration.Milliseconds(),
	)

	return socks, nil
}

func (s *CachedService) Count(tags []string) (int, error) {
	ctx := context.Background()
	start := time.Now()

	// Try to get from cache first
	count, found, err := s.cache.GetCount(ctx, tags)
	if err != nil {
		s.logger.Log("cache_error", err, "operation", "Count", "fallback", "database")
		s.metrics.RecordCacheError("Count", time.Since(start))
		// On cache error, fall back to database
	} else if found {
		duration := time.Since(start)
		s.metrics.RecordCacheHit("Count", duration)
		s.logger.Log(
			"cache_hit", "true",
			"operation", "Count",
			"tags", tags,
			"count", count,
			"duration_ms", duration.Milliseconds(),
		)
		return count, nil
	}

	// Cache miss - get from database
	s.logger.Log("cache_hit", "false", "operation", "Count", "source", "database")
	count, err = s.next.Count(tags)
	duration := time.Since(start)
	
	if err != nil {
		s.metrics.RecordCacheMiss("Count", duration)
		s.logger.Log(
			"operation", "Count",
			"error", err,
			"duration_ms", duration.Milliseconds(),
		)
		return count, err
	}

	s.metrics.RecordCacheMiss("Count", duration)

	// Cache the result (fire-and-forget)
	go func() {
		cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		if cacheErr := s.cache.SetCount(cacheCtx, tags, count); cacheErr != nil {
			s.logger.Log("cache_set_error", cacheErr, "operation", "Count")
		}
	}()

	s.logger.Log(
		"operation", "Count",
		"source", "database",
		"cached", "true",
		"count", count,
		"duration_ms", duration.Milliseconds(),
	)

	return count, nil
}

func (s *CachedService) Get(id string) (Sock, error) {
	ctx := context.Background()
	start := time.Now()

	// Try to get from cache first
	sock, found, err := s.cache.GetProduct(ctx, id)
	if err != nil {
		s.logger.Log("cache_error", err, "operation", "Get", "id", id, "fallback", "database")
		s.metrics.RecordCacheError("Get", time.Since(start))
		// On cache error, fall back to database
	} else if found {
		duration := time.Since(start)
		s.metrics.RecordCacheHit("Get", duration)
		s.logger.Log(
			"cache_hit", "true",
			"operation", "Get",
			"id", id,
			"product_name", sock.Name,
			"duration_ms", duration.Milliseconds(),
		)
		return sock, nil
	}

	// Cache miss - get from database
	s.logger.Log("cache_hit", "false", "operation", "Get", "id", id, "source", "database")
	sock, err = s.next.Get(id)
	duration := time.Since(start)
	
	if err != nil {
		s.metrics.RecordCacheMiss("Get", duration)
		s.logger.Log(
			"operation", "Get",
			"id", id,
			"error", err,
			"duration_ms", duration.Milliseconds(),
		)
		return sock, err
	}

	s.metrics.RecordCacheMiss("Get", duration)

	// Cache the result (fire-and-forget)
	go func() {
		cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		if cacheErr := s.cache.SetProduct(cacheCtx, id, sock); cacheErr != nil {
			s.logger.Log("cache_set_error", cacheErr, "operation", "Get", "id", id)
		}
	}()

	s.logger.Log(
		"operation", "Get",
		"id", id,
		"source", "database",
		"cached", "true",
		"product_name", sock.Name,
		"duration_ms", duration.Milliseconds(),
	)

	return sock, nil
}

func (s *CachedService) Tags() ([]string, error) {
	ctx := context.Background()
	start := time.Now()

	// Try to get from cache first
	tags, found, err := s.cache.GetTags(ctx)
	if err != nil {
		s.logger.Log("cache_error", err, "operation", "Tags", "fallback", "database")
		s.metrics.RecordCacheError("Tags", time.Since(start))
		// On cache error, fall back to database
	} else if found {
		duration := time.Since(start)
		s.metrics.RecordCacheHit("Tags", duration)
		s.logger.Log(
			"cache_hit", "true",
			"operation", "Tags",
			"count", len(tags),
			"duration_ms", duration.Milliseconds(),
		)
		return tags, nil
	}

	// Cache miss - get from database
	s.logger.Log("cache_hit", "false", "operation", "Tags", "source", "database")
	tags, err = s.next.Tags()
	duration := time.Since(start)
	
	if err != nil {
		s.metrics.RecordCacheMiss("Tags", duration)
		s.logger.Log(
			"operation", "Tags",
			"error", err,
			"duration_ms", duration.Milliseconds(),
		)
		return tags, err
	}

	s.metrics.RecordCacheMiss("Tags", duration)

	// Cache the result (fire-and-forget)
	go func() {
		cacheCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		
		if cacheErr := s.cache.SetTags(cacheCtx, tags); cacheErr != nil {
			s.logger.Log("cache_set_error", cacheErr, "operation", "Tags")
		}
	}()

	s.logger.Log(
		"operation", "Tags",
		"source", "database",
		"cached", "true",
		"count", len(tags),
		"duration_ms", duration.Milliseconds(),
	)

	return tags, nil
}

func (s *CachedService) Health() []Health {
	start := time.Now()
	
	// Get health from the original service
	health := s.next.Health()

	// Add Redis health check
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	
	redisStatus := "OK"
	if err := s.cache.Ping(ctx); err != nil {
		redisStatus = "err"
		s.logger.Log("redis_health_error", err)
	}

	redisHealth := Health{
		Service: "catalogue-redis",
		Status:  redisStatus,
		Time:    time.Now().String(),
	}

	health = append(health, redisHealth)

	duration := time.Since(start)
	s.logger.Log(
		"operation", "Health",
		"redis_status", redisStatus,
		"duration_ms", duration.Milliseconds(),
	)

	return health
}
