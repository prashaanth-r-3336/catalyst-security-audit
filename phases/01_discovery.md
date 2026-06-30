# Phase 1: Project Discovery

## Purpose
Build a complete Project Profile of the Catalyst project before any audit begins. All subsequent agents receive this profile as context — it tells them which components are active, where entry points are, and what the attack surface looks like.

---

## Instructions

You are the Discovery agent. Read the Catalyst project directory thoroughly and produce a structured Project Profile. Do not make assumptions — derive everything from the actual files.

---

### 1.1 — Catalyst Config

Read `catalyst-config.json` (project root). Extract:

- `projectId` and `projectKey` — note if these are hardcoded vs referenced from env
- `projectType` — determines available services
- Function stacks defined under `functions` array
- Environment: development / staging / production

Look for multiple environment configs (`.catalystrc`, `.env.catalyst`). Flag if production and development configs share secrets.

---

### 1.2 — Function Inventory

For each function directory (typically under `functions/`):

1. Read `index.js` / `main.py` / `Main.java` (whichever applies)
2. Classify each function:

| Type | Catalyst Name | Auth Required by Platform | Notes |
|---|---|---|---|
| Advanced I/O | `advancedio` | **No** — publicly accessible | Security-critical: must self-enforce auth if needed |
| Basic I/O | `basicio` | **Yes** — Catalyst user session | Safe default; check auth context usage |
| Cron | `cron` | No (internal scheduler) | Check if also HTTP-invocable |
| Event | `event` | Internal event system | Check event source validation |
| Event Listener | `eventlistener` | Internal | Check listener scope |

3. For each function, record:
   - Function name
   - Type
   - Entry point file
   - External libraries imported (`require`/`import` statements)
   - Catalyst SDK services accessed (datastore, cache, nosql, filestore, etc.)
   - Environment variables referenced (`process.env.*` or equivalent)
   - External HTTP calls (fetch, axios, request, http, urllib, requests, etc.)
   - Any hardcoded values that look like credentials, IDs, or URLs

---

### 1.3 — Component Detection

Scan all function source files for these SDK usage patterns:

| Component | Node.js Pattern | Python Pattern | Java Pattern |
|---|---|---|---|
| Data Store | `catalyst.datastore()` | `catalyst.DataStore()` | `catalyst.dataStore()` |
| Cache | `catalyst.cache()` | `catalyst.Cache()` | `catalyst.cache()` |
| NoSQL | `catalyst.nosql()` | `catalyst.NoSQL()` | `catalyst.noSql()` |
| File Store | `catalyst.filestore()` | `catalyst.FileStore()` | `catalyst.fileStore()` |
| AppSail | Dockerfile present, `appsail` in config | same | same |
| Circuits | `catalyst.circuits()` | `catalyst.Circuits()` | `catalyst.circuits()` |
| Connections | `catalyst.connection()` | `catalyst.Connection()` | `catalyst.connection()` |
| Smart Browz | `catalyst.smartbrowz()` | `catalyst.SmartBrowz()` | `catalyst.smartBrowz()` |
| Signals | `catalyst.datastream()` | `catalyst.DataStream()` | `catalyst.dataStream()` |
| Pipelines | `catalyst.pipeline()` | `catalyst.Pipeline()` | `catalyst.pipeline()` |
| QuickML | `catalyst.ml()` | `catalyst.ML()` | `catalyst.ml()` |
| Zia Services | `catalyst.zia()` | `catalyst.Zia()` | `catalyst.zia()` |
| Job Scheduling | `catalyst.jobschedule()` | `catalyst.JobSchedule()` | `catalyst.jobSchedule()` |
| Stratus | `stratus` in config, static assets present | same | same |
| Auth | `catalyst.auth()` | `catalyst.Auth()` | `catalyst.auth()` |

Record which components are actively used (not just imported).

---

### 1.4 — Environment Variables Inventory

Grep all source files for `process.env.`, `os.environ`, `System.getenv`:

For each variable found:
1. Name
2. What it appears to store (credential? URL? feature flag?)
3. Whether it's also referenced in `catalyst-config.json` env section

Flag variables whose names suggest secrets: `*SECRET*`, `*KEY*`, `*TOKEN*`, `*PASSWORD*`, `*CREDENTIAL*`, `*PWD*`, `*API_KEY*`.

---

### 1.5 — Connections Inventory

Check Catalyst Connections configuration (`.connections/` or Connections references in config):

For each connection:
- Name and provider (Google, Salesforce, etc.)
- OAuth scopes requested
- Where it's used in function code

Flag: any OAuth client secrets or tokens appearing directly in function source code instead of via the Connections API.

---

### 1.6 — External Integrations

Scan for all external HTTP calls:

```
grep -r "fetch\|axios\|request\|http\.\|https\.\|urllib\|requests\." functions/ --include="*.js" --include="*.py" --include="*.java"
```

For each:
- Destination URL (is it hardcoded? user-controlled?)
- HTTP method
- Whether TLS verification is disabled (`rejectUnauthorized: false`, `verify=False`)
- Whether user input flows into the URL

---

### 1.7 — Dependency Inventory

For each function with a `package.json` / `requirements.txt` / `pom.xml`:

1. List all direct dependencies with pinned versions
2. Flag: unpinned versions (`^`, `~`, `*`, no version specifier)
3. Flag: packages known to have security issues (check package name against common CVEs)
4. Flag: packages with no recent updates (last publish > 2 years ago if determinable)
5. Check if lockfile (`package-lock.json`, `yarn.lock`, `poetry.lock`) is present

---

### 1.8 — Local Workspace Secret Scan (Gitignored Files)

**Critical:** gitignored local files are NOT in the repository but still exist on disk. They frequently contain live credentials that can leak via screenshots, archives, Docker build context, editor backups, or accidental copy.

