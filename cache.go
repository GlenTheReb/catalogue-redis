package catalogue

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/go-kit/kit/log"
	"github.com/go-redis/redis/v8"
)

// CatalogueCache defines the interface for Redis caching operations
type CatalogueCache interface {
	// Product caching
	GetProducts(ctx context.Context, tags []string, order string, pageNum, pageSize int) ([]Sock, bool, error)
	SetProducts(ctx context.Context, tags []string, order string, pageNum, pageSize int, products []Sock) error
	
	// Individual product caching
	GetProduct(ctx context.Context, id string) (Sock, bool, error)
	SetProduct(ctx context.Context, id string, product Sock) error
	
	// Count caching
	GetCount(ctx context.Context, tags []string) (int, bool, error)
	SetCount(ctx context.Context, tags []string, count int) error
	
	// Tags caching
	GetTags(ctx context.Context) ([]string, bool, error)
	SetTags(ctx context.Context, tags []string) error
	
	// Cache invalidation
	InvalidateProduct(ctx context.Context, id string) error
	InvalidateAll(ctx context.Context) error
	
	// Health check
	Ping(ctx context.Context) error
}

type catalogueCache struct {
	client *redis.Client
	logger log.Logger
	ttl    time.Duration
}

// NewCatalogueCache creates a new Redis cache instance
func NewCatalogueCache(redisAddr string, logger log.Logger) CatalogueCache {
	rdb := redis.NewClient(&redis.Options{
		Addr:         redisAddr,
		Password:     "", // no password
		DB:           0,  // default DB
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
		PoolSize:     10,
		PoolTimeout:  5 * time.Second,
	})

	return &catalogueCache{
		client: rdb,
		logger: logger,
		ttl:    30 * time.Minute, // 30 minutes cache TTL
	}
}

// Cache key generators
func (c *catalogueCache) productListKey(tags []string, order string, pageNum, pageSize int) string {
	tagsStr := strings.Join(tags, ",")
	if tagsStr == "" {
		tagsStr = "all"
	}
	return fmt.Sprintf("catalogue:products:%s:order:%s:page:%d:size:%d", tagsStr, order, pageNum, pageSize)
}

func (c *catalogueCache) productKey(id string) string {
	return fmt.Sprintf("catalogue:product:%s", id)
}

func (c *catalogueCache) countKey(tags []string) string {
	tagsStr := strings.Join(tags, ",")
	if tagsStr == "" {
		tagsStr = "all"
	}
	return fmt.Sprintf("catalogue:count:%s", tagsStr)
}

func (c *catalogueCache) tagsKey() string {
	return "catalogue:tags:all"
}

// Product list operations
func (c *catalogueCache) GetProducts(ctx context.Context, tags []string, order string, pageNum, pageSize int) ([]Sock, bool, error) {
	key := c.productListKey(tags, order, pageNum, pageSize)
	
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		c.logger.Log("cache", "miss", "key", key, "operation", "GetProducts")
		return nil, false, nil
	}
	if err != nil {
		c.logger.Log("cache", "error", "operation", "GetProducts", "key", key, "error", err)
		return nil, false, err
	}

	var products []Sock
	if err := json.Unmarshal([]byte(val), &products); err != nil {
		c.logger.Log("cache", "unmarshal_error", "operation", "GetProducts", "key", key, "error", err)
		// Delete corrupted cache entry
		c.client.Del(ctx, key)
		return nil, false, nil
	}

	c.logger.Log("cache", "hit", "key", key, "operation", "GetProducts", "count", len(products))
	return products, true, nil
}

func (c *catalogueCache) SetProducts(ctx context.Context, tags []string, order string, pageNum, pageSize int, products []Sock) error {
	key := c.productListKey(tags, order, pageNum, pageSize)
	
	data, err := json.Marshal(products)
	if err != nil {
		c.logger.Log("cache", "marshal_error", "operation", "SetProducts", "key", key, "error", err)
		return err
	}

	err = c.client.Set(ctx, key, data, c.ttl).Err()
	if err != nil {
		c.logger.Log("cache", "error", "operation", "SetProducts", "key", key, "error", err)
		return err
	}

	c.logger.Log("cache", "set", "key", key, "operation", "SetProducts", "count", len(products), "ttl", c.ttl)
	return nil
}

// Individual product operations
func (c *catalogueCache) GetProduct(ctx context.Context, id string) (Sock, bool, error) {
	key := c.productKey(id)
	
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		c.logger.Log("cache", "miss", "key", key, "operation", "GetProduct")
		return Sock{}, false, nil
	}
	if err != nil {
		c.logger.Log("cache", "error", "operation", "GetProduct", "key", key, "error", err)
		return Sock{}, false, err
	}

	var product Sock
	if err := json.Unmarshal([]byte(val), &product); err != nil {
		c.logger.Log("cache", "unmarshal_error", "operation", "GetProduct", "key", key, "error", err)
		// Delete corrupted cache entry
		c.client.Del(ctx, key)
		return Sock{}, false, nil
	}

	c.logger.Log("cache", "hit", "key", key, "operation", "GetProduct", "product_id", id)
	return product, true, nil
}

