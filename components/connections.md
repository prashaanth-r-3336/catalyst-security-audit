# Component Audit: Catalyst Connections

## Component Overview
Catalyst Connections manages OAuth 2.0 integrations with third-party services (Google, Salesforce, Zoho CRM, Slack, etc.). Connections store client secrets and access tokens securely within Catalyst — they must NEVER be replicated into function source code or environment variables.

---

## Security Checklist

### CONN-SEC-01 — OAuth Credentials in Source Code ★ CRITICAL

The entire purpose of Catalyst Connections is to avoid storing OAuth credentials in function code. Any `client_secret`, `client_id` (combined with secret), `refresh_token`, or `access_token` in source code defeats this.

```bash
# OAuth credentials in source
grep -rn "client_secret\|clientSecret\|client_id.*secret\|refresh_token\|access_token" \
  functions/ --include="*.js" --include="*.py" | grep -v "//.*comment"

# Common OAuth provider credential patterns
grep -rn "GOOGLE_CLIENT\|SALESFORCE_TOKEN\|SLACK_SECRET\|ZOHO_SECRET\|TWITTER_SECRET\|GITHUB_TOKEN" \
  functions/ --include="*.js" --include="*.py"

# Bearer tokens hardcoded
grep -rn "Bearer [A-Za-z0-9._-]\{40,\}" functions/ --include="*.js"

# Zoho access tokens
grep -rn "1000\.[a-z0-9]\{32,\}\.[a-z0-9]\{32,\}" functions/ --include="*.js"
```

**Finding format:**
```
[CONN-SEC-01] CRITICAL: OAuth credential hardcoded in function source
File: {file}:{line}
Type: {client_secret / access_token / refresh_token}
Provider: {Google / Zoho / Salesforce / ...}
Fix: Delete the credential immediately (rotate it too — it's compromised). Use catalyst.connection('{connection_name}').invoke() instead.
```

---

### CONN-SEC-02 — OAuth Scopes Broader Than Needed ★ MEDIUM

Connections should request the minimum OAuth scopes needed. Over-permissioned connections cause more damage if a token is compromised.

**Check:** For each Connection in the project, review the scopes requested.

```bash
# Find connection names used in functions
grep -rn "catalyst.connection\|connection('" functions/ --include="*.js"
# For each connection name, look at its scope configuration in Catalyst console
```

Review each connection's scopes for:
- Write scopes when only read is needed
- Admin/full-access scopes when specific resource scopes exist
- Unnecessary scopes for services not actively used

**Catalog of overly broad scopes by provider:**
- Google: `https://www.googleapis.com/auth/drive` (full Drive) when only `drive.readonly` needed
- Salesforce: `full` when only `api` + specific object permissions needed
- Zoho CRM: `ZohoCRM.modules.ALL` when only specific modules needed
- GitHub: `repo` (full repo access) when only `repo:status` needed

---

### CONN-SEC-03 — Token/Response Logging ★ HIGH

```bash
# Connections API response being logged
grep -rn "connection\(\)" functions/ --include="*.js" -A 10 | \
  grep "console\.log\|logger\.\|log\."

# Logging access token from connection response
grep -rn "access_token\|accessToken" functions/ --include="*.js" | \
  grep "console\|log\."
```

OAuth tokens appearing in Catalyst function logs are visible in the Catalyst console to anyone with access.

---

### CONN-SEC-04 — Missing Error Handling on Connection Invoke ★ MEDIUM

```bash
# Connection invoke without error handling
grep -rn "connection.*invoke\|\.invoke(" functions/ --include="*.js" -A 5 | \
  grep -v "catch\|try\|\.then.*err\|error"
```

Failed connection invocations without error handling can:
- Leak partial data to the response
- Allow function to proceed without the external data (logic bypass)

---

### CONN-SEC-05 — Connection Name as User Input ★ HIGH

```bash
# Connection name derived from user input
grep -rn "connection(" functions/ --include="*.js" | \
  grep "req\.\|body\.\|param\.\|query\."
```

If an attacker can control which Connection is invoked, they may be able to invoke a more privileged connection than intended.

**Fix:** Connection names must be hardcoded strings — never derived from user input.

---

## Scalability Checklist

### CONN-SCALE-01 — Connection Created Per Request (Not Reused)

```bash
# catalyst.connection() called inside handler
grep -rn "catalyst\.connection\(" functions/ --include="*.js" -B 3 | \
  grep "exports\.\|async function\|function main"
```

The Connections object should be initialized at module level if possible. Re-creating it on every request adds unnecessary overhead.

### CONN-SCALE-02 — No Timeout on Connection Invoke

```bash
grep -rn "\.invoke(" functions/ --include="*.js" | grep -v "timeout\|Timeout"
```

External API calls through Connections without timeout configuration will block the function until the Catalyst-default function timeout, wasting execution time.

**Fix:** Set explicit timeouts on Connection invoke calls; implement circuit-breaker pattern for repeated failures.

### CONN-SCALE-03 — Sequential Connection Calls That Could Be Parallel

```bash
# Multiple awaited connection invocations in same function
grep -rn "await.*connection\|await.*invoke" functions/ --include="*.js" | \
  awk -F: '{print $1}' | sort | uniq -d
```

Multiple independent external API calls (e.g., fetch user from CRM + fetch calendar from Google) should use `Promise.all()` not sequential awaits.

---

## Common Anti-Patterns

| Anti-Pattern | Risk | Fix |
|---|---|---|
| Storing Connections response (with token) in Cache | Token cache poisoning; token leakage | Cache data, not tokens |
| Passing connection tokens to client-side | Client receives OAuth tokens | Server-side only; never expose to browser |
| Using one shared connection for all users | User A's connected account used for User B | Use per-user Connections or Zoho Connected Apps |
| Ignoring token refresh failures | Silent auth failure, stale data served | Handle 401 from Connection invoke; trigger re-auth flow |
