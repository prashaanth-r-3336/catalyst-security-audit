# Phase 5: Recent Code Changes Security Review

## Purpose
Specifically audit recent commits (default: last 30 days, or since the last audit tag) to verify they did not introduce new security issues or regressions. This phase answers the question: "Did the latest changes make the project less secure?"

---

## Instructions

You are the Recent Changes agent. Review the git log and diffs for the project to identify security-relevant changes and verify they are correct.

---

### 5.1 — Recent Commit Inventory

```bash
# List recent commits with author and message
git -C {projectPath} log --since="30 days ago" --oneline --author-date-order 2>/dev/null | head -40

# Or if a baseline tag/commit is known:
git -C {projectPath} log {baseline_commit}..HEAD --oneline 2>/dev/null
```

For each commit, classify:
- **Security-relevant**: auth changes, route changes, credential handling, dependency updates, config changes
- **Feature**: new functionality that may introduce new attack surface
- **Fix**: bug fixes (may be security-relevant if fixing a security bug)
- **Dependency**: package version changes (always audit)

---

### 5.2 — Diff Analysis for New Secrets

```bash
# Scan the diff of recent commits for newly introduced credential patterns
git -C {projectPath} diff HEAD~10..HEAD -- \
  ":(exclude)package-lock.json" ":(exclude)yarn.lock" \
  | grep "^+" \
  | grep -E "(apiKey|api_key|client_secret|refresh_token|access_token|Bearer|password|token)\s*[=:]\s*['\"][A-Za-z0-9+/._-]{12,}" \
  | grep -v "process\.env\|os\.environ\|placeholder\|example\|your_\|CHANGE_ME"
```

Flag any diff line (starting with `+`) that contains a credential value rather than an env var reference.

---

### 5.3 — New Routes and Endpoints

```bash
# Find newly added route definitions in recent commits
git -C {projectPath} diff HEAD~10..HEAD -- "*.js" \
  | grep "^+" \
  | grep -E "app\.(get|post|put|patch|delete|use)\("
```

For each newly added route:
1. Is auth middleware applied before the handler?
2. Does it return data that should be protected?
3. Is rate limiting applied where needed?

---

### 5.4 — New File Types in Tracked Files

```bash
# Check if any sensitive file types were accidentally added to git tracking
git -C {projectPath} diff --name-only HEAD~10..HEAD | \
  grep -E "\.(env|pem|key|p12|pfx|cert|token|secret)$|credentials|tokens\.json|secrets\.json"
```

Flag any file whose extension or name suggests it should be gitignored but was committed.

---

### 5.5 — Dependency Changes

```bash
# Package.json / package-lock.json changes in recent commits
git -C {projectPath} diff HEAD~10..HEAD -- "*/package.json" "*/package-lock.json" \
  | grep "^+" | grep "\"version\"\|\"resolved\"\|\"integrity\"" | head -30

# Check if any dependency was downgraded (downgrade can reintroduce fixed CVE)
git -C {projectPath} diff HEAD~10..HEAD -- "*/package.json" \
  | grep "^-\|^+" | grep -v "^---\|^+++" | head -40
```

Flag:
- Any dependency version change that moves to an older version
- Any newly added dependency that hasn't been audited
- Removal of a security-related dependency (helmet, csrf, rate-limit)

---

### 5.6 — Auth and Authorization Changes

```bash
# Changes to auth middleware, route protection, or permission checks
git -C {projectPath} diff HEAD~10..HEAD -- \
  "*middleware*" "*auth*" "*permission*" "*role*" "*.guard.*" 2>/dev/null | head -100
```

Verify:
- No auth middleware was removed or bypassed
- Role/permission checks weren't simplified in a way that grants broader access
- No route that previously required auth was made public

---

### 5.7 — Configuration and Infrastructure Changes

```bash
# Changes to Dockerfile, .gitignore, .dockerignore, catalyst-config, CI/CD
git -C {projectPath} diff HEAD~10..HEAD -- \
  "Dockerfile" ".gitignore" ".dockerignore" "*.yml" "*.yaml" \
  "catalyst-config.json" "app-config.json" 2>/dev/null
```

Flag:
- `.gitignore` rules removed (previously ignored files now tracked)
- `.dockerignore` rules removed (sensitive files now in Docker context)
- Dockerfile changes that add secrets via `ENV`/`ARG`
- New CI/CD steps that might expose secrets in logs

---

## Output Format

For each recent commit reviewed, produce:

```
Commit: {hash} — {message}
Author: {author}
Date: {date}
Security-relevant: Yes / No
Finding: {describe any security issue found} OR "No issues found"
```

Then produce a summary:

```
RECENT CHANGES REVIEW SUMMARY
──────────────────────────────
Commits reviewed: {N} (last 30 days)
New routes added: {N} — all protected: Yes/No
Dependency changes: {N} — vulnerabilities introduced: Yes/No
New secrets in diff: None found / {list files}
Auth changes: {summary}
Config changes: {summary}

VERDICT: PASS — recent changes introduce no new security issues
      OR FAIL — {N} new issues introduced (see findings above)
```

---

## Gate Criteria

If the recent changes review finds CRITICAL or HIGH issues introduced by new commits, these must be listed prominently in the Phase 4 report under "Regressions Introduced by Recent Changes."
