# Component Audit: Catalyst Cache

## Component Overview
Catalyst Cache is an in-memory key-value store for hot data. Misuse leads to cache poisoning, sensitive data exposure, cache key enumeration, and incorrect authorization decisions.

---

## Security Checklist

### CACHE-SEC-01 — Sensitive Data Stored in Cache ★ HIGH

Cache is shared across function instances. Sensitive data (passwords, tokens, raw PII, session data) in cache is exposed to any function that knows the key.

```bash
# Cache put operations storing sensitive-sounding data
grep -rn "cache.*put\|\.put(" functions/ --include="*.js" -A 2 | \
  grep -i "password\|token\|secret\|session\|credit\|ssn\|auth"
```

**Finding:** If auth tokens, full user credentials, or raw PII are stored in Cache → HIGH.

**Fix:** Store minimal, non-sensitive data in Cache. If caching user data, store only non-sensitive identifiers and public profile fields.

---

### CACHE-SEC-02 — Predictable/Enumerable Cache Keys ★ MEDIUM

Cache keys derived from sequential IDs or user-supplied values allow attackers to enumerate other users' cached data.

```bash
# Cache keys using user input
grep -rn "cache.*put\|cache.*get" functions/ --include="*.js" -B 2 -A 2 | \
  grep "req\.\|body\.\|param\.\|query\."

# Sequential or predictable key construction
grep -rn "\.put(\|\.get(" functions/ --include="*.js" -A 1 | \
  grep "'\|\"" | grep -E "user_[0-9]|_id\s*\+|rowId\s*\+"
```

**Vulnerable pattern:**
```js
// VULNERABLE — predictable key: user_123, user_124, ...
const cacheKey = 'user_' + userId;
await catalyst.cache().put(cacheKey, userData);
```

**Safe pattern:**
```js
// SAFE — HMAC-signed key makes enumeration infeasible
const crypto = require('crypto');
const cacheKey = crypto.createHmac('sha256', process.env.CACHE_KEY_SECRET)
  .update('user_' + userId).digest('hex');
```

---

### CACHE-SEC-03 — Cache Poisoning via User-Controlled Key ★ HIGH

If user input directly becomes a cache key (or part of one) without validation, an attacker can overwrite cached data for other users.

```bash
# put() where key comes from user input
grep -rn "\.put(" functions/ --include="*.js" -B 5 | \
  grep "req\.\|body\.\|param\.\|query\."
```

**Exploit:** Attacker sends a request with a key value matching another user's cache entry, overwriting it with crafted data.

---

### CACHE-SEC-04 — Authorization Decisions Cached Incorrectly ★ HIGH

Caching the result of an authorization check (e.g., "is user X an admin?") without proper TTL or invalidation logic can lock users into cached roles.

```bash
grep -rn "cache.*admin\|cache.*role\|cache.*permission\|cache.*auth" functions/ --include="*.js" -i
```

**Rules for caching auth decisions:**
- Short TTL (30-60 seconds maximum for role/permission cache)
- Invalidate on permission change
- Never cache a `deny` decision — always re-check denials live

---

## Scalability Checklist

### CACHE-SCALE-01 — Missing Cache for Hot ZCQL Queries

```bash
# Functions that query the same tables repeatedly without caching
grep -rn "\.ZCQL\|getRow\|getRows" functions/ --include="*.js" | \
  awk -F: '{print $1}' | sort | uniq -c | sort -rn | head -10
```

For each high-frequency queried table, check if the result is cached.

**Recommendation:** Config tables, product catalogs, user preferences, and feature flags should be cached with appropriate TTL. Typical TTLs: config 5 min, user profile 60s, product catalog 5 min.

### CACHE-SCALE-02 — No TTL Set on Cache Entries

```bash
# cache put() without TTL
grep -rn "\.put(" functions/ --include="*.js" | grep -v "ttl\|TTL\|expires\|timeout"
```

Cache entries without TTL persist indefinitely (or until eviction). Stale data bugs are common.

**Fix:** Always set TTL appropriate to the data freshness requirement.

### CACHE-SCALE-03 — Cache Miss Stampede (Thundering Herd)

Pattern: Cache expires → multiple concurrent requests all miss → all hit Data Store simultaneously → DB overload.

```bash
# Cache get/put without stampede protection
grep -rn "cache.*get\|\.get(" functions/ --include="*.js" -A 10 | \
  grep -v "lock\|mutex\|singleflight\|dedupe"
```

**Fix for high-traffic keys:** Use a short-lived lock or single-flight pattern to allow only one concurrent request to repopulate a cache miss.

### CACHE-SCALE-04 — Caching Large Objects

```bash
# Cache put with potentially large values
grep -rn "\.put(" functions/ --include="*.js" -A 2 | \
  grep -v "limit\|slice\|truncate\|\.length"
```

Catalyst Cache has per-value size limits. Storing large objects (full query result sets, big JSON) will fail silently or cause eviction pressure.

**Fix:** Cache only the minimum data needed. Store record IDs, not full records, if the data is large.
