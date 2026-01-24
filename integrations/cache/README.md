# Redis Cache Integration

High-performance caching layer for Vorzimmerdrache, optimizing API calls and database queries on the critical path.

## Features

- **Redis-backed caching** with configurable TTL
- **Auto-retry** on connection failures
- **Pattern-based cache invalidation**
- **Multi-get/set operations** for batch queries
- **Statistics tracking** (hits, misses, sets, deletes)
- **Connection pooling** via PgBouncer

## Installation

```bash
npm install ioredis
```

## Quick Start

### Basic Usage

```javascript
const RedisCache = require('./redis-cache');

const cache = new RedisCache({
  host: 'redis',
  port: 6379,
  password: process.env.REDIS_PASSWORD,
  prefix: 'vzd:',
  defaultTTL: 300 // 5 minutes
});

// Set with default TTL
await cache.set('user:123', { name: 'John', email: 'john@example.com' });

// Get
const user = await cache.get('user:123');

// Get or Set (fetch function if not cached)
const data = await cache.getOrSet('expensive-query', async () => {
  return await someSlowOperation();
}, 3600); // 1 hour TTL
```

## Cache Modules

### CachedGeocodeService

Caches Google Maps geocoding results (1-hour TTL).

```javascript
const CachedGeocodeService = require('./cached-geocode');

const geo = new CachedGeocodeService({ apiKey: process.env.GOOGLE_MAPS_API_KEY });

const result = await geo.geocode('Musterstraße 123, 10115 Berlin');

// First call: 800ms (API)
// Second call: 15ms (cache)
```

### CachedCRMLookup

Caches PostgreSQL CRM queries (5-minute TTL).

```javascript
const CachedCRMLookup = require('./cached-crm');

const crm = new CachedCRMLookup();
await crm.connect();

const customer = await crm.findByPhone('+4917123456789');

// First call: 50ms (DB)
// Second call: 5ms (cache)
```

### CachedPhoneNormalization

Caches phone number normalization (24-hour TTL).

```javascript
const CachedPhoneNormalization = require('./cached-phone');

const phone = new CachedPhoneNormalization();

const result = await phone.validate('0171 123456789');
// Returns: { valid: true, normalized: '+4917123456789' }
```

## TTL Recommendations

| Data Type | TTL | Reason |
|-----------|-----|--------|
| Google Maps geocoding | 1 hour | Addresses rarely change |
| CRM lookups | 5 min | Fresh customer data |
| Phone normalization | 24 hours | Numbers don't change |
| Lead lists | 1 min | Real-time updates |
| Lead scores | 10 min | Periodic recalculations |

## Pattern-Based Invalidation

```javascript
// Invalidate all phone caches
await cache.deletePattern('phone:*');

// Invalidate all geocode caches
await cache.deletePattern('geo:*');
```

## Monitoring

### Get Cache Statistics

```javascript
const stats = cache.getStats();
console.log(stats);
// { hits: 1234, misses: 56, sets: 789, deletes: 12 }

const hitRate = stats.hits / (stats.hits + stats.misses);
console.log(`Hit rate: ${(hitRate * 100).toFixed(2)}%`);
```

### Get Redis Info

```javascript
const info = await cache.getInfo();
console.log(info.memory);
console.log(info.keyspace);
```

## Connection Configuration

```javascript
const cache = new RedisCache({
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT,
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: 3,
  retryStrategy: (times) => Math.min(times * 50, 2000),
  enableOfflineQueue: false,
  db: 0
});
```

## Best Practices

1. **Use getOrSet for lazy loading**
   ```javascript
   const data = await cache.getOrSet(key, fetchFn, ttl);
   ```

2. **Prefix keys by service**
   ```javascript
   new RedisCache({ prefix: 'crm:' });
   new RedisCache({ prefix: 'geo:' });
   ```

3. **Set appropriate TTLs**
   - Static data: Long TTL (hours/days)
   - Dynamic data: Short TTL (minutes)
   - Never cache: User-specific sensitive data

4. **Handle cache failures gracefully**
   ```javascript
   try {
     const cached = await cache.get(key);
     if (cached) return cached;
   } catch (error) {
     console.warn('Cache error:', error);
   }
   // Fallback to direct query
   return await directQuery();
   ```

5. **Monitor hit rates**
   - Aim for >80% hit rate
   - Investigate low hit rates
   - Adjust TTLs based on patterns

## Integration with n8n

### Add to n8n container

Update docker-compose.yml:

```yaml
n8n:
  volumes:
    - ./node_modules:/home/node/.n8n/node_modules:ro
```

### Use in Function Node

```javascript
const CachedCRMLookup = require('/home/node/.n8n/node_modules/integrations/cache/cached-crm');

const crm = new CachedCRMLookup();
await crm.connect();

const phone = $input.first().json.normalizedPhone;
const customer = await crm.findByPhone(phone);

return { json: { customer } };
```

## Testing

```bash
# Test Redis connection
docker exec redis redis-cli -a $REDIS_PASSWORD ping

# Check cache stats
docker exec redis redis-cli -a $REDIS_PASSWORD INFO stats

# Monitor in real-time
docker exec redis redis-cli -a $REDIS_PASSWORD MONITOR
```

## Troubleshooting

### Connection Refused

```bash
# Check Redis is running
docker ps | grep redis

# Check logs
docker logs redis
```

### Memory Issues

```bash
# Check memory usage
docker exec redis redis-cli -a $REDIS_PASSWORD INFO memory

# Adjust maxmemory in docker-compose.yml
# redis:
#   command: redis-server --maxmemory 512mb --maxmemory-policy allkeys-lru
```

### High Miss Rate

- Check if keys are being set
- Verify TTL isn't too short
- Check key prefixes match

## License

MIT
