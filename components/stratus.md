# Component Audit: Catalyst Stratus

## Component Overview
Stratus is Catalyst's CDN and static asset hosting. It serves frontend applications (React, Vue, Angular), static pages, and downloadable assets. Security concerns are about what gets deployed, headers on served content, and sensitive file exposure.

---

## Security Checklist

### STR-SEC-01 — Sensitive Files in Stratus Build Output ★ CRITICAL

Static build artifacts sometimes include files that should never be deployed: environment files, private keys, source maps with internal paths, CI/CD config, or test credentials.

```bash
# Check what's in the Stratus public directory
find public/ dist/ build/ stratus/ -type f 2>/dev/null | head -100

# Sensitive files in deploy directory
find public/ dist/ build/ stratus/ -name ".env*" -o -name "*.pem" -o \
  -name "*.key" -o -name "*.p12" -o -name "*.pfx" -o -name "*.cert" \
  -o -name "*.secret" -o -name "credentials.json" -o -name "*.config.js" 2>/dev/null

# Source maps (expose source code structure)
find public/ dist/ build/ -name "*.map" 2>/dev/null | head -20
```

**Flag:**
- Any `.env*` file in deploy directory → CRITICAL
- Private keys or certificate files → CRITICAL
- Source maps in production (expose source code) → MEDIUM

---

### STR-SEC-02 — Hardcoded Secrets in Frontend Bundle ★ CRITICAL

JavaScript bundles deployed via Stratus are fully public. Any secret in frontend code is completely exposed.

```bash
# Secrets in JS bundle
grep -rn "apiKey\|api_key\|secret\|password\|token" public/ dist/ build/ \
  --include="*.js" --include="*.json" | grep -v "//.*comment\|placeholder\|example" | \
  grep "['\"][A-Za-z0-9+/._-]\{20,\}['\"]"

# Catalyst project credentials in frontend
grep -rn "projectKey\|projectId\|AKIA\|1000\." public/ dist/ build/ \
  --include="*.js" 2>/dev/null
```

---

### STR-SEC-03 — Missing Security Headers ★ MEDIUM

Static assets served without security headers allow XSS, clickjacking, and MIME sniffing attacks.

**Required headers for Stratus-served pages:**
- `Content-Security-Policy` — prevent XSS
- `X-Content-Type-Options: nosniff` — prevent MIME sniffing
- `X-Frame-Options: DENY` or `SAMEORIGIN` — prevent clickjacking
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=()`

```bash
# Check if headers are configured in Catalyst Stratus settings or custom headers file
find . -name "headers.json" -o -name "_headers" -o -name "stratus.json" 2>/dev/null | \
  xargs grep -l "Content-Security-Policy\|X-Frame-Options" 2>/dev/null
```

**Flag:** If CSP and X-Frame-Options are not configured for Stratus → MEDIUM.

---

### STR-SEC-04 — Sensitive Paths Not Blocked ★ MEDIUM

Files in the deploy directory that should not be publicly accessible.

```bash
# Common sensitive paths that should not be in Stratus
find public/ dist/ build/ -name "*.bak" -o -name "*.sql" -o -name "*.log" \
  -o -name "*.json" -not -name "package.json" -o -name "*.yaml" -o \
  -name "*.yml" -o -name "Dockerfile" -o -name "*.sh" 2>/dev/null
```

---

### STR-SEC-05 — API Keys Injected via Build-Time Env Vars

React/Vue/Angular apps often inject API keys at build time via `REACT_APP_*`, `VITE_*`, `VUE_APP_*`. These become part of the public bundle.

```bash
# Build-time env var injections
grep -rn "REACT_APP_\|VITE_\|VUE_APP_\|NEXT_PUBLIC_" src/ --include="*.js" --include="*.ts" \
  --include="*.jsx" --include="*.tsx" | \
  grep -i "key\|secret\|token\|password\|credential"
```

**Flag:** Any secret-sounding variable injected as a public build env var → HIGH. Acceptable: non-secret config like `REACT_APP_API_URL`.

---

### STR-SEC-06 — No Subresource Integrity (SRI) for Third-Party CDN Scripts ★ MEDIUM

If the frontend loads scripts from external CDNs (Google Analytics, etc.) without SRI hashes, a compromised CDN can inject malicious code.

```bash
# External script tags without integrity attribute
grep -rn "<script src=\"http" public/ dist/ src/ --include="*.html" | grep -v "integrity="
grep -rn "crossorigin" src/ --include="*.html" | grep -v "integrity="
```

---

## Scalability / Performance Checklist

### STR-SCALE-01 — Unoptimized Assets

```bash
# Uncompressed images
find public/ dist/ build/ -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.gif" \
  2>/dev/null | xargs ls -lh 2>/dev/null | awk '$5 > "500K"' | head -10
# Check if webp/avif alternatives exist
find public/ dist/ build/ -name "*.webp" -o -name "*.avif" 2>/dev/null | wc -l
```

### STR-SCALE-02 — No Cache-Control Headers for Static Assets

Static assets (JS bundles, CSS, images) should have long-lived cache headers. Dynamic HTML should have `Cache-Control: no-store`.

```bash
find . -name "_headers" -o -name "headers.json" 2>/dev/null | \
  xargs grep -L "Cache-Control" 2>/dev/null
```
