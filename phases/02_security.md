# Phase 2: Catalyst Security Audit

## Purpose
Cross-cutting security audit adapted for the Catalyst platform. These checks apply regardless of which components are in use. Component-specific checks are in `components/`.

---

## Instructions

You are the Security Audit agent. You have the Project Profile from Phase 1. Audit the actual source files for the vulnerabilities below. Report every finding with evidence (file path, line number, code snippet).

---

### SEC-01 — Function Authentication Model

**Risk:** CRITICAL  
Catalyst Advanced I/O functions are **publicly accessible** — no Catalyst-enforced auth. Basic I/O functions require a valid Catalyst session. Developers frequently use Advanced I/O for endpoints that should be protected.

**Check:**
1. For every function with type `advancedio` in the Project Profile:
   - Does the function handle user-specific data or perform write operations?
   - Does it call `catalyst.auth().getCurrentUser()` or equivalent auth context extraction at the top of the handler?
   - If it serves data, does it verify the authenticated user owns that data?

2. For every function with type `basicio`:
   - Does it properly extract and validate the user context from `context.catalyst.auth()` before using user identity claims?
   - Is there any path in the function that bypasses the auth context and uses a user-supplied identity claim from the request body instead?

**Grep patterns:**
```bash
# Advanced I/O functions — list them
grep -r "advancedio\|\"type\": \"Advanced I/O\"" catalyst-config.json functions/

# Check if Advanced I/O functions have auth checks
# (absence of auth check in an advancedio function = finding)

# Functions trusting user-supplied identity (risky)
grep -r "req.body.userId\|req.body.user_id\|req.query.userId" functions/ --include="*.js"
```

**Finding format:**
```
[SEC-01] CRITICAL: Advanced I/O function '{name}' handles sensitive data without auth check
File: functions/{name}/index.js
Exploit: Attacker calls the public endpoint directly, accessing/modifying other users' data
Fix: Add catalyst.auth().getCurrentUser() at handler entry; return 401 if no session; verify resource ownership
```

---

### SEC-02 — ZCQL Injection

**Risk:** CRITICAL  
Catalyst Data Store supports ZCQL queries. If user input is concatenated into a ZCQL string, attackers can manipulate the query logic to access any row in any table.

**Check:** See also `components/datastore.md` for detailed patterns.

**Grep patterns:**
```bash
# String concatenation in ZCQL
grep -rn "ZCQL\|zcql" functions/ --include="*.js" --include="*.py" | grep -i "+"
grep -rn "\.query(" functions/ --include="*.js"
grep -rn "SELECT.*\+" functions/ --include="*.js" --include="*.py"
```

**Finding format:**
```
[SEC-02] CRITICAL: ZCQL injection via string concatenation
File: functions/{name}/index.js:{line}
Code: `SELECT * FROM Users WHERE email = '` + userEmail + `'`
Exploit: Attacker sends: email = ' OR '1'='1 — returns all rows
Fix: Use SDK row methods (getRow, getRows with criteria objects) instead of raw ZCQL with user input
```

---

### SEC-03 — Secret and Credential Leakage

**Risk:** HIGH  
Secrets hardcoded in Catalyst function source code are exposed to anyone with repo access and appear in Catalyst console logs.

**Check:**
1. Grep for patterns suggesting hardcoded secrets:
```bash
grep -rn "apiKey\s*=\s*['\"][A-Za-z0-9+/]{20,}" functions/
grep -rn "secret\s*[=:]\s*['\"][^'\"]{8,}" functions/ -i
grep -rn "password\s*[=:]\s*['\"][^'\"]{4,}" functions/ -i
grep -rn "token\s*[=:]\s*['\"][A-Za-z0-9._-]{20,}" functions/ -i
grep -rn "Bearer [A-Za-z0-9._-]{20,}" functions/
grep -rn "Authorization.*['\"][A-Za-z0-9+/]{20,}" functions/
# AWS-style keys
grep -rn "AKIA[0-9A-Z]{16}" functions/
# Zoho auth tokens
grep -rn "1000\.[a-z0-9]{32}\.[a-z0-9]{32}" functions/
```

2. For each environment variable used for secrets: is it defined in Catalyst project config (under Environment Variables in Catalyst console) or in a committed `.env` file?

3. Connections: are any OAuth client_secret values appearing in source?

**Finding format:**
```
[SEC-03] HIGH: Hardcoded {credential_type} in function source
File: functions/{name}/index.js:{line}
Value: {first 4 chars}***{last 4 chars}
Fix: Move to Catalyst Environment Variables (project console → Configuration → Environment Variables); access via process.env.VAR_NAME
```

---

### SEC-04 — SSRF via User-Controlled External Calls

