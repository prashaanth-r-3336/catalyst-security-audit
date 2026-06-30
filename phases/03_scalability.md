# Phase 3: Catalyst Scalability Audit

## Purpose
Identify Catalyst-specific patterns that will cause performance degradation, timeout failures, excessive cost, or inability to scale under load. These are not security issues but they are production correctness issues.

---

## Instructions

You are the Scalability Audit agent. You have the Project Profile from Phase 1. Audit the source files for the patterns below. Report every finding with code evidence and the expected impact under load.

---

### SCALE-01 — SDK Initialization Inside Handler (Cold Start Bloat)

**Impact:** HIGH — Every function invocation pays initialization cost; worse under high concurrency  
**Catalyst context:** Each function invocation may be a cold start. SDK initialization (`require('zcatalyst-sdk-node')`, connection setup) inside the handler runs on every invocation.

**Bad pattern:**
```js
exports.main = async (context, basicIO) => {
  const catalyst = require('zcatalyst-sdk-node')(context); // ← runs every invocation
  const datastore = catalyst.datastore();
  // ...
}
```

**Good pattern:**
```js
const catalystSDK = require('zcatalyst-sdk-node'); // ← module-level, cached after first load
exports.main = async (context, basicIO) => {
  const catalyst = catalystSDK(context);
  // ...
}
```

**Grep:**
```bash
# require() inside handler body
grep -rn "require(" functions/ --include="*.js" -A 0 | grep -v "^functions/[^/]*/index.js:1:"
# Python: imports inside function body
grep -rn "^    import \|^        import " functions/ --include="*.py"
```

**Finding format:**
```
[SCALE-01] LOW: SDK/module require() inside handler function — runs on every invocation
File: functions/{name}/index.js:{line}
Impact: Added ~50-200ms cold start per invocation; worse under burst load
Fix: Move require() to module top-level
```

---

### SCALE-02 — N+1 ZCQL Queries

**Impact:** HIGH — Linear increase in DB calls as data grows; function timeout risk  
**Catalyst context:** Each ZCQL call is a network round-trip to Catalyst Data Store. N+1 inside a loop is the most common Catalyst performance issue.

**Bad pattern:**
```js
// Processing 100 orders — makes 100 separate ZCQL calls
for (const orderId of orderIds) {
  const order = await datastore.table('Orders').getRow(orderId); // ← N+1
  process(order);
}
```

**Good pattern:**
```js
// One ZCQL call for all orders
const orders = await datastore.table('Orders')
  .ZCQL(`SELECT * FROM Orders WHERE ROWID IN (${orderIds.join(',')})`);
```

**Grep:**
```bash
# Async calls inside loops
grep -rn "await.*datastore\|await.*getRow\|await.*ZCQL" functions/ --include="*.js" -B 5 | grep -E "for |forEach|map\(|while "
grep -rn "for.*await\|forEach.*await\|\.map.*async" functions/ --include="*.js" | grep -i "datastore\|getrow\|zcql\|cache\|nosql"
```

**Finding format:**
```
[SCALE-02] LOW: N+1 ZCQL pattern — {N} Data Store calls inside a loop
File: functions/{name}/index.js:{line}
Impact: {N} items = {N} network round-trips; at 100 items, likely to hit function timeout
Fix: Replace loop with single bulk ZCQL query using IN clause or getRows() with criteria
```

---

### SCALE-03 — Heavy Operations in Synchronous Functions

**Impact:** HIGH — Function timeout; user-facing latency; retry storms  
**Catalyst context:** Advanced I/O and Basic I/O functions have execution time limits (~45s). Long-running work (file processing, bulk DB operations, ML inference, sending bulk emails) must use Job Scheduling.

**Signs of violating sync/async boundary:**
- Loops over large datasets inside a function
- File parsing/transformation inline
- Sending bulk emails or notifications
- ML model inference on large inputs
- Calling multiple external APIs sequentially

**Check:**
```bash
# Large loops with awaited operations
grep -rn "for.*let\|for.*var\|for.*const\|while(" functions/ --include="*.js" | head -30
# Multiple sequential await calls (waterfall)
grep -rn "await " functions/ --include="*.js" | awk '{count[$1]++} END {for (f in count) print count[f], f}' | sort -rn | head -20
# Sleep/delay (suggests long-running operation)
grep -rn "setTimeout\|sleep\|delay" functions/ --include="*.js"
```

**Assess:** Any function that processes more than ~50 records, sends more than ~10 external requests, or does file transformation should be moved to Job Scheduling.

**Finding format:**
```
[SCALE-03] MEDIUM: Heavy synchronous operation in {function_type} function '{name}'
File: functions/{name}/index.js
Operation: {describe what it does}
Impact: Will timeout under real data volume; blocks the calling client
Fix: Move heavy work to a Catalyst Immediate Job or Cron Job; return 202 Accepted with job ID to client
```

---

### SCALE-04 — Hot Data Not Using Catalyst Cache

**Impact:** MEDIUM — Unnecessary ZCQL round-trips for frequently read, rarely changed data  
**Catalyst context:** Catalyst Cache is an in-memory key-value store. Data Store access has per-query cost and latency. Config data, user profiles, and lookup tables read on every request should be cached.

