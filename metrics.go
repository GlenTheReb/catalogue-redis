package catalogue

import (
	"sync"
	"time"

	"github.com/go-kit/kit/log"
)

// CacheMetrics tracks cache performance metrics
type CacheMetrics struct {
	mu sync.RWMutex
	
	// Hit/Miss counters
	totalRequests int64
	cacheHits     int64
	cacheMisses   int64
	cacheErrors   int64
	
	// Response time tracking
	totalResponseTime time.Duration
	cacheResponseTime time.Duration
	dbResponseTime    time.Duration
	
	// Operation counters
	listRequests    int64
	getRequests     int64
	countRequests   int64
	tagsRequests    int64
	
	logger log.Logger
}

// NewCacheMetrics creates a new metrics tracker
func NewCacheMetrics(logger log.Logger) *CacheMetrics {
	return &CacheMetrics{
		logger: logger,
	}
}

// RecordCacheHit records a cache hit with response time
func (m *CacheMetrics) RecordCacheHit(operation string, duration time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	m.totalRequests++
	m.cacheHits++
	m.totalResponseTime += duration
	m.cacheResponseTime += duration
	
	m.incrementOperationCounter(operation)
}

// RecordCacheMiss records a cache miss with response time
func (m *CacheMetrics) RecordCacheMiss(operation string, duration time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	m.totalRequests++
	m.cacheMisses++
	m.totalResponseTime += duration
	m.dbResponseTime += duration
	
	m.incrementOperationCounter(operation)
}

// RecordCacheError records a cache error
func (m *CacheMetrics) RecordCacheError(operation string, duration time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	
	m.totalRequests++
	m.cacheErrors++
	m.totalResponseTime += duration
	m.dbResponseTime += duration
	
	m.incrementOperationCounter(operation)
}

func (m *CacheMetrics) incrementOperationCounter(operation string) {
	switch operation {
	case "List":
		m.listRequests++
	case "Get":
		m.getRequests++
	case "Count":
		m.countRequests++
	case "Tags":
		m.tagsRequests++
	}
}

// GetMetrics returns current metrics snapshot
func (m *CacheMetrics) GetMetrics() MetricsSnapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	
	hitRatio := float64(0)
	if m.totalRequests > 0 {
		hitRatio = float64(m.cacheHits) / float64(m.totalRequests) * 100
	}
	
	avgResponseTime := time.Duration(0)
	if m.totalRequests > 0 {
		avgResponseTime = m.totalResponseTime / time.Duration(m.totalRequests)
	}
	
	avgCacheResponseTime := time.Duration(0)
	if m.cacheHits > 0 {
		avgCacheResponseTime = m.cacheResponseTime / time.Duration(m.cacheHits)
	}
	
	avgDbResponseTime := time.Duration(0)
	dbRequests := m.cacheMisses + m.cacheErrors
	if dbRequests > 0 {
		avgDbResponseTime = m.dbResponseTime / time.Duration(dbRequests)
	}
	
	return MetricsSnapshot{
		TotalRequests:        m.totalRequests,
		CacheHits:            m.cacheHits,
		CacheMisses:          m.cacheMisses,
		CacheErrors:          m.cacheErrors,
		HitRatio:             hitRatio,
		AvgResponseTime:      avgResponseTime,
		AvgCacheResponseTime: avgCacheResponseTime,
		AvgDbResponseTime:    avgDbResponseTime,
		ListRequests:         m.listRequests,
		GetRequests:          m.getRequests,
		CountRequests:        m.countRequests,
		TagsRequests:         m.tagsRequests,
	}
}

// LogMetrics logs current metrics
func (m *CacheMetrics) LogMetrics() {
	metrics := m.GetMetrics()
	
	m.logger.Log(
		"metrics", "cache_performance",
		"total_requests", metrics.TotalRequests,
		"cache_hits", metrics.CacheHits,
		"cache_misses", metrics.CacheMisses,
		"cache_errors", metrics.CacheErrors,
		"hit_ratio_percent", metrics.HitRatio,
		"avg_response_time_ms", metrics.AvgResponseTime.Milliseconds(),
		"avg_cache_response_time_ms", metrics.AvgCacheResponseTime.Milliseconds(),
		"avg_db_response_time_ms", metrics.AvgDbResponseTime.Milliseconds(),
		"list_requests", metrics.ListRequests,
		"get_requests", metrics.GetRequests,
		"count_requests", metrics.CountRequests,
		"tags_requests", metrics.TagsRequests,
	)
}

// StartPeriodicLogging starts periodic metrics logging
func (m *CacheMetrics) StartPeriodicLogging(interval time.Duration) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			m.LogMetrics()
		}
	}()
	
	m.logger.Log("metrics", "periodic_logging_started", "interval_seconds", interval.Seconds())
}

// MetricsSnapshot represents a point-in-time view of cache metrics
type MetricsSnapshot struct {
	TotalRequests        int64
	CacheHits            int64
	CacheMisses          int64
	CacheErrors          int64
	HitRatio             float64
	AvgResponseTime      time.Duration
	AvgCacheResponseTime time.Duration
	AvgDbResponseTime    time.Duration
	ListRequests         int64
	GetRequests          int64
	CountRequests        int64
	TagsRequests         int64
}

// MetricsMiddleware wraps a service with performance metrics collection
type metricsMiddleware struct {
	next    Service
	metrics *CacheMetrics
}

// NewMetricsMiddleware creates a new metrics middleware
func NewMetricsMiddleware(metrics *CacheMetrics) Middleware {
	return func(next Service) Service {
		return &metricsMiddleware{
			next:    next,
			metrics: metrics,
		}
	}
}

func (mw *metricsMiddleware) List(tags []string, order string, pageNum, pageSize int) ([]Sock, error) {
	start := time.Now()
	defer func() {
		// Note: This middleware should be applied after the cached service
		// The actual cache hit/miss recording is done in the cached service
		duration := time.Since(start)
		mw.metrics.logger.Log("operation", "List", "total_duration_ms", duration.Milliseconds())
	}()
	
	return mw.next.List(tags, order, pageNum, pageSize)
}

func (mw *metricsMiddleware) Count(tags []string) (int, error) {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		mw.metrics.logger.Log("operation", "Count", "total_duration_ms", duration.Milliseconds())
	}()
	
	return mw.next.Count(tags)
}

func (mw *metricsMiddleware) Get(id string) (Sock, error) {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		mw.metrics.logger.Log("operation", "Get", "total_duration_ms", duration.Milliseconds())
	}()
	
	return mw.next.Get(id)
}

func (mw *metricsMiddleware) Tags() ([]string, error) {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		mw.metrics.logger.Log("operation", "Tags", "total_duration_ms", duration.Milliseconds())
	}()
	
	return mw.next.Tags()
}

func (mw *metricsMiddleware) Health() []Health {
	start := time.Now()
	defer func() {
		duration := time.Since(start)
		mw.metrics.logger.Log("operation", "Health", "total_duration_ms", duration.Milliseconds())
	}()
	
	health := mw.next.Health()
	
	// Add metrics to health response
	metrics := mw.metrics.GetMetrics()
	metricsHealth := Health{
		Service: "catalogue-metrics",
		Status:  "OK",
		Time:    time.Now().String(),
	}
	
	// Log current performance stats
	mw.metrics.logger.Log(
		"health_check", "metrics",
		"hit_ratio_percent", metrics.HitRatio,
		"total_requests", metrics.TotalRequests,
		"avg_response_time_ms", metrics.AvgResponseTime.Milliseconds(),
	)
	
	return append(health, metricsHealth)
}