**Risk:** HIGH  
Any Catalyst function that makes outbound HTTP requests based on user-supplied input is vulnerable to SSRF. Attackers can reach internal Catalyst infrastructure, metadata endpoints, or internal services.

**Check:**
1. Find all external HTTP calls identified in Discovery
2. For each: does user input flow into the URL?

```bash
# Find HTTP calls where URL might be user-controlled
grep -rn "fetch\|axios\|request(" functions/ --include="*.js" -A 3 | grep -i "req\.\|body\.\|query\.\|param\."
```

3. If user-controlled URLs are found, check for:
   - Allowlist validation of the URL against permitted domains
   - IP-level validation blocking private ranges: `10.x`, `172.16-31.x`, `192.168.x`, `127.x`, `169.254.169.254`
   - Scheme validation (only `https://` permitted)

**Catalyst-specific SSRF targets to block:**
- `169.254.169.254` — cloud metadata endpoint
- `localhost` / `127.0.0.1`
- Internal Catalyst service endpoints

**Finding format:**
```
[SEC-04] HIGH: SSRF — user-controlled URL in external HTTP call
File: functions/{name}/index.js:{line}
Code: fetch(req.body.webhookUrl)
Exploit: Attacker sends webhookUrl=http://169.254.169.254/latest/meta-data/ to read cloud metadata
Fix: Validate URL against an explicit allowlist of permitted domains; block private IP ranges after DNS resolution
```

---

### SEC-05 — Error Handling and Information Disclosure

**Risk:** MEDIUM  
Catalyst function errors that return raw exception messages expose internal structure, table names, column names, and stack traces.

**Check:**
```bash
# Uncaught errors sent directly to response
grep -rn "catch.*res\.send\|catch.*basicIO\.send\|catch.*context\.res" functions/ --include="*.js"
# Stack traces in responses
grep -rn "\.stack\|error\.message\|err\.message" functions/ --include="*.js" | grep -i "send\|json\|body"
# Console.log of sensitive data
grep -rn "console\.log.*password\|console\.log.*token\|console\.log.*secret" functions/ -i
```

**Finding format:**
```
[SEC-05] MEDIUM: Stack trace / error detail exposed in function response
File: functions/{name}/index.js:{line}
Fix: Return generic error { "error": "Internal error", "requestId": correlationId }; log full detail server-side
```

---

### SEC-06 — Insecure Direct Object References (IDOR)

**Risk:** HIGH  
Catalyst resources (Data Store rows, File Store files, Cache entries) are accessed by ID. If the app doesn't verify the authenticated user owns the requested resource, any authenticated user can access any resource.

**Check:**
1. Find all places where a resource ID comes from user input (request params, body, query string)
2. For each: is there an ownership check before returning the resource?

```bash
# IDs from request being used in data access
grep -rn "req\.params\.\|req\.query\.\|req\.body\." functions/ --include="*.js" | grep -v "userId\|email" | head -50

# Direct row access without ownership check
grep -rn "getRow\|deleteRow\|updateRow" functions/ --include="*.js" -B 5
```

**Finding format:**
```
[SEC-06] HIGH: IDOR — resource {resource_type} accessed by ID without ownership verification
File: functions/{name}/index.js:{line}
Code: datastore.table('Orders').getRow(req.params.orderId)  // no ownership check
Exploit: User A changes orderId in request to access User B's order
Fix: After getRow(), verify row.CREATORID === currentUser.userId or equivalent ownership field
```

---

### SEC-07 — Dependency Vulnerabilities

**Risk:** MEDIUM to HIGH  
Vulnerable npm/pip/Maven packages in function dependencies.

**Check:**
For each function with a package manifest:
```bash
# Node.js
cd functions/{name} && npm audit --json 2>/dev/null
# Python
pip-audit -r requirements.txt 2>/dev/null
# Check for unpinned versions
grep -n "\^\\|~\\|\\*" functions/*/package.json
```

Flag: `critical` or `high` severity vulnerabilities from audit output.  
Flag: unpinned major versions (`^1.0.0`) in production functions.  
Flag: missing lockfile.

**Finding format:**
```
[SEC-07] HIGH: Vulnerable dependency {package}@{version} in function {name}
CVE: CVE-XXXX-XXXX — {description}
File: functions/{name}/package.json
Fix: Upgrade to {package}@{safe_version}; run npm audit fix
```

---

### SEC-08 — Cross-Origin Resource Sharing (CORS)

**Risk:** MEDIUM  
Advanced I/O functions that set `Access-Control-Allow-Origin: *` while also supporting credentialed requests allow any origin to make authenticated requests on behalf of users.

