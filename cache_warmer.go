package catalogue

import (
	"context"
	"time"

	"github.com/go-kit/kit/log"
)

// CacheWarmer handles cache pre-population strategies
type CacheWarmer struct {
	service Service
	cache   CatalogueCache
	logger  log.Logger
}

// NewCacheWarmer creates a new cache warming utility
func NewCacheWarmer(service Service, cache CatalogueCache, logger log.Logger) *CacheWarmer {
	return &CacheWarmer{
		service: service,
		cache:   cache,
		logger:  logger,
	}
}

// WarmCache pre-populates the cache with commonly accessed data
func (w *CacheWarmer) WarmCache() {
	ctx := context.Background()
	start := time.Now()
	
	w.logger.Log("cache_warming", "started")

	// Warm tags cache
	go w.warmTags(ctx)
	
	// Warm popular product listings
	go w.warmProductListings(ctx)
	
	// Warm individual products (first page of all products)
	go w.warmIndividualProducts(ctx)

	w.logger.Log("cache_warming", "initiated", "duration_ms", time.Since(start).Milliseconds())
}

func (w *CacheWarmer) warmTags(ctx context.Context) {
	start := time.Now()
	
	tags, err := w.service.Tags()
	if err != nil {
		w.logger.Log("cache_warming", "tags_error", "error", err)
		return
	}

	if err := w.cache.SetTags(ctx, tags); err != nil {
		w.logger.Log("cache_warming", "tags_cache_error", "error", err)
		return
	}

	w.logger.Log("cache_warming", "tags_completed", "count", len(tags), "duration_ms", time.Since(start).Milliseconds())
}

func (w *CacheWarmer) warmProductListings(ctx context.Context) {
	start := time.Now()
	
	// Common listing patterns to warm
	listings := []struct {
		tags     []string
		order    string
		pageNum  int
		pageSize int
	}{
		{[]string{}, "", 1, 6},     // First page, no filters
		{[]string{}, "", 1, 12},    // First page, larger size
		{[]string{}, "price", 1, 6}, // Sorted by price
		{[]string{}, "name", 1, 6},  // Sorted by name
		{[]string{"brown"}, "", 1, 6}, // Filtered by popular tag
		{[]string{"blue"}, "", 1, 6},  // Filtered by popular tag
		{[]string{"geek"}, "", 1, 6},  // Filtered by popular tag
	}

	for _, listing := range listings {
		func(l struct {
			tags     []string
			order    string
			pageNum  int
			pageSize int
		}) {
			listStart := time.Now()
			
			products, err := w.service.List(l.tags, l.order, l.pageNum, l.pageSize)
			if err != nil {
				w.logger.Log("cache_warming", "listing_error", "error", err, "tags", l.tags)
				return
			}

			if err := w.cache.SetProducts(ctx, l.tags, l.order, l.pageNum, l.pageSize, products); err != nil {
				w.logger.Log("cache_warming", "listing_cache_error", "error", err, "tags", l.tags)
				return
			}

			// Also warm the count for this filter
			count, err := w.service.Count(l.tags)
			if err == nil {
				w.cache.SetCount(ctx, l.tags, count)
			}

			w.logger.Log(
				"cache_warming", "listing_completed",
				"tags", l.tags,
				"order", l.order,
				"pageNum", l.pageNum,
				"pageSize", l.pageSize,
				"count", len(products),
				"duration_ms", time.Since(listStart).Milliseconds(),
			)
		}(listing)
	}

	w.logger.Log("cache_warming", "listings_completed", "duration_ms", time.Since(start).Milliseconds())
}

func (w *CacheWarmer) warmIndividualProducts(ctx context.Context) {
	start := time.Now()
	
	// Get first page of products to warm individual product cache
	products, err := w.service.List([]string{}, "", 1, 10) // Get first 10 products
	if err != nil {
		w.logger.Log("cache_warming", "products_list_error", "error", err)
		return
	}

	warmed := 0
	for _, product := range products {
		// Get full product details to ensure proper caching
		fullProduct, err := w.service.Get(product.ID)
		if err != nil {
			w.logger.Log("cache_warming", "product_error", "error", err, "id", product.ID)
			continue
		}

		if err := w.cache.SetProduct(ctx, product.ID, fullProduct); err != nil {
			w.logger.Log("cache_warming", "product_cache_error", "error", err, "id", product.ID)
			continue
		}

		warmed++
	}

	w.logger.Log("cache_warming", "products_completed", "warmed", warmed, "total", len(products), "duration_ms", time.Since(start).Milliseconds())
}

// WarmCacheAsync starts cache warming in the background
func (w *CacheWarmer) WarmCacheAsync() {
	go w.WarmCache()
}

// SchedulePeriodicWarming sets up periodic cache warming (useful for long-running services)
func (w *CacheWarmer) SchedulePeriodicWarming(interval time.Duration) {
	ticker := time.NewTicker(interval)
	go func() {
		for range ticker.C {
			w.WarmCache()
		}
	}()
	
	w.logger.Log("cache_warming", "scheduled", "interval_minutes", interval.Minutes())
}
