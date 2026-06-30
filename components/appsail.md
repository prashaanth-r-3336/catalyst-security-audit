# Component Audit: Catalyst AppSail

## Component Overview
AppSail runs containerized applications (Docker) within Catalyst. It is for long-running, stateful, or high-memory workloads that don't fit the Functions model. Container security, secret management, and network exposure are the primary concerns.

---

## Security Checklist

### SAIL-SEC-01 — Secrets in Dockerfile or Image Layers ★ CRITICAL

Secrets embedded in `Dockerfile` (via `ENV`, `ARG`, or `COPY`) are baked into image layers and visible in `docker history`.

```bash
# Dockerfile — ENV with secret-sounding names
grep -rn "ENV.*SECRET\|ENV.*KEY\|ENV.*PASSWORD\|ENV.*TOKEN\|ENV.*CREDENTIAL" \
  */Dockerfile* appsail/*/Dockerfile 2>/dev/null

# ARG used to pass secrets (also baked into layers)
grep -rn "^ARG.*SECRET\|^ARG.*KEY\|^ARG.*TOKEN" */Dockerfile* 2>/dev/null

# .env files COPY'd into image
grep -rn "COPY.*\.env\|ADD.*\.env" */Dockerfile* 2>/dev/null
```

**Fix:** Use Catalyst AppSail Environment Variables (set in Catalyst console); access via `process.env.VAR` at runtime — never bake into image.

---

### SAIL-SEC-02 — Running as Root in Container ★ HIGH

Containers running as root give any container escape exploits full host access.

```bash
# No USER directive in Dockerfile
grep -rn "^USER" */Dockerfile* appsail/*/Dockerfile 2>/dev/null | wc -l
# If 0 results — running as root
```

**Fix:** Add `USER appuser` (non-root) to Dockerfile. Create the user in the build stage:
```dockerfile
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser
USER appuser
```

---

### SAIL-SEC-03 — Health Endpoint Exposes Sensitive Information ★ MEDIUM

AppSail health check endpoints that return internal diagnostics (dependency versions, DB connection strings, environment variables) leak information.

```bash
# Health endpoint handler
grep -rn "\/health\|\/status\|\/ping\|healthcheck" \
  appsail/ --include="*.js" --include="*.py" --include="*.go" -A 15 | \
  grep -i "version\|env\|config\|db\|connection\|process\.env"
```

**Fix:** Health endpoint returns only `{ "status": "ok" }`. Move diagnostics to a protected admin endpoint with auth.

---

### SAIL-SEC-04 — No Non-Root User + Minimal Base Image ★ MEDIUM

```bash
# Check base image
grep -rn "^FROM" */Dockerfile* 2>/dev/null

# Flags:
# FROM ubuntu, FROM debian (large attack surface — prefer slim/alpine)
# FROM node:latest (unpinned)
# FROM python:latest (unpinned)
```

**Best practices:**
- Use `node:20-alpine`, `python:3.11-slim`, not `ubuntu` or `debian`
- Pin exact image version with SHA digest: `FROM node:20.11.0-alpine3.19@sha256:...`
- Multi-stage builds to exclude build tools from final image

---

### SAIL-SEC-05 — Exposed Debug Ports or Admin Endpoints ★ MEDIUM

```bash
# EXPOSE in Dockerfile — check for non-standard ports
grep -rn "^EXPOSE" */Dockerfile* 2>/dev/null

# Debug endpoints in code
grep -rn "debug\|DEBUG\|9229\|5858\|--inspect" appsail/ --include="*.js" -r
```

**Fix:** Only expose the port the application serves on. Remove debug/inspect flags from production CMD/ENTRYPOINT.

---

### SAIL-SEC-06 — Dependency Vulnerabilities in Container

```bash
# Package.json / requirements.txt in AppSail — audit these
find appsail/ -name "package.json" -not -path "*/node_modules/*"
find appsail/ -name "requirements.txt"

# Run audit
cd appsail && npm audit --json 2>/dev/null | jq '.vulnerabilities | to_entries[] | select(.value.severity == "critical" or .value.severity == "high")'
```

---

## Scalability Checklist

### SAIL-SCALE-01 — No Resource Limits Set

If `docker-compose.yml` or AppSail config defines resource limits, check they're appropriate. Unconstrained containers can starve other services.

```bash
grep -rn "memory\|cpu\|resources\|limits" appsail/ --include="*.yml" --include="*.yaml"
```

### SAIL-SCALE-02 — No Graceful Shutdown Handler

```bash
# SIGTERM handler
grep -rn "SIGTERM\|SIGINT\|process\.on.*'exit'" appsail/ --include="*.js" --include="*.py"
```

AppSail containers receive SIGTERM on scale-down or deployment. Without graceful shutdown, in-flight requests are dropped.

**Fix:**
```js
process.on('SIGTERM', () => {
  server.close(() => { process.exit(0); });
});
```

### SAIL-SCALE-03 — Single Instance — No Horizontal Scale Consideration

```bash
# Global in-memory state (breaks multi-instance)
grep -rn "^const\s\+[A-Z_]\+\s*=\s*\[\|^const\s\+[A-Z_]\+\s*=\s*{" appsail/ --include="*.js"
grep -rn "global\." appsail/ --include="*.js"
```

AppSail can run multiple instances. Global in-memory state (rate limit counters, session maps) won't be shared. Move to Cache or Data Store.
