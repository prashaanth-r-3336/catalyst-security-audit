# Component Audit: Catalyst Data Store

## Component Overview
Catalyst Data Store is a relational database accessed via ZCQL (a SQL-like query language) or the Catalyst SDK row API. It is the most common source of both injection vulnerabilities and scalability issues in Catalyst projects.

---

## Security Checklist

### DS-SEC-01 — ZCQL Injection ★ CRITICAL

ZCQL supports a SQL-like syntax. If user input is concatenated into a ZCQL string, the attacker controls the query logic.

**Vulnerable patterns:**
```js
// VULNERABLE — direct string concatenation
const result = await datastore.table('Users')
  .ZCQL(`SELECT * FROM Users WHERE email = '${req.body.email}'`);

// VULNERABLE — template literal with user input
const result = await datastore.table('Orders')
  .ZCQL("SELECT * FROM Orders WHERE user_id = " + userId + " AND status = '" + status + "'");
```

**Grep:**
```bash
# Template literals in ZCQL
grep -rn "ZCQL\`\|\.zcql\`\|\.ZCQL(" functions/ --include="*.js" -A 1 | grep "\${req\|\${body\|\${param\|\${query\|\${user"

# String concatenation in ZCQL
grep -rn "ZCQL(" functions/ --include="*.js" | grep '".*+\|+.*"'
grep -rn "\.query(" functions/ --include="*.js" | grep '".*+\|+.*"'
```

**Safe patterns — use instead:**
```js
// SAFE — SDK row API (no ZCQL string needed)
const row = await datastore.table('Users').getRow(rowId);  // rowId is a validated integer

// SAFE — getRows with criteria object (no string building)
const rows = await datastore.table('Orders').getRows({
  criteria: { user_id: currentUser.userId, status: 'active' }
});

// SAFE — if raw ZCQL is needed, validate inputs before use
// Numeric IDs only — parseInt and validate
const safeUserId = parseInt(req.params.userId, 10);
if (isNaN(safeUserId) || safeUserId <= 0) return res.status(400).json({error: 'Invalid ID'});
```

**Finding format:**
```
[DS-SEC-01] CRITICAL: ZCQL injection via string concatenation
File: {file}:{line}
Input path: req.{body/query/params}.{field} → ZCQL string
Exploit: Attacker sends {field}=' OR '1'='1 to extract all rows
Fix: Replace with SDK getRow()/getRows() API or validate/cast input to strict type before use
```

---

### DS-SEC-02 — Missing Row-Level Authorization (IDOR) ★ HIGH

Data Store rows must be checked for ownership before serving to a user. Fetching a row by ID without verifying the row belongs to the requesting user is IDOR.

```bash
# Row access without nearby ownership check
grep -rn "getRow\|deleteRow\|updateRow" functions/ --include="*.js" -B 3 -A 5 | \
  grep -v "userId\|user_id\|CREATORID\|owner"
```

**Pattern to check:**
```js
// VULNERABLE — no ownership check after fetch
const order = await datastore.table('Orders').getRow(req.params.orderId);
return res.json(order); // User A can access User B's order by changing orderId

// SAFE — ownership check after fetch
const order = await datastore.table('Orders').getRow(req.params.orderId);
if (order.CREATORID !== currentUser.userId) {
  return res.status(403).json({ error: 'Forbidden' });
}
return res.json(order);
```

---

### DS-SEC-03 — Dynamic Table/Column Names from User Input ★ HIGH

ZCQL queries built with user-supplied table or column names cannot be fully parameterized.

```bash
grep -rn "table(\`\|table(req\.\|table(body\.\|table(param\." functions/ --include="*.js"
grep -rn "table(.*\+\|table(.*\$\{" functions/ --include="*.js"
```

**Fix:** Use an explicit allowlist of permitted table names. Reject anything not on the list.

```js
const ALLOWED_TABLES = ['Orders', 'Products', 'UserProfiles'];
const tableName = req.body.table;
if (!ALLOWED_TABLES.includes(tableName)) {
  return res.status(400).json({ error: 'Invalid table' });
}
```

---

### DS-SEC-04 — Sensitive Data Without Encryption at Rest

Check if any Data Store tables contain fields that should be encrypted:
- Passwords or password hints
- API tokens or keys
- Payment information
- Government IDs

```bash
# Column names suggesting sensitive data in ZCQL queries
grep -rn "ZCQL\|getRow\|insertRow" functions/ --include="*.js" | \
  grep -i "password\|token\|ssn\|credit_card\|cvv\|api_key\|secret"
```

**Finding:** If sensitive fields are read/written plaintext without encryption, flag as HIGH.

---

## Scalability Checklist

### DS-SCALE-01 — N+1 Query Pattern

```bash
# await on datastore inside for/while/forEach
grep -rn "for\|while\|forEach\|\.map" functions/ --include="*.js" -A 5 | \
  grep "await.*datastore\|await.*getRow\|await.*ZCQL"
```

### DS-SCALE-02 — Unbounded Result Sets

```bash
# ZCQL SELECT without LIMIT
grep -rn "\.ZCQL\|\.zcql" functions/ --include="*.js" | grep "SELECT" | grep -iv "LIMIT\|limit"
# getRows without maxRows
grep -rn "\.getRows(" functions/ --include="*.js" | grep -v "maxRows\|limit"
```

**Fix:** Always add `LIMIT {n}` to ZCQL queries; set `maxRows` on `getRows()` calls. Implement cursor-based pagination.

### DS-SCALE-03 — No Index on Frequently Queried Columns

```bash
# Columns used in WHERE clauses
grep -rn "WHERE\|where" functions/ --include="*.js" | \
  grep -oP "WHERE\s+\K\w+" | sort | uniq -c | sort -rn
```

Frequently queried columns should have indexes in the Data Store schema. Flag top-queried columns for index review.

### DS-SCALE-04 — Transaction-less Multi-Step Mutations

```bash
# Multiple insert/update/delete without transaction wrapper
grep -rn "insertRow\|updateRow\|deleteRow" functions/ --include="*.js" | \
  awk -F: '{print $1}' | sort | uniq -d
```

Multi-step mutations that aren't wrapped in a transaction can leave data in inconsistent state on partial failure. Recommend using Catalyst Data Store bulk APIs.
