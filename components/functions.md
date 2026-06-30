# Component Audit: Catalyst Functions

## Component Overview
Catalyst Functions are the primary compute layer. Five types exist with different auth models and execution contexts. Type confusion is the most critical Catalyst-specific vulnerability.

| Type | Public? | Auth | Use Case |
|---|---|---|---|
| Advanced I/O | **Yes — no auth enforced** | None by default | Public APIs, webhooks |
| Basic I/O | No — Catalyst session required | Catalyst user session | User-specific operations |
| Cron | No — scheduler only | None | Scheduled background tasks |
| Event | No — internal events | Internal event system | React to Catalyst events |
| Event Listener | No — internal | Internal | Listen to data change events |

---

## Security Checklist

### FN-SEC-01 — Function Type vs. Sensitivity Mismatch ★ CRITICAL

For every Advanced I/O function in the project:

1. Does it access user-specific data? (Data Store rows, File Store files, Cache entries)
2. Does it perform write/delete/update operations?
3. Does it use `catalyst.auth().getCurrentUser()` at the very start?

If (1 or 2) AND NOT (3) → CRITICAL finding.

```bash
# List all Advanced I/O functions
grep -rn "advancedio\|Advanced I/O" catalyst-config.json

# Check each for auth context
grep -rn "getCurrentUser\|auth()" functions/{advancedio_function_name}/ --include="*.js"
```

**Exploit:** Attacker calls public function URL directly, bypasses all auth, accesses or modifies other users' data.

**Fix:**
```js
exports.main = async (context, basicIO) => {
  const catalyst = require('zcatalyst-sdk-node')(context);
  const user = await catalyst.auth().getCurrentUser(); // SECURITY: auth check
  if (!user) {
    basicIO.status = 401;
    basicIO.response.json({ error: 'Unauthorized' });
    return;
  }
  // Now safe to use user.user_id for ownership checks
}
```

---

### FN-SEC-02 — Auth Context Spoofing

For Basic I/O functions: does any code path accept user identity from the request body or query params instead of from `catalyst.auth().getCurrentUser()`?

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
**Good:** `require(...)` at module top, called with `(context)` inside handler

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
