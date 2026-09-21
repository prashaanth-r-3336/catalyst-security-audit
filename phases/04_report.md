# Phase 4: Audit Report

## Purpose
Synthesize all findings from Security, Component, and Scalability agents into a single structured PASS/FAIL report. This is the final output the user sees.

---

## Instructions

You are the Report agent. You have:
- The Project Profile from Phase 1
- MEDIUM/LOW/INFO findings arrays from Security (Phase 2), Scalability (Phase 3), Component agents, and Recent Changes (Phase 5) — these were not sent through Verification
- `confirmed` CRITICAL/HIGH findings that survived Phase 6 Verification — these are the only CRITICAL/HIGH items that may drive the verdict
- `needs_validation` candidates from Phase 6 — source-grounded but blocked on a fact outside the repo (e.g. console-only Security Rules config); these carry no severity
- `rejected` candidates from Phase 6 — refuted; do not include these as findings anywhere in the report

Produce the final report in the format below. Do not re-analyze — synthesize and structure only. Do not re-litigate a Phase 6 verdict; if you disagree with one, note it as a caveat rather than silently overriding it.

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

  CRITICAL  │  {N}   (confirmed)
  HIGH      │  {N}   (confirmed)
  MEDIUM    │  {N}
  LOW       │  {N}
  INFO      │  {N}
  ──────────────────
  TOTAL     │  {N}

  NEEDS VALIDATION │ {N}   (blocked on a fact outside source — no severity, not counted above)
  REJECTED          │ {N}   (candidates disproved during verification — not findings, not counted above)

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
NEEDS VALIDATION (blocked on a fact outside source — not a confirmed finding)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[Only present if Phase 6 returned needs_validation candidates. These carry no severity and do
NOT affect the PASS/FAIL verdict — they are leads for the project owner to resolve, not findings.]

| Title | Location | Blocked on | How to resolve |
|-------|----------|------------|-----------------|
| {title} | {file}:{line} | {exact missing fact, e.g. "actual Security Rules authentication value"} | {console check or local step} |

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

**Only `confirmed` findings can drive the verdict.** A `rejected` candidate is not a finding and must not appear in any severity-bearing section. A `needs_validation` candidate carries no severity and never causes a FAIL by itself, no matter how alarming its description — it is a lead for the owner, not a demonstrated vulnerability. See `phases/06_verification.md`.

**FAIL** if any of:
- 1 or more `confirmed` CRITICAL findings
- 1 or more `confirmed` **blocking** HIGH findings — see the dependency scoping note below for SEC-07/SEC-16
- Hard-coded secrets detected anywhere (these are evidence-in-hand, not candidates — Verification does not gate an actually-committed secret)
- A function handling sensitive data with Security Rules `authentication: optional` confirmed from source (or no Security Rules at all) — if the actual value can't be determined from source, this is `needs_validation`, not an automatic FAIL
- ZCQL string concatenation with user input, confirmed present in the cited file:line

**Dependency finding scoping (SEC-07 / SEC-16):** A `confirmed` CRITICAL/HIGH from a dependency audit is **blocking** only if it's in a direct, production dependency with a reachable exploit path. A CRITICAL/HIGH that is transitive-only or dev-dependency-only is **advisory** — list it under "Dependency Advisories (non-blocking)" and do not let it alone flip the verdict to FAIL. This prevents near-every real repo from failing solely on unavoidable transitive npm noise.

**PASS** if all of:
- Zero `confirmed` CRITICAL findings
- Zero `confirmed` blocking HIGH findings (advisory dependency findings and needs_validation leads may still be present — list them)
- All secrets in Catalyst Environment Variables or Connections
- Every function handling sensitive data has Security Rules `authentication: required` (or equivalent API Gateway protection) plus in-handler identity resolution via `userManagement().getCurrentUser()`
- All ZCQL queries using SDK methods or parameterized patterns

**PASS with conditions** — if MEDIUM findings, advisory-only dependency findings, or needs_validation leads exist but no `confirmed` CRITICAL/blocking-HIGH: note them and require fix/resolution before next major release.

---

## Deduplication Rule

If the same vulnerability appears in both Phase 2 (Security) and a Component agent (e.g., ZCQL injection found by both), keep the finding once with the most detail. Credit the component agent's finding as the primary if it has the exact file/line.

---

## Findings ID Format

`{PHASE}-{COMPONENT}-{SEQUENCE}`  
Examples: `SEC-DS-001` (Security, Data Store, first finding), `COMP-FS-002` (Component, File Store, second), `SCALE-FN-001` (Scalability, Functions, first)