Scan for gitignored files that actually exist and may contain secrets:

```bash
# Find all gitignored files that actually exist locally
git -C {projectPath} ls-files --others --ignored --exclude-standard 2>/dev/null | head -60

# Also check common secret-holding patterns regardless of gitignore
find {projectPath} -maxdepth 4 -not -path "*/.git/*" -not -path "*/node_modules/*" \
  \( -name ".env" -o -name ".env.*" -o -name "*.local" \
     -o -name "*-tokens.json" -o -name "*-token.json" \
     -o -name "org-tree-tokens*" -o -name "people-tokens*" \
     -o -name "credentials.json" -o -name "secrets.json" \
     -o -name ".claude/settings.local.json" \
     -o -name "service-account*.json" \
     -o -name "*.pem" -o -name "*.key" -o -name "*.p12" \
  \) 2>/dev/null
```

For each file found, record:
1. File path
2. Whether it's gitignored (safe from repo) but still exists locally
3. Whether it contains patterns matching live secrets (tokens, keys, passwords)
4. Whether the Docker build context would include it (check `.dockerignore`)

**Known high-risk local file patterns for Catalyst projects:**
- `.env` / `.env.local` / `.env.development` — environment variable overrides
- `*-tokens.json` — OAuth token caches from CRM sync scripts
- `catalyst-config.json` (inside `functions/*/`) — local dev env var overrides with real credentials
- `.claude/settings.local.json` — may contain AI API keys pasted into assistant settings
- `scripts/*.json` — token cache files from utility scripts

---

### 1.9 — Git History Secret Scan

Secrets committed and later removed still exist in git history. Anyone with repo clone access can recover them.

```bash
# Scan recent git history for credential-shaped strings
git -C {projectPath} log --all --oneline | head -30

# Check if any sensitive-looking files appeared in git history
git -C {projectPath} log --all --full-history --diff-filter=D -- \
  "*.env" "*-tokens.json" "*credentials*" "*secret*" "*password*" 2>/dev/null | head -20

# Grep recent commit diffs for credential patterns
git -C {projectPath} log --since="6 months ago" -p --all \
  | grep -E "(api_key|apikey|client_secret|refresh_token|access_token|password|Bearer|AKIA)" \
  | grep -v "process\.env\|your_.*_here\|placeholder\|example\|REDACTED" \
  | head -30
```

Flag: any commit that shows real credential values (not env var references or placeholders) in the diff output.

---

### 1.10 — Scripts Directory Audit

The `scripts/` directory typically holds one-off utility scripts that were written quickly and often contain hardcoded credentials.

```bash
# List all scripts
find {projectPath}/scripts -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.py" -o -name "*.sh" \) 2>/dev/null

# Grep for credential patterns
grep -rn "client_secret\|refresh_token\|apiKey\|Bearer\|Authorization.*['\"][A-Za-z0-9]{20,}\|token.*=.*['\"][A-Za-z0-9]{20,}" \
  {projectPath}/scripts/ 2>/dev/null | grep -v "process\.env"
```

Record for each script: whether it reads credentials from env vars (safe) or hardcodes them (flag).

---

### 1.11 — .gitignore and .dockerignore Completeness

Both files must exclude ALL local files that could contain secrets or PII.

```bash
cat {projectPath}/.gitignore
cat {projectPath}/.dockerignore 2>/dev/null || echo "NO .dockerignore found"
```

Check `.gitignore` covers:
- `*.env*` / `.env*`
- `*-tokens.json` / `*-token.json`
- `functions/*/catalyst-config.json`
- `*.pem` / `*.key` / `*.p12`
- `.claude/` (Claude Code local settings)
- Any AI assistant settings files

Check `.dockerignore` additionally covers:
- Everything `.gitignore` covers (Docker build context is separate from git)
- `*-records.json` / employee data exports / PII CSVs
- Generated audit reports (PDFs, HTMLs)
- Local token caches
- `node_modules/` (should already be there)

**Flag:** if `.dockerignore` is absent entirely AND an AppSail or containerized component exists.

---

## Output Format

Produce a structured **Project Profile** with these fields:

```json
{
  "project_name": "",
  "project_id": "",
  "project_id_source": "hardcoded | env_var | sdk_context",
  "functions": [
    {
      "name": "",
      "type": "advancedio | basicio | cron | event | eventlistener",
      "entry_point": "",
      "components_used": [],
      "env_vars_referenced": [],
      "external_http_calls": [],
      "has_auth_check": true
    }
  ],
  "components_in_use": ["datastore", "cache", ...],
  "env_vars": [
    {
      "name": "",
      "likely_type": "secret | url | config | unknown",
      "in_catalyst_config": true
    }
  ],
  "connections": [
    {
      "name": "",
      "provider": "",
      "scopes": [],
      "secret_in_source": false
    }
  ],
  "external_integrations": [
    {
      "url_pattern": "",
      "user_controlled": false,
      "tls_disabled": false
    }
  ],
  "dependencies": [
    {
      "function": "",
      "package": "",
      "version": "",
      "pinned": true,
      "lockfile_present": true
    }
  ],
  "flags": [
    "HARDCODED_PROJECT_ID",
    "MISSING_LOCKFILE",
    "SECRET_IN_ENV_NOT_CATALYST_CONFIG",
    ...
  ],
  "local_workspace": {
    "gitignored_files_with_secrets": [],
    "local_token_caches": [],
    "dockerignore_present": true,
    "dockerignore_gaps": []
  },
  "git_history": {
    "credentials_found_in_history": false,
    "affected_files": [],
    "rotation_required": false
  },
  "scripts": [
    {
      "file": "",
      "hardcoded_credentials": false,
      "reads_from_env": true
    }
  ]
}
```