**Signs of missing cache:**
- Same table queried on every request (config tables, user preferences, product catalog)
- User identity lookup on every authenticated request
- Static/semi-static data (feature flags, rate limits, allowed values) read from Data Store

**Check:**
```bash
# How many times each table is queried — high-count tables are cache candidates
grep -rn "table('[A-Za-z_]*')" functions/ --include="*.js" | sed "s/.*table('\([^']*\)').*/\1/" | sort | uniq -c | sort -rn

# Functions that use DataStore but NOT Cache
for dir in functions/*/; do
  name=$(basename $dir)
  has_ds=$(grep -l "datastore()" $dir/*.js 2>/dev/null | wc -l)
  has_cache=$(grep -l "catalyst.cache()" $dir/*.js 2>/dev/null | wc -l)
  if [ "$has_ds" -gt 0 ] && [ "$has_cache" -eq 0 ]; then
    echo "$name: uses DataStore, no Cache"
  fi
done
```

**Finding format:**
```
[SCALE-04] INFO: Table '{table_name}' queried on every request in '{function_name}' — Cache candidate
File: functions/{name}/index.js
Access pattern: Read-only, same query every request
Fix: Cache result with catalyst.cache().put('config_key', data, {ttl: 300}); serve from cache on subsequent requests
```

---

### SCALE-05 — Bulk Operations Not Using Job Pools

**Impact:** MEDIUM — Serial execution of bulk work; no parallelism; timeout risk  
**Catalyst context:** Catalyst Job Scheduling supports Job Pools for parallel execution of multiple jobs. Bulk work (processing 1000 records, sending 500 emails) run as individual sequential Jobs will timeout or take disproportionately long.

**Check:**
```bash
# Creating multiple immediate jobs without a pool
grep -rn "createImmediateJob\|immediate_job" functions/ --include="*.js" -B 5 -A 5 | grep -v "pool\|Pool"
# Loop creating jobs
grep -rn "createImmediateJob" functions/ --include="*.js" -B 10 | grep "for\|while\|forEach\|map"
```

**Finding format:**
```
[SCALE-05] LOW: Bulk jobs created without Job Pool — serial execution
File: functions/{name}/index.js:{line}
Operation: Creating {N} immediate jobs in a loop without pool grouping
Fix: Create a Job Pool first, then submit all jobs to the pool for parallel execution
```

---

### SCALE-06 — Missing Retry Logic for External Calls

**Impact:** MEDIUM — Transient failures cause complete feature failure  
**Catalyst context:** Catalyst Connections and external API calls can fail transiently. Functions without retry logic fail permanently on the first transient error.

**Check:**
```bash
# External calls without retry
grep -rn "fetch\|axios\|request(" functions/ --include="*.js" | grep -v "retry\|Retry\|attempt"
# Connection API calls without error retry
grep -rn "catalyst.connection()\|connection.invoke\|connection.send" functions/ --include="*.js" -A 5 | grep -v "catch\|retry"
```

**Finding format:**
```
[SCALE-06] INFO: External API call without retry logic
File: functions/{name}/index.js:{line}
Call: {describe the call}
Fix: Wrap in exponential backoff retry (max 3 attempts); use a library like p-retry; log all retry attempts
```

---

### SCALE-07 — Unbounded Query Results

**Impact:** HIGH — Memory exhaustion; function timeout on large tables  
**Catalyst context:** ZCQL queries without LIMIT clauses return all matching rows. As table grows, function memory and execution time grow with it.

**Grep:**
```bash
# ZCQL queries without LIMIT
grep -rn "ZCQL\|\.query(" functions/ --include="*.js" | grep -iv "limit\|LIMIT" | grep "SELECT"
# getRows() without maxRows
grep -rn "getRows\(\)" functions/ --include="*.js"
```

**Finding format:**
```
[SCALE-07] MEDIUM: Unbounded ZCQL query — no LIMIT clause on table '{table_name}'
File: functions/{name}/index.js:{line}
Impact: At 10,000 rows, likely function OOM; at 100,000 rows, certain timeout
Fix: Add LIMIT clause; implement cursor-based pagination for large result sets
```

---

### SCALE-08 — AppSail vs Functions — Wrong Compute Choice

**Impact:** MEDIUM — Cost inefficiency and resource constraints  
**Catalyst context:** AppSail is for long-running, stateful, or high-memory workloads. Functions are for short-lived, stateless operations. Using Functions for AppSail workloads (WebSocket servers, persistent connections, streaming) will fail or be cost-inefficient.

**Check:** For each Advanced I/O function:
- Does it maintain state between requests? (global mutable variables)
- Does it open WebSocket connections?
- Does it stream responses?
- Does it spawn child processes?

```bash
# State in global scope (wrong for Functions)
grep -rn "^let \|^var \|^const " functions/ --include="*.js" | grep -v "require\|import\|module"
# WebSocket usage
grep -rn "WebSocket\|ws://" functions/ --include="*.js"
# Child processes
grep -rn "child_process\|spawn\|exec(" functions/ --include="*.js"
```

**Finding format:**
```
[SCALE-08] MEDIUM: Stateful/long-running operation in Functions — should use AppSail
File: functions/{name}/index.js
Pattern: {describe: WebSocket / global state / child process / persistent connection}
Fix: Migrate this workload to an AppSail container; Functions are stateless and short-lived
```