**Check:**
```bash
grep -rn "Access-Control-Allow-Origin\|cors(" functions/ --include="*.js"
grep -rn "allowedOrigins\|origin:" functions/ --include="*.js"
```

Flag: `Access-Control-Allow-Origin: *` combined with `Access-Control-Allow-Credentials: true`.  
Flag: CORS origin set from user-supplied `Origin` header without validation.

---

### SEC-09 — Catalyst Auth Token Misuse

**Risk:** HIGH  
Functions that accept a user identity from the request body/query (rather than from the Catalyst auth context) can be spoofed by any authenticated user claiming to be someone else.

**Check:**
```bash
# User identity from request body (risky)
grep -rn "req\.body\.userId\|req\.body\.email\|req\.body\.user_id\|req\.query\.userId" functions/ --include="*.js"

# Correct pattern — auth from Catalyst context
grep -rn "getCurrentUser\|auth()\.getCurrentUser\|auth\.getCurrentUser" functions/ --include="*.js"
```

If a function uses `req.body.userId` without also validating it against `catalyst.auth().getCurrentUser()`, that's a finding.

---

### SEC-10 — Cron and Event Function Direct Invocation

**Risk:** MEDIUM  
Cron functions are intended to run on a schedule, but if they have a public HTTP endpoint or if their function URL is guessable, attackers can trigger them manually — potentially causing duplicate processing, privilege escalation via scheduled elevated operations, or resource exhaustion.

**Check:**
1. Identify all Cron-type functions from Discovery
2. Check if they have any HTTP-facing entry in `catalyst-config.json`
3. Check if they perform operations that would be dangerous if run out of schedule (billing, provisioning, data deletion)
4. Check if they have idempotency guards

```bash
# Cron functions that modify data — check for idempotency
grep -rn "delete\|Delete\|DROP\|update\|Update\|insert\|Insert" functions/*/index.js | grep -i "cron"
```

---

### SEC-11 — Local Workspace and Gitignored File Secrets ★ CRITICAL

**Risk:** CRITICAL  
Gitignored local files — `.env`, token cache JSON files, `.claude/settings.local.json`, `catalyst-config.json` in function dirs — often contain live credentials. These don't appear in `git status` but exist on disk and can leak via Docker build context, editor backups, screenshots, zip archives, or accidental copy. Code cleanup does not invalidate already-issued tokens — rotation is always required after exposure.

**Using Discovery Phase output (1.8):**
For each gitignored file identified:
1. Does it contain live credential values (not placeholders like `your_key_here`)?
2. Is it covered by `.dockerignore`? (Gitignore and Dockerignore are separate)
3. Are the credentials it contains already rotated?

**Grep for live credential patterns in local files:**
```bash
# .env files
grep -rn "=.[A-Za-z0-9+/._-]\{20,\}" {projectPath}/.env* 2>/dev/null | \
  grep -v "example\|placeholder\|your_\|CHANGE_ME\|localhost\|false\|true"

# Token cache JSON files
find {projectPath} -maxdepth 4 -name "*-tokens.json" -o -name "*-token.json" 2>/dev/null | \
  xargs grep -l "access_token\|refresh_token\|client_secret" 2>/dev/null

# Claude Code local settings (may contain API keys pasted into assistant config)
cat {projectPath}/.claude/settings.local.json 2>/dev/null | \
  grep -i "apiKey\|api_key\|token\|secret\|anthropic\|openai"

# catalyst-config.json files in functions (gitignored dev env vars)
find {projectPath}/functions -name "catalyst-config.json" 2>/dev/null | \
  xargs grep -l "SECRET\|TOKEN\|KEY\|PASSWORD" 2>/dev/null
```

**Credential types to flag (CRITICAL — always require rotation after exposure):**
- GitHub PATs (`ghp_*`, `github_pat_*`)
- GitHub OAuth client secrets
- Zoho OAuth client secrets and refresh/access tokens
- Anthropic API keys (`sk-ant-*`)
- Any `Bearer` token value
- OAuth refresh tokens (long-lived, used to mint access tokens)

**Finding format:**
```
[SEC-11] CRITICAL: Live {credential_type} in gitignored local file
File: {file}:{line}
Status: File exists locally, not in git; credentials are live and must be rotated
Impact: Anyone with local machine access, Docker build context, or an archive/backup of the workspace can extract these credentials
Fix: 1. Rotate the credential immediately (code cleanup does not invalidate issued tokens)
     2. Delete the file or replace value with env var reference
     3. Add the file pattern to both .gitignore AND .dockerignore
```

---

### SEC-12 — Scripts Directory Credential Audit