func (c *catalogueCache) SetProduct(ctx context.Context, id string, product Sock) error {
	key := c.productKey(id)
	
	data, err := json.Marshal(product)
	if err != nil {
		c.logger.Log("cache", "marshal_error", "operation", "SetProduct", "key", key, "error", err)
		return err
	}

	err = c.client.Set(ctx, key, data, c.ttl).Err()
	if err != nil {
		c.logger.Log("cache", "error", "operation", "SetProduct", "key", key, "error", err)
		return err
	}

	c.logger.Log("cache", "set", "key", key, "operation", "SetProduct", "product_id", id, "ttl", c.ttl)
	return nil
}

// Count operations
func (c *catalogueCache) GetCount(ctx context.Context, tags []string) (int, bool, error) {
	key := c.countKey(tags)
	
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		c.logger.Log("cache", "miss", "key", key, "operation", "GetCount")
		return 0, false, nil
	}
	if err != nil {
		c.logger.Log("cache", "error", "operation", "GetCount", "key", key, "error", err)
		return 0, false, err
	}

	count, err := strconv.Atoi(val)
	if err != nil {
		c.logger.Log("cache", "parse_error", "operation", "GetCount", "key", key, "error", err)
		// Delete corrupted cache entry
		c.client.Del(ctx, key)
		return 0, false, nil
	}

	c.logger.Log("cache", "hit", "key", key, "operation", "GetCount", "count", count)
	return count, true, nil
}

func (c *catalogueCache) SetCount(ctx context.Context, tags []string, count int) error {
	key := c.countKey(tags)
	
	err := c.client.Set(ctx, key, count, c.ttl).Err()
	if err != nil {
		c.logger.Log("cache", "error", "operation", "SetCount", "key", key, "error", err)
		return err
	}

	c.logger.Log("cache", "set", "key", key, "operation", "SetCount", "count", count, "ttl", c.ttl)
	return nil
}

// Tags operations
func (c *catalogueCache) GetTags(ctx context.Context) ([]string, bool, error) {
	key := c.tagsKey()
	
	val, err := c.client.Get(ctx, key).Result()
	if err == redis.Nil {
		c.logger.Log("cache", "miss", "key", key, "operation", "GetTags")
		return nil, false, nil
	}
	if err != nil {
		c.logger.Log("cache", "error", "operation", "GetTags", "key", key, "error", err)
		return nil, false, err
	}

	var tags []string
	if err := json.Unmarshal([]byte(val), &tags); err != nil {
		c.logger.Log("cache", "unmarshal_error", "operation", "GetTags", "key", key, "error", err)
		// Delete corrupted cache entry
		c.client.Del(ctx, key)
		return nil, false, nil
	}

	c.logger.Log("cache", "hit", "key", key, "operation", "GetTags", "count", len(tags))
	return tags, true, nil
}

func (c *catalogueCache) SetTags(ctx context.Context, tags []string) error {
	key := c.tagsKey()
	
	data, err := json.Marshal(tags)
	if err != nil {
		c.logger.Log("cache", "marshal_error", "operation", "SetTags", "key", key, "error", err)
		return err
	}

	err = c.client.Set(ctx, key, data, c.ttl).Err()
	if err != nil {
		c.logger.Log("cache", "error", "operation", "SetTags", "key", key, "error", err)
		return err
	}

	c.logger.Log("cache", "set", "key", key, "operation", "SetTags", "count", len(tags), "ttl", c.ttl)
	return nil
}

// Cache invalidation
func (c *catalogueCache) InvalidateProduct(ctx context.Context, id string) error {
	key := c.productKey(id)
	
	err := c.client.Del(ctx, key).Err()
	if err != nil {
		c.logger.Log("cache", "error", "operation", "InvalidateProduct", "key", key, "error", err)
		return err
	}

	c.logger.Log("cache", "invalidate", "key", key, "operation", "InvalidateProduct", "product_id", id)
	return nil
}

func (c *catalogueCache) InvalidateAll(ctx context.Context) error {
	pattern := "catalogue:*"
	
	iter := c.client.Scan(ctx, 0, pattern, 0).Iterator()
	keys := []string{}
	
	for iter.Next(ctx) {
		keys = append(keys, iter.Val())
	}
	
	if err := iter.Err(); err != nil {
		c.logger.Log("cache", "error", "operation", "InvalidateAll", "error", err)
		return err
	}

	if len(keys) > 0 {
		err := c.client.Del(ctx, keys...).Err()
		if err != nil {
			c.logger.Log("cache", "error", "operation", "InvalidateAll", "error", err)
			return err
		}
		c.logger.Log("cache", "invalidate_all", "operation", "InvalidateAll", "keys_deleted", len(keys))
	} else {
		c.logger.Log("cache", "invalidate_all", "operation", "InvalidateAll", "keys_deleted", 0)
	}

	return nil
}

// Health check
func (c *catalogueCache) Ping(ctx context.Context) error {
	err := c.client.Ping(ctx).Err()
	if err != nil {
		c.logger.Log("cache", "ping_error", "error", err)
		return err
	}
	return nil
}
