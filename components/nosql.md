# Component Audit: Catalyst NoSQL

## Component Overview
Catalyst NoSQL is a document store based on a key-value model. Documents are stored in buckets and accessed by document ID. Security risks include document injection, unauthorized access by document ID, and unvalidated schema.

---

## Security Checklist

### NOSQL-SEC-01 — Document ID Enumeration / IDOR ★ HIGH

NoSQL documents accessed by a user-supplied document ID without ownership verification are IDOR-vulnerable.

```bash
# NoSQL document access using request-supplied ID
grep -rn "nosql\(\)\|NoSQL\(\)" functions/ --include="*.js" -A 10 | \
  grep "req\.params\|req\.query\|req\.body" | grep -i "get\|fetch\|read"

# Document delete/update with user-supplied ID
grep -rn "nosql.*delete\|nosql.*update\|nosql.*set" functions/ --include="*.js" -B 5 | \
  grep "req\."
```

**Fix:** After fetching a document, verify `document.metadata.owner === currentUser.userId` or equivalent ownership field before returning.

---

### NOSQL-SEC-02 — Injection via Document Queries ★ MEDIUM

If NoSQL supports query operators and user input flows into query conditions without validation, operator injection is possible.

```bash
# Query conditions using user input
grep -rn "nosql.*query\|nosql.*find\|nosql.*filter" functions/ --include="*.js" -A 5 | \
  grep "req\.\|body\.\|param\."
```

**Fix:** Validate and sanitize all query field values. Reject values containing query operator syntax (e.g., `$where`, `$regex`, `{}`).

---

### NOSQL-SEC-03 — Unvalidated Document Schema ★ MEDIUM

NoSQL is schema-flexible — any JSON structure can be stored. Without schema validation at write time, attackers can inject unexpected fields.

```bash
# Document insert/update without validation
grep -rn "nosql.*set\|nosql.*insert\|nosql.*put" functions/ --include="*.js" -B 5 | \
  grep "req\.body\b" | grep -v "validate\|schema\|Joi\|zod\|ajv"
```

**Exploit:** Attacker includes `isAdmin: true` in a document payload, which gets stored and later used for privilege checks.

**Fix:** Validate document structure against a strict schema before writing. Strip unexpected fields.

---

### NOSQL-SEC-04 — Sensitive Data in Documents Without Encryption

```bash
# Documents containing sensitive field names
grep -rn "nosql.*set\|nosql.*insert" functions/ --include="*.js" -A 5 | \
  grep -i "password\|token\|secret\|ssn\|credit_card\|api_key"
```

Sensitive fields stored in plaintext NoSQL documents should be encrypted before storage.

---

## Scalability Checklist

### NOSQL-SCALE-01 — Fetching Full Documents When Only Partial Data Needed

```bash
grep -rn "nosql.*get\|nosql.*fetch" functions/ --include="*.js" -A 5 | \
  grep -v "fields\|projection\|select\|keys"
```

**Fix:** Use field projection to fetch only required fields, reducing network transfer and memory.

### NOSQL-SCALE-02 — Document Size Not Bounded

Documents stored without size limits can grow unbounded (e.g., appending to an array field).

```bash
# Array field appends without length check
grep -rn "nosql" functions/ --include="*.js" -A 10 | \
  grep "push\|append\|concat" | grep -v "length\|limit\|max"
```

### NOSQL-SCALE-03 — Missing Pagination on Document Listing

```bash
grep -rn "nosql.*list\|nosql.*scan\|nosql.*getAll" functions/ --include="*.js" | \
  grep -v "limit\|pageSize\|cursor\|nextToken"
```