**Risk:** HIGH  
One-off utility scripts in `scripts/` are often written quickly with hardcoded credentials and never audited. They may have introduced secrets into git history even if cleaned up later.

**Using Discovery Phase output (1.10):**
For each script file identified:
```bash
# Hardcoded credentials in scripts (not from process.env)
grep -rn "client_secret\|refresh_token\|apiKey\|access_token\|Bearer\|Authorization" \
  {projectPath}/scripts/ 2>/dev/null | grep -v "process\.env\|os\.environ\|getenv"

# Scripts that read token files (indirect credential access)
grep -rn "readFile.*token\|readFileSync.*token\|require.*token\|import.*token" \
  {projectPath}/scripts/ 2>/dev/null
```

Flag: any script that hardcodes credential values, reads from local token cache files, or builds auth strings from non-env-var sources.

---

### SEC-13 — Route-Level Auth Audit (Every Endpoint)

**Risk:** HIGH  
Every server route must have explicit auth middleware. The most common miss is endpoints added quickly that assume a later middleware will protect them — it doesn't.

For AppSail Express servers and Catalyst function routers, enumerate every route:
```bash
grep -n "app\.\(get\|post\|put\|patch\|delete\|use\)(" {projectPath}/appsail/*/index.js 2>/dev/null | \
  grep -v "//.*app\." | head -60
```

For each route found, verify:
1. Is it protected by an auth middleware called before the handler?
2. If it's a public route (health check, OAuth callback), is that intentional and documented?
3. Does it return any data that reveals internal structure (users, counts, config) without auth?

**Unauthenticated routes that are HIGH risk if unprotected:**
- Any route returning a list of users, emails, or org members
- Any route that reads or writes DataStore rows
- Any route that triggers CRM operations
- Admin/management routes

---

### SEC-14 — OAuth Error Message Injection

**Risk:** MEDIUM  
OAuth failure handlers that render `error.message` directly into HTML responses are vulnerable to reflected HTML injection if the upstream provider or a thrown error contains markup. Also applies to any server-rendered error page.

```bash
# Error messages rendered into HTML without escaping
grep -rn "res\.send\|res\.render\|\.html\b" {projectPath}/appsail/ {projectPath}/functions/ \
  --include="*.js" -A 2 | grep "error\.message\|err\.message\|e\.message\|\.message"

# Template strings with error content
grep -rn "\${.*message\|' + .*message\|\" + .*message" \
  {projectPath}/appsail/ {projectPath}/functions/ --include="*.js" | \
  grep -i "html\|render\|send\|body"
```

**Safe pattern:**
```js
function escapeHtml(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;')
    .replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
res.send(`<p>Error: ${escapeHtml(err.message)}</p>`);
```

---

### SEC-15 — OAuth Redirect URI Host Inference

**Risk:** LOW  
If `APP_URL` (or equivalent base URL env var) is not explicitly set, many OAuth implementations fall back to inferring the redirect URI from the `Host` request header (`req.get('host')`). Behind a reverse proxy that doesn't normalize the Host header, this allows redirect URI confusion.

```bash
grep -rn "req\.get('host')\|req\.headers\.host\|req\.hostname" \
  {projectPath}/appsail/ {projectPath}/functions/ --include="*.js" | \
  grep -i "redirect\|callback\|oauth\|auth"

# Check if APP_URL is explicitly set or optional
grep -rn "APP_URL\|BASE_URL\|REDIRECT_URI" \
  {projectPath}/appsail/ {projectPath}/functions/ --include="*.js"
```

**Finding:** If redirect URI construction falls back to `req.get('host')` without `APP_URL` being required → LOW finding. Fix: require `APP_URL` explicitly in production; fail startup if unset.

---

### SEC-16 — Dependency Audit Across ALL Package Manifests

**Risk:** MEDIUM to CRITICAL (depends on CVE)  
Run `npm audit` (or `pip-audit`, `mvn audit`) on every package manifest in the project — not just the main function, but also `client/`, `api/`, root, and any nested packages.

```bash
# Find all package.json files (excluding node_modules)
find {projectPath} -name "package.json" -not -path "*/node_modules/*" | head -20

# Run audit on each (in CI, use --json for machine-readable output)
for dir in $(find {projectPath} -name "package.json" -not -path "*/node_modules/*" \
  -exec dirname {} \; | sort -u); do
  echo "=== $dir ==="; cd "$dir" && npm audit --audit-level=moderate 2>/dev/null; cd -;
done
```

Report separately for each manifest:
- Total vulnerabilities by severity
- Specific CVEs for any CRITICAL/HIGH findings
- Whether `npm audit fix` was run

**Flag:** any package manifest where `npm audit` reports vulnerabilities that have not been addressed.
