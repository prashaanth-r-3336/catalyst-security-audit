# Component Audit: Catalyst Signals (Data Streams)

## Component Overview
Catalyst Signals (formerly Data Streams) enables event-driven data pipelines. Data is published to a stream and consumed by subscriber functions. Security concerns center on who can publish events, what data is in the payload, and how subscribers validate event authenticity.

---

## Security Checklist

### SIG-SEC-01 — Unauthenticated Event Publishing ★ HIGH

Who can publish events to a Signal stream? If the publish endpoint is accessible without authentication, attackers can inject crafted events that trigger downstream processing.

```bash
# Signal/stream publish calls
grep -rn "datastream\|signal\|publish\|emit" functions/ --include="*.js" -A 5 | \
  grep -v "//\s*comment"

# Advanced I/O functions that publish events
grep -rn "datastream\|signals" functions/ --include="*.js" -l
```

**Check:** For each function that publishes to a Signal stream:
1. Is the function type Basic I/O (requires Catalyst auth) or Advanced I/O (public)?
2. If Advanced I/O, does it authenticate the caller before publishing?

---

### SIG-SEC-02 — No Schema Validation on Incoming Events ★ MEDIUM

Subscriber functions that process stream events without schema validation will fail unpredictably or process malformed/crafted events.

```bash
# Subscriber functions accessing event payload without validation
grep -rn "event\.payload\|event\.data\|context\.event\|stream.*event" functions/ --include="*.js" -A 10 | \
  grep -v "validate\|schema\|typeof\|parseInt\|hasOwnProperty"
```

**Fix:** Validate event schema at the start of every subscriber function. Reject malformed events with a logged error.

---

### SIG-SEC-03 — PII in Event Payloads ★ MEDIUM

```bash
# Event payloads with PII field names
grep -rn "publish\|emit\|\.send(" functions/ --include="*.js" -A 10 | \
  grep -i "email\|phone\|address\|ssn\|credit\|password\|token"
```

Event payloads are stored and replayed. PII in event payloads creates compliance issues (retention, deletion rights).

**Fix:** Use opaque identifiers (user IDs, row IDs) in event payloads. Subscriber functions look up the actual data when needed.

---

### SIG-SEC-04 — Replay Attack via Event Reprocessing ★ MEDIUM

Events that trigger critical operations (payments, provisioning) without idempotency checks can be replayed.

```bash
# Critical operations in signal subscribers without idempotency
grep -rn "createRecord\|sendEmail\|charge\|provision\|insertRow" functions/ --include="*.js" | \
  grep -li "signal\|datastream\|stream\|subscriber" $(find functions -name "index.js") 2>/dev/null
```

**Fix:** Each event should have a unique ID. Subscriber checks if the event ID has already been processed before acting (store processed event IDs in Cache or Data Store).

---

## Scalability Checklist

### SIG-SCALE-01 — Subscriber Processing Too Slowly for Event Rate

```bash
# Subscriber functions with heavy synchronous processing
grep -rn "for\|while\|forEach\|\.map" functions/ --include="*.js" -A 5 | \
  grep "await\|async" | \
  grep -li "signal\|stream\|subscriber" $(find functions -name "index.js") 2>/dev/null
```

If events arrive faster than the subscriber can process them, a backlog builds. Heavy processing in subscribers should offload work to Immediate Jobs.

### SIG-SCALE-02 — No Dead Letter Handling

```bash
# Subscriber catch blocks without failure recording
grep -rn "catch" functions/ --include="*.js" -A 5 | \
  grep -li "signal\|stream\|subscriber" $(find functions -name "index.js") 2>/dev/null | \
  xargs grep -L "datastore\|failedEvent\|dead.letter\|error.queue" 2>/dev/null
```

Failed event processing without a dead-letter mechanism causes silent data loss. Write failed events to a `FailedSignals` table for retry.

### SIG-SCALE-03 — High-Volume Publishing Without Batching

```bash
# Loop publishing individual events
grep -rn "publish\|emit" functions/ --include="*.js" -B 5 | \
  grep "for\|while\|forEach\|\.map"
```

**Fix:** Batch event publishing where possible. Send arrays of events rather than one event per loop iteration.
