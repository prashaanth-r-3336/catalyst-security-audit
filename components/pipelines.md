# Component Audit: Catalyst Pipelines

## Component Overview
Catalyst Pipelines orchestrates multi-step data transformation workflows, typically for ETL/ELT scenarios. Pipeline steps can invoke functions, Data Store operations, and external APIs. Security focus is on pipeline trigger authentication, data leakage between steps, and injection in transformation logic.

---

## Security Checklist

### PIPE-SEC-01 — Pipeline Trigger Without Authentication ★ HIGH

Pipelines triggered via HTTP must authenticate the caller. Unauthenticated pipeline triggers allow arbitrary execution of potentially expensive or destructive data operations.

```bash
# Pipeline trigger functions
grep -rn "pipeline\|Pipeline" functions/ --include="*.js" -A 10 | \
  grep "trigger\|invoke\|start\|execute" | grep -v "//\s"

# Check if trigger has auth check
grep -rn "pipeline.*trigger\|trigger.*pipeline" functions/ --include="*.js" -B 5 | \
  grep -v "getCurrentUser\|auth()\|Authorization"
```

---

### PIPE-SEC-02 — Injection in Pipeline Transformation Logic ★ HIGH

If pipeline step transforms data using user-input-derived values (e.g., field mapping driven by user config), injection is possible.

```bash
# eval or dynamic code in pipeline steps
grep -rn "eval\|new Function\|exec(" functions/ --include="*.js" | \
  grep -li "pipeline\|transform\|step" $(find functions -name "index.js") 2>/dev/null

# Template literals with user-derived field names
grep -rn "pipeline\|transform" functions/ --include="*.js" -A 10 | \
  grep "\${req\.\|\${body\.\|\${param\."
```

---

### PIPE-SEC-03 — Sensitive Data Logged at Pipeline Steps ★ MEDIUM

```bash
grep -rn "pipeline\|Pipeline" functions/ --include="*.js" -A 15 | \
  grep "console\.log\|logger\." | \
  grep -i "data\|payload\|row\|record\|result"
```

Pipeline step logs are often verbose for debugging but should not log the full data payload — only record counts and step status.

---

### PIPE-SEC-04 — No Idempotency in Pipeline Steps ★ MEDIUM

ETL pipelines re-run on failure. If transformation steps aren't idempotent, re-runs cause duplicate records.

```bash
# Pipeline steps that insert without checking for duplicates
grep -rn "insertRow\|createRecord" functions/ --include="*.js" | \
  grep -li "pipeline\|step\|transform" $(find functions -name "index.js") 2>/dev/null | \
  xargs grep -L "upsert\|ON DUPLICATE\|update.*WHERE\|exists" 2>/dev/null
```

**Fix:** Use upsert semantics in pipeline destination writes. Check for existing record before insert.

---

## Scalability Checklist

### PIPE-SCALE-01 — Single Large Batch vs. Chunked Processing

```bash
# Pipeline steps processing full dataset at once
grep -rn "getRows\|ZCQL\|SELECT \*" functions/ --include="*.js" | \
  grep -li "pipeline\|etl\|transform" $(find functions -name "index.js") 2>/dev/null | \
  xargs grep -L "LIMIT\|limit\|chunk\|page\|batch" 2>/dev/null
```

**Fix:** Process data in configurable chunks (e.g., 500 records per step invocation). Persist progress in Data Store so pipeline can resume.

### PIPE-SCALE-02 — No Progress Tracking for Long Pipelines

```bash
grep -rn "pipeline\|Pipeline" functions/ --include="*.js" -A 20 | \
  grep -v "progress\|Progress\|checkpoint\|cursor\|lastProcessed"
```

Long-running pipelines without progress tracking restart from the beginning on failure. Add a checkpoint table.

### PIPE-SCALE-03 — External API Calls in Tight Inner Loop

```bash
grep -rn "fetch\|axios\|connection.*invoke" functions/ --include="*.js" -B 5 | \
  grep "for\|while\|forEach\|\.map" | \
  grep -li "pipeline\|transform" $(find functions -name "index.js") 2>/dev/null
```

**Fix:** Batch external API calls where the provider supports it. Cache frequently repeated API responses within the pipeline run.
