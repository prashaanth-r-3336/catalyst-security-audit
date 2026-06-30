# Component Audit: Catalyst Circuits

## Component Overview
Circuits is a visual workflow automation builder. Workflows are triggered by events, APIs, or schedules, and chain actions across Catalyst services and third-party integrations. Security concerns center on trigger authentication, data passed between steps, and actions performed with elevated project-level identity.

---

## Security Checklist

### CKT-SEC-01 — Unauthenticated Workflow Triggers ★ HIGH

Circuits workflows triggered via webhook/API must validate the trigger source. An unauthenticated HTTP trigger allows anyone to invoke the workflow.

```bash
# Look for Circuit webhook URLs in code — these should have auth
grep -rn "circuits\|Circuits\|workflow.*trigger\|trigger.*workflow" functions/ --include="*.js" -A 5
# Check if trigger endpoints validate a shared secret or token
grep -rn "x-webhook-secret\|hmac\|signature\|trigger.*key" functions/ --include="*.js" -i
```

**Check for each webhook-triggered Circuit:**
1. Is the trigger URL protected with a secret/token?
2. Is the secret stored in Catalyst Environment Variables (not hardcoded)?
3. Is the signature validated using constant-time comparison?

---

### CKT-SEC-02 — Sensitive Data in Workflow Context ★ MEDIUM

Data passed between Circuits workflow steps is stored in the workflow execution context. If steps log this context or it's accessible in the Catalyst console, sensitive data is exposed.

```bash
# Logging workflow context
grep -rn "circuits\|workflow" functions/ --include="*.js" -A 10 | \
  grep "console\.log\|logger\.\|log\." | \
  grep -i "context\|payload\|data\|body"
```

**Fix:** Pass only non-sensitive data between workflow steps. Use Data Store row IDs (not the row data) as step-to-step context. Fetch the data in the step that needs it.

---

### CKT-SEC-03 — No Error Handling in Workflow Steps ★ MEDIUM

```bash
# Workflow step functions without try/catch
grep -rn "circuits\|workflow" functions/ --include="*.js" -B 2 -A 20 | \
  grep -v "try\|catch\|error" | head -30
```

Workflow steps without error handling cause the entire workflow to fail silently or with a generic error, making debugging difficult and potentially leaving data in an inconsistent state.

---

### CKT-SEC-04 — Workflow Action With Broad Permissions ★ MEDIUM

Circuits actions execute with the Catalyst project identity. If a workflow performs sensitive operations (delete data, send emails, call external APIs), there should be guards:

1. Input validation in the first step (validate trigger payload before acting)
2. Business logic checks (is the user allowed to trigger this workflow?)
3. Rate limiting (can one user trigger this workflow more than N times?)

```bash
# Workflow step functions that delete or send
grep -rn "deleteRow\|sendEmail\|deleteFile\|createRecord" functions/ --include="*.js" | \
  grep -li "circuit\|workflow" $(find functions -name "index.js") 2>/dev/null
```

---

## Scalability Checklist

### CKT-SCALE-01 — Synchronous Long-Running Workflow Steps

Workflow steps that take too long delay the entire workflow. Heavy operations within a step should themselves use Job Scheduling.

```bash
# Steps with loops or multiple awaits
grep -rn "for\|while\|forEach" functions/ --include="*.js" | \
  grep -li "circuit\|workflow" $(find functions -name "index.js") 2>/dev/null
```

### CKT-SCALE-02 — No Retry Configuration on Failing Steps

External API calls in workflow steps without retry configuration fail the entire workflow on the first transient error.

**Recommendation:** Configure step retry policy in the Circuits builder (max retries, backoff). For custom function steps, implement retry at the step level.

### CKT-SCALE-03 — Workflow Fan-Out Without Concurrency Control

If a workflow triggers many parallel branches (fan-out), each branch spawns separate executions. Without concurrency limits, a single trigger can spawn hundreds of concurrent executions.

**Check:** Review workflows with parallel branching for appropriate concurrency caps or throttling at the trigger level.
