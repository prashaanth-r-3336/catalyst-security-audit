# Component Audit: Catalyst Functions

## Component Overview
Catalyst Functions are the primary compute layer. Seven types exist (`basicio`, `advancedio`, `event`, `job`, `cron`, `integration`, `browserlogic`) with different execution contexts — but **auth is not determined by type**. This is the most commonly misunderstood Catalyst-specific security fact.

| Type | Public? | Auth | Use Case |
|---|---|---|---|
| Advanced I/O | **Yes by default** | Gated only by Security Rules (`authentication: optional/required`) — `optional` is the default set at creation | Public APIs, webhooks |
| Basic I/O | **Yes by default** | Same Security Rules gate as Advanced I/O — NOT inherently session-protected | User-specific operations, but must set `authentication: required` explicitly |
| Job | No — Job Scheduling only | Internal | Scheduled/background work — preferred over Cron |
| Cron | No — legacy scheduler only | Internal | Deprecated in favor of Job; flag as INFO in new projects |
| Event | No — internal, triggered by Signals | Internal event system | React to Catalyst events (standalone Event Listeners is deprecated) |
| Integration | No — internal | Zoho service triggers | React to Zoho service events |
| Browser Logic | N/A | Invoked by SmartBrowz | See `components/smartbrowz.md` |

**Enabling API Gateway on a function disables Security Rules for it** — the two are mutually exclusive per function. Check which one is actually active before concluding a function is (un)protected.

---

## Security Checklist

### FN-SEC-01 — Security Rules Not Set to Required ★ CRITICAL

For every Basic I/O or Advanced I/O function in the project:

1. Does it access user-specific data? (Data Store rows, File Store files, Cache entries)
2. Does it perform write/delete/update operations?
3. Does its Security Rules config set `"authentication": "required"` (or is API Gateway configured with equivalent protection)?
4. If (3) is satisfied, does the handler still resolve identity via `catalyst.initialize(req).userManagement().getCurrentUser()` and verify resource ownership — Security Rules only gates "is there a session," not "does this user own this row"?

If (1 or 2) AND NOT (3) → CRITICAL finding. If (3) but NOT (4) on a resource-fetching path → treat as IDOR (see FN-SEC-02/SEC-06).

```bash
# List all functions and their declared type
grep -rn "\"type\"\s*:\s*\"\(basicio\|advancedio\)\"" functions/*/catalyst-config.json 2>/dev/null

# Check each function's Security Rules
grep -rn "\"authentication\"" functions/*/catalyst-config.json functions/*/security-rules.json 2>/dev/null

# Check for identity resolution in the handler
grep -rn "userManagement()\.getCurrentUser\|catalyst\.initialize" functions/{function_name}/ --include="*.js"
```

**Exploit:** Attacker calls the function URL directly. With `authentication: optional` (the default), no session is required at all — the handler runs regardless of who calls it.

**Fix:**
1. Set Security Rules `"authentication": "required"` for any function touching sensitive data.
2. Inside the handler, resolve identity explicitly and check ownership:

```js
// Advanced I/O (raw-http template)
const catalyst = require('zcatalyst-sdk-node');

module.exports = async (req, res) => {
  const userApp = catalyst.initialize(req); // user-scope
  const user = await userApp.userManagement().getCurrentUser();
  if (!user || !user.user_id) {
    // null is also returned for collaborators/admins — treat as unauthenticated here
    res.writeHead(401, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ error: 'Unauthorized' }));
  }
  // Now safe to use user.user_id for ownership checks against fetched rows
};
```

---

### FN-SEC-02 — Auth Context Spoofing

For Basic I/O or Advanced I/O functions: does any code path accept user identity from the request body or query params instead of from `catalyst.initialize(req).userManagement().getCurrentUser()`?

```bash
grep -rn "req\.body\.userId\|req\.body\.user_id\|req\.query\.userId\|req\.headers\['x-user-id'\]" \
  functions/ --include="*.js"
```

**Finding:** Any function that accepts `userId` from the request and uses it for data access without validating it against the auth context.

---

### FN-SEC-03 — Input Validation at Function Boundary

Every function is a trust boundary. Check that each function validates its inputs:

```bash
# Functions that use req.body directly without validation
grep -rn "req\.body\." functions/ --include="*.js" | grep -v "typeof\|validate\|schema\|parseInt\|Number(\|String(\|\.trim()"
```

Required validations:
- Type check all inputs
- Length/size limits on strings and arrays
- Allowlist for enum-type fields
- Numeric range checks for IDs

---

### FN-SEC-04 — Error Handling

```bash
# Catch blocks that send raw error messages
grep -rn "catch" functions/ --include="*.js" -A 3 | grep "\.send\|\.json\|response\." | grep "error\|err\|e\."
# Stack traces in responses
grep -rn "\.stack" functions/ --include="*.js" | grep -i "send\|json\|response"
```

**Fix:** All catch blocks must return a generic error message; log the full error server-side with a correlation ID.

---

### FN-SEC-05 — Hardcoded URLs / Endpoints

```bash
# Hardcoded Catalyst project URLs or internal endpoints
grep -rn "catalyst.com\|zylker.com\|zoho.com" functions/ --include="*.js" | grep -v "comment\|//\s"
# Hardcoded IPs
grep -rn "https\?://[0-9]\{1,3\}\.[0-9]\{1,3\}" functions/ --include="*.js"
```

---

## Scalability Checklist

### FN-SCALE-01 — Module-Level SDK Initialization

```bash
# SDK initialized inside handler (should be module-level)
grep -rn "require('zcatalyst-sdk-node')" functions/ --include="*.js" -B 2 | \
  grep "exports\.\|async function\|function main"
```

**Bad:** `require(...)` inside `exports.main`  
**Good:** `require('zcatalyst-sdk-node')` at module top; call `catalyst.initialize(req)` (Advanced I/O) inside the handler per-request — the require, not the initialize call, is what belongs at module scope

### FN-SCALE-02 — Response Returned Before Async Work Completes

```bash
# Response sent without awaiting async operations
grep -rn "basicIO\.send\|context\.res\.send" functions/ --include="*.js" -B 5 | \
  grep -v "await"
```

### FN-SCALE-03 — Synchronous Loops Over Data

```bash
# For loops containing awaited async calls
grep -rn "for " functions/ --include="*.js" -A 5 | grep "await"
```

Any loop with `await` inside is serializing concurrent-capable work. Use `Promise.all()` for independent parallel operations.

---

## Common Anti-Patterns

| Anti-Pattern | Finding | Fix |
|---|---|---|
| `console.log(JSON.stringify(req.body))` | Logs full request — may contain PII/secrets | Log only non-sensitive fields |
| `process.exit(1)` inside handler | Crashes function runtime | Throw or return error response |
| No `try/catch` in async function | Unhandled promise rejection crashes function | Wrap all async code in try/catch |
| Returning `200` on all errors | Hides failures from monitoring | Use correct HTTP status codes |
| Global mutable state | State bleeds between invocations | Keep handlers stateless |
