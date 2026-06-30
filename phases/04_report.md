# Phase 4: Audit Report

## Purpose
Synthesize all findings from Security, Component, and Scalability agents into a single structured PASS/FAIL report. This is the final output the user sees.

---

## Instructions

You are the Report agent. You have:
- The Project Profile from Phase 1
- All findings arrays from Security (Phase 2), Scalability (Phase 3), Component agents, and Recent Changes (Phase 5)

Produce the final report in the format below. Do not re-analyze — synthesize and structure only.

**Required for every finding:**
- Severity (Critical / High / Medium / Low)
- File name and exact line number
- Description of the issue
- Potential impact
- Recommended fix
- Secure code example (if applicable)

**Required for every area with no findings:**  
Explicitly state: "Reviewed — appears secure." with one sentence of evidence. Do not silently skip clean areas.

---

## Report Format

```
╔══════════════════════════════════════════════════════════════╗
║         CATALYST SECURITY AUDIT REPORT                      ║
║         Project: {project_name}                             ║
║         Date: {date}                                        ║
╚══════════════════════════════════════════════════════════════╝

VERDICT: PASS | FAIL

{If FAIL: "N CRITICAL and/or HIGH findings require resolution before production."}
{If PASS: "All checks passed. N MEDIUM/LOW/INFO findings documented for improvement."}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
FINDINGS SUMMARY
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  CRITICAL  │  {N}
  HIGH      │  {N}
  MEDIUM    │  {N}
  LOW       │  {N}
  INFO      │  {N}
  ──────────────────
  TOTAL     │  {N}

Coverage: {N} components audited, {N} functions reviewed, {N} dependencies scanned

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CRITICAL FINDINGS (must fix before production)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[For each CRITICAL finding:]

## [{FINDING-ID}] {Title}

**Category:** {ZCQL Injection | Auth Bypass | Secret Leakage | IDOR | SSRF | ...}
**Component:** {Data Store | Functions | File Store | ...}
**Location:** {file}:{line}

**What it is:**
{One paragraph describing the vulnerability in plain language.}

**Exploit scenario:**
{Step-by-step: "1. Attacker calls endpoint X with parameter Y set to Z. 2. Function builds ZCQL query as... 3. Result: attacker reads rows from table T belonging to other users."}

**Code evidence:**
```{language}
{offending code snippet}
```

**Fix:**
```{language}
{corrected code snippet}
```

**Reference:** {OWASP A0X | CWE-XXX | Catalyst docs link}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
HIGH FINDINGS (must fix before production)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Same format as CRITICAL]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MEDIUM FINDINGS (fix before next release)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Condensed format: Finding ID | Title | Location | One-line fix]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
LOW / INFO FINDINGS (improvement backlog)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Table format]

| ID | Title | Location | Recommendation |
|----|-------|----------|----------------|
| ... | ... | ... | ... |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AREAS REVIEWED AND APPEARING SECURE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[This section is REQUIRED. For every area with no findings, explicitly confirm it was
reviewed. Never leave this blank or skip it — an empty section reads as "not checked."]

| Area | Result | Evidence |
|------|--------|----------|
| Authentication | SECURE — {description} | {file:line} |
| Authorization | SECURE — {description} | {file:line} |
| Input validation | SECURE — {description} | {file:line} |
| Injection (ZCQL/SQL/OS) | SECURE — {description} | {file:line} |
| SSRF | SECURE — {description} OR NOT APPLICABLE | {file:line or reason} |
| XSS | SECURE — {description} | {file:line} |
| Security headers / CORS | SECURE — {description} | {file:line} |
| Tracked secret scan | CLEAN — No live secrets in tracked files | git grep result |
| Local workspace scan | CLEAN / ACTION REQUIRED — {detail} | file paths checked |
| Git history | CLEAN — No credentials in history | git log result |
| Scripts directory | CLEAN — All credentials from env vars | scripts/ grep result |
| Dependency audit | CLEAN (0 vulns) / FIXED / OPEN | npm audit result |
| Recent code changes | SECURE — {commits reviewed, summary} | commit hashes |
| .gitignore completeness | COMPLETE — covers {list key patterns} | .gitignore reviewed |
| .dockerignore completeness | COMPLETE / MISSING / GAPS — {detail} | .dockerignore reviewed |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RECENT CODE CHANGES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Commits reviewed: {N} (last 30 days, through {latest_commit_hash})

[List security-relevant commits:]
| Commit | Purpose | Security verdict |
|--------|---------|-----------------|
| {hash} | {message} | SECURE / FINDING: {ref} |

Regressions introduced: None / {list SEC-ID references}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMPONENT COVERAGE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

| Component | Audited | Findings | Status |
|-----------|---------|----------|--------|
| Functions | Yes | N | PASS/FAIL |
| Data Store | Yes | N | PASS/FAIL |
| Cache | Yes/No (not in use) | N | PASS/SKIP |
| ... | | | |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMMEDIATE ACTIONS REQUIRED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[For each CRITICAL/HIGH finding, list concrete owner actions:]

| Priority | Action | Status |
|----------|--------|--------|
| CRITICAL | {action — e.g. Rotate credential X; delete file Y} | OWNER ACTION REQUIRED |
| HIGH | {action} | REQUIRED |
| MEDIUM | {action} | RECOMMENDED |

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
IMPORTANT NOTES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Code cleanup does NOT invalidate already-issued OAuth tokens or API keys. Rotate/revoke
  any exposed credentials immediately — the credential itself must be revoked, not just
  removed from the codebase.
- This report intentionally does not print secret values — it references file locations only.
  Do not distribute outside the authorized internal review group.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WHAT TO DO NEXT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Fix all CRITICAL findings immediately — these are production blockers.
2. Fix all HIGH findings before next deployment.
3. Schedule MEDIUM findings for next sprint.
4. Add LOW/INFO items to the improvement backlog.
5. Re-run /catalyst-security-audit after fixes to verify resolution.
```

---

## Verdict Rules

**FAIL** if any of:
- 1 or more CRITICAL findings
- 1 or more HIGH findings
- Hard-coded secrets detected anywhere
- Advanced I/O functions handling sensitive data without auth checks
- ZCQL string concatenation with user input

**PASS** if all of:
- Zero CRITICAL findings
- Zero HIGH findings
- All secrets in Catalyst Environment Variables or Connections
- All functions with appropriate auth for their type
- All ZCQL queries using SDK methods or parameterized patterns

**PASS with conditions** — if MEDIUM findings exist but no CRITICAL/HIGH: note them and require fix before next major release.

---

## Deduplication Rule

If the same vulnerability appears in both Phase 2 (Security) and a Component agent (e.g., ZCQL injection found by both), keep the finding once with the most detail. Credit the component agent's finding as the primary if it has the exact file/line.

---

## Findings ID Format

`{PHASE}-{COMPONENT}-{SEQUENCE}`  
Examples: `SEC-DS-001` (Security, Data Store, first finding), `COMP-FS-002` (Component, File Store, second), `SCALE-FN-001` (Scalability, Functions, first)
