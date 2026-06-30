# Component Audit: Catalyst Cron / Job Scheduling

## Component Overview
Catalyst Cron handles three job types: Cron Jobs (schedule-based), Immediate Jobs (on-demand async), and Job Pools (parallelized bulk work). Cron functions run without a user session context — they operate with the project's identity. This makes authorization and idempotency critical.

---

## Security Checklist

### CRON-SEC-01 — Cron Function Invocable via HTTP ★ HIGH

Cron functions should only be triggered by the Catalyst scheduler. If the function URL is exposed or the function is also registered as an Advanced I/O function, external actors can trigger it manually.

```bash
# Check if cron function is also listed as advancedio in config
grep -A 20 "\"functions\"" catalyst-config.json | grep -i "cron\|schedule" -A 5
# Check if cron function has any HTTP routing
grep -rn "app\.get\|app\.post\|router\." functions/*/index.js | \
  grep -li "cron" $(find functions -name "index.js")
```

**Flag:** If a Cron function handles HTTP requests (has `req/res` handling beyond Catalyst's internal call format) → HIGH.

---

### CRON-SEC-02 — Elevated Operations Without Idempotency ★ HIGH

Cron jobs often perform bulk operations: sending emails, processing payments, data migrations. Manual re-trigger or scheduler duplicate fires on a non-idempotent job causes duplicates.

```bash
# Cron functions that modify data
grep -rn "insertRow\|updateRow\|deleteRow\|createRecord\|sendEmail\|chargeCard" \
  functions/ --include="*.js" | \
  grep -li "cron" $(find functions -name "index.js") 2>/dev/null
```

**Check per cron function that modifies data:**
1. Is there a status flag in Data Store that marks the item as "processed"?
2. Does the job check this flag before processing?
3. Is the flag updated atomically with the processing operation?

**Pattern for idempotency:**
```js
// Check and mark atomically before processing
const item = await datastore.table('InvoicesToProcess').getRow(id);
if (item.status === 'processed') return; // Skip already-processed items

// Process...
await sendInvoiceEmail(item);

// Mark as done
await datastore.table('InvoicesToProcess').updateRow({ ROWID: id, status: 'processed' });
```

---

### CRON-SEC-03 — Hardcoded User IDs or Admin Credentials ★ HIGH

Cron functions run as the project, not as a user. Some developers hardcode admin user IDs or tokens to perform operations that require a user identity.

```bash
grep -rn "admin\|Admin\|superUser\|hardcoded" functions/ --include="*.js" | \
  grep -i "userId\|user_id\|email\|token"

# Hardcoded user IDs (long numeric strings in cron context)
grep -rn "userId\s*=\s*['\"][0-9]\{8,\}['\"]" functions/ --include="*.js"
```

**Finding:** Hardcoded user IDs or tokens in cron functions → HIGH (privilege escalation risk if the hardcoded account has elevated permissions).

---

### CRON-SEC-04 — Cron Accessing User Data Without Scoping ★ MEDIUM

Cron jobs that access all rows in a user-data table (without filtering by tenant/user) and operate on all of them could be used as a privilege escalation vector if another Catalyst function allows triggering the cron.

```bash
# Cron functions doing SELECT * without user/tenant filter
grep -rn "ZCQL\|getRows" functions/ --include="*.js" | \
  grep -i "cron\|schedule" | grep "SELECT \*\|getRows()\|getRows({'}"
```

---

## Scalability Checklist

### CRON-SCALE-01 — Processing Large Datasets in a Single Cron Function ★ HIGH

```bash
# Cron functions with loops over potentially large result sets
grep -rn "for\|while\|forEach\|\.map" functions/ --include="*.js" -B 5 -A 5 | \
  grep "await\|async" | grep -li "cron" $(find functions -name "index.js") 2>/dev/null
```

A cron function that fetches 10,000 records and processes them serially will timeout. Instead:
1. Fetch records in pages
2. Dispatch each page as an Immediate Job
3. Use a Job Pool for parallel execution

**Pattern:**
```js
// Cron function — just dispatches jobs
exports.main = async (context) => {
  const items = await datastore.table('ToProcess').ZCQL('SELECT ROWID FROM ToProcess WHERE status = "pending" LIMIT 1000');
  
  const pool = await catalyst.jobschedule().getJobPool('ProcessingPool');
  for (const item of items) {
    await catalyst.jobschedule().createImmediateJob({
      pool_id: pool.id,
      params: { rowId: item.ROWID }
    });
  }
};
```

### CRON-SCALE-02 — Cron Overlap — No Lock Mechanism

```bash
# Cron functions without execution lock / mutex
grep -rn "exports\.main\s*=" functions/ --include="*.js" -A 30 | \
  grep -v "lock\|Lock\|mutex\|semaphore\|running\|in_progress" | \
  grep -li "cron" $(find functions -name "index.js") 2>/dev/null
```

If a cron job takes longer than its schedule interval, multiple instances will overlap. Use a Data Store row as a distributed lock.

**Pattern:**
```js
// Distributed lock using Data Store
const lock = await datastore.table('CronLocks').ZCQL(
  `SELECT * FROM CronLocks WHERE job_name = 'ProcessInvoices' AND status = 'running'`
);
if (lock.length > 0) {
  console.log('Previous run still active — skipping');
  return;
}
await datastore.table('CronLocks').insertRow({ job_name: 'ProcessInvoices', status: 'running' });
// ... do work ...
await datastore.table('CronLocks').updateRow({ job_name: 'ProcessInvoices', status: 'idle' });
```

### CRON-SCALE-03 — Immediate Jobs Not Using Job Pools for Bulk Work

```bash
# createImmediateJob inside a loop without pool
grep -rn "createImmediateJob\|immediate_job" functions/ --include="*.js" -B 5 | \
  grep "for\|while\|forEach\|\.map"
```

**Fix:** Create a Job Pool, then submit all immediate jobs to the pool. The pool manages concurrency and prevents overwhelming downstream systems.

### CRON-SCALE-04 — No Dead Letter / Failure Tracking

```bash
# Cron/job functions without error logging to Data Store
grep -rn "catch" functions/ --include="*.js" -A 5 | \
  grep -li "cron\|job" $(find functions -name "index.js") 2>/dev/null | \
  xargs grep -l "datastore\|log" 2>/dev/null
```

Failed jobs with no record written to a failure table are invisible. Build a dead-letter mechanism: on job failure, write the failed item + error to a `JobFailures` table for retry or manual inspection.
