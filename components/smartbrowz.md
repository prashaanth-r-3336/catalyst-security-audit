# Component Audit: Catalyst Smart Browz

## Component Overview
Smart Browz is a headless browser service. A Catalyst function instructs Smart Browz to navigate to URLs, interact with pages, and extract data. Because Smart Browz makes outbound requests from within the Catalyst infrastructure, user-controlled URLs create a Server-Side Request Forgery (SSRF) risk — the most critical vulnerability for this component.

---

## Security Checklist

### SB-SEC-01 — SSRF via User-Controlled URL ★ CRITICAL

If the URL passed to Smart Browz originates from user input, attackers can direct the headless browser to internal Catalyst services, cloud metadata endpoints, or other internal infrastructure.

```bash
# Smart Browz URL from request
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -A 10 | \
  grep "req\.\|body\.\|param\.\|query\." | grep -i "url\|navigate\|goto"

# Direct URL from request body/params
grep -rn "smartbrowz" functions/ --include="*.js" -A 5 | \
  grep "\(req\.\|body\.\|param\.\|query\."
```

**SSRF targets to block:**
- `http://169.254.169.254/` — AWS/GCP/Azure metadata endpoint
- `http://localhost` / `http://127.0.0.1`
- `http://10.*` / `http://172.16-31.*` / `http://192.168.*` — RFC 1918 private ranges
- `file://` — local file system access
- `gopher://`, `ftp://` — alternative protocol attacks

**Required validation before passing URL to Smart Browz:**
```js
const { URL } = require('url');
const dns = require('dns').promises;

async function validateUrl(rawUrl) {
  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    throw new Error('Invalid URL');
  }

  // Only HTTPS
  if (parsed.protocol !== 'https:') throw new Error('Only HTTPS URLs permitted');

  // Allowlist of permitted domains (preferred over blocklist)
  const ALLOWED_DOMAINS = ['partner1.com', 'partner2.com'];
  if (!ALLOWED_DOMAINS.some(d => parsed.hostname === d || parsed.hostname.endsWith('.' + d))) {
    throw new Error('Domain not in allowlist');
  }

  // Resolve DNS and validate IP is not private
  const addresses = await dns.resolve4(parsed.hostname);
  for (const ip of addresses) {
    if (isPrivateIP(ip)) throw new Error('Private IP range — SSRF blocked');
  }

  return parsed.toString();
}
```

**Finding format:**
```
[SB-SEC-01] CRITICAL: SSRF — user-controlled URL passed to Smart Browz
File: {file}:{line}
Input path: req.{body/query/params}.{field} → smartbrowz navigate
Exploit: Attacker sends url=http://169.254.169.254/latest/meta-data/ to read cloud infrastructure metadata
Fix: Validate URL against domain allowlist; block private IP ranges after DNS resolution; permit only HTTPS
```

---

### SB-SEC-02 — Credentials Passed to Smart Browz Pages ★ HIGH

If Smart Browz is used to log into third-party sites (scraping authenticated content), credentials must come from Catalyst Connections or Environment Variables — not from user input.

```bash
# Smart Browz interactions with credential-like patterns
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -A 20 | \
  grep -i "password\|credential\|login\|username\|secret" | \
  grep "req\.\|body\.\|param\."
```

**Finding:** Credentials from user request passed to a Smart Browz login interaction → HIGH.

---

### SB-SEC-03 — Extracted Data Not Sanitized Before Use ★ MEDIUM

Data extracted from browsed pages (web scraping results) is untrusted. Using it directly (as HTML, in queries, in commands) can lead to XSS, injection, or stored XSS.

```bash
# Smart Browz result used in downstream operations
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -A 15 | \
  grep "datastore\|cache\|nosql\|innerHTML\|eval\|exec"
```

**Fix:** Treat all Smart Browz output as untrusted external data. Validate and sanitize before storing or rendering.

---

### SB-SEC-04 — No Timeout on Smart Browz Sessions ★ MEDIUM

```bash
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -A 10 | \
  grep -v "timeout\|Timeout\|timeOut"
```

Smart Browz sessions without timeouts can hang indefinitely, holding up function execution and accumulating cost.

**Fix:** Always set page navigation timeout and overall session timeout.

---

### SB-SEC-05 — Smart Browz Result Contains PII

```bash
# Logging or storing Smart Browz results
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -A 15 | \
  grep "console\.log\|datastore.*insert\|cache.*put\|nosql.*set"
```

If scraped pages contain PII (names, emails, phone numbers), storing or logging this data creates compliance obligations (GDPR, CCPA) depending on the data source.

---

## Scalability Checklist

### SB-SCALE-01 — Smart Browz in Synchronous Function

Smart Browz is inherently slow (page load + JavaScript execution). Running it in an Advanced I/O or Basic I/O function risks timeout.

```bash
# Smart Browz usage in non-cron function types
grep -rn "smartbrowz\|SmartBrowz" functions/ --include="*.js" -l
# Cross-reference with function types from Discovery
```

**Recommendation:** Move Smart Browz operations to Cron functions or Immediate Jobs where longer execution times are supported.

### SB-SCALE-02 — Multiple Serial Smart Browz Navigations

```bash
grep -rn "smartbrowz\|navigate\|goto" functions/ --include="*.js" | \
  awk -F: '{print $1}' | sort | uniq -c | sort -rn | head -5
```

Multiple page navigations in a single session should be minimized. If scraping multiple URLs, consider separate jobs.
