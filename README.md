# Catalyst Security Audit — Claude Code Skill

A Claude Code skill for comprehensive post-development security auditing of [Catalyst by Zoho](https://catalyst.zoho.com) projects. Point it at any Catalyst repository and get a structured PASS/FAIL report covering security, component correctness, scalability, and recent code changes.

---

## What it audits

| Track | What gets checked |
|---|---|
| **Security** | OWASP Top 10 adapted for Catalyst: Security Rules auth gaps (both Basic I/O and Advanced I/O are public by default — I/O type does not determine auth), ZCQL injection, IDOR via row IDs, SSRF, secret leakage in tracked files + gitignored local files + git history + scripts/, OAuth error injection, every route for auth middleware, npm audit across all package manifests |
| **Components** | All 15 Catalyst components in use: Functions, Data Store, Cache, NoSQL, File Store, AppSail, Circuits, Connections, Smart Browz, Signals, Pipelines, QuickML, Zia Services, Cron/Job Scheduling, Stratus |
| **Scalability** | N+1 ZCQL, cold start patterns, sync/async boundary violations, unbounded queries, cache strategy gaps, job pool usage, global state in AppSail |
| **Recent changes** | Last 30 days of commits — new secrets in diffs, new unprotected routes, dependency downgrades, auth regressions, accidentally tracked sensitive files |
| **Explicit clean areas** | Every area is reported SECURE or FINDING — nothing is silently skipped |

**For every finding:** Severity · File:Line · Description · Impact · Recommended fix · Secure code example  
**For every clean area:** Explicit "Reviewed — appears secure" with evidence

---

## Installation

### Option 1 — Plugin marketplace (recommended)

Inside Claude Code:

```
/plugin marketplace add prashaanth-r-3336/catalyst-security-audit
/plugin install catalyst-security-audit@catalyst-security-audit
```

If the install summary says to run `/reload-plugins`, do that. This is the actively maintained path — `skills/`, `commands/`, and `.claude-plugin/plugin.json` are all wired for it.

### Option 2 — install.sh (fallback)

```bash
git clone https://github.com/prashaanth-r-3336/catalyst-security-audit.git
cd catalyst-security-audit
./install.sh                                        # global → ~/.claude/
./install.sh --project /path/to/your/catalyst-project # per-project → .claude/
./install.sh --yes                                   # skip the confirmation prompt (CI)
```

This copies `phases/` and `components/`, plus a resolved copy of `skills/catalyst-security-audit/SKILL.md`, into `~/.claude/skills/catalyst-security-audit/` (or the per-project equivalent), and registers `/catalyst-security-audit` as a slash command.

---

## Usage

In any Claude Code session pointed at a Catalyst project:

```
/catalyst-security-audit
```

To audit a specific directory:

```
/catalyst-security-audit /path/to/your/catalyst-project
```

The skill runs in phases:
1. **Discovery** — builds a project profile (sequential; all later phases depend on this)
2. **Parallel fan-out** — security audit, scalability audit, recent-changes review, and one agent per active Catalyst component all run simultaneously
3. **Report** — synthesizes all findings into a PASS/FAIL report

---

## Output

```
VERDICT: PASS | FAIL

FINDINGS SUMMARY
  CRITICAL  │  N
  HIGH      │  N
  MEDIUM    │  N
  LOW       │  N

[Full findings with file:line, description, impact, fix, secure code example]

AREAS REVIEWED AND APPEARING SECURE
[Every checked area — none silently skipped]

RECENT CODE CHANGES
[Last 30 days of commits reviewed]

IMMEDIATE ACTIONS REQUIRED
[Owner-action table for all CRITICAL/HIGH items]
```

---

## Repository structure

```
catalyst-security-audit/
├── .claude-plugin/
│   ├── plugin.json                 ← Plugin manifest (name, version, skills/commands paths)
│   └── marketplace.json            ← Marketplace listing
├── skills/catalyst-security-audit/
│   └── SKILL.md                    ← Canonical orchestrator (single source of truth)
├── commands/catalyst-security-audit.md  ← Slash command — thin pointer to SKILL.md
├── .cursor-plugin/                 ← Cursor rule (self-contained — no Workflow-tool equivalent)
├── install.sh                      ← Fallback installer (see Installation above)
├── LICENSE
├── phases/
│   ├── 01_discovery.md             ← Project profile: components, functions, local files, git history, scripts
│   ├── 02_security.md              ← SEC-01 to SEC-16: Security Rules auth model, injection, secrets, routes, OAuth, deps
│   ├── 03_scalability.md           ← Catalyst-specific scalability patterns
│   ├── 04_report.md                ← PASS/FAIL report format with secure-areas table
│   └── 05_recent_changes.md        ← Last 30 days of commits review
└── components/
    ├── functions.md                 ← Function type security, auth model, cold start
    ├── datastore.md                 ← ZCQL injection, IDOR, unbounded queries
    ├── cache.md                     ← Key enumeration, cache poisoning, TTL
    ├── nosql.md                     ← Document injection, IDOR, schema validation
    ├── filestore.md                 ← File IDOR, upload validation, path traversal
    ├── appsail.md                   ← Docker secrets, non-root, health endpoints
    ├── circuits.md                  ← Workflow trigger auth, step data leakage
    ├── connections.md               ← OAuth credential storage, scope excess
    ├── smartbrowz.md               ← SSRF via user-controlled URLs
    ├── signals.md                   ← Event publishing auth, replay attacks
    ├── pipelines.md                 ← Pipeline trigger auth, transform injection
    ├── quickml.md                   ← Adversarial inputs, model output trust
    ├── zia_services.md             ← PII to Zia, biometric data retention
    ├── cron.md                      ← Idempotency, dispatch lock, job pools
    └── stratus.md                   ← Bundle secrets, security headers, source maps
```

---

## Security checks reference

| ID | Area | Risk |
|---|---|---|
| SEC-01 | Security Rules auth gap (authentication: optional on sensitive data — not an I/O-type issue) | CRITICAL |
| SEC-02 | ZCQL injection via string concatenation | CRITICAL |
| SEC-03 | Hardcoded secrets in tracked source files | HIGH |
| SEC-04 | SSRF via user-controlled external calls | HIGH |
| SEC-05 | Error handling / stack trace exposure | MEDIUM |
| SEC-06 | IDOR — resource access without ownership check | HIGH |
| SEC-07 | Vulnerable npm/pip/Maven dependencies | MEDIUM–HIGH |
| SEC-08 | CORS misconfiguration | MEDIUM |
| SEC-09 | Catalyst auth token spoofing | HIGH |
| SEC-10 | Cron function direct HTTP invocation | MEDIUM |
| SEC-11 | **Local workspace / gitignored file secrets** | CRITICAL |
| SEC-12 | **Scripts directory credential audit** | HIGH |
| SEC-13 | **Route-level auth audit (every endpoint)** | HIGH |
| SEC-14 | **OAuth error message HTML injection** | MEDIUM |
| SEC-15 | **OAuth redirect URI host inference** | LOW |
| SEC-16 | **Full npm audit across all manifests** | MEDIUM–CRITICAL |

SEC-11 through SEC-16 were added based on analysis of real-world audit patterns (local ignored files, scripts/, unauthenticated endpoints, OAuth edge cases).

> **Important:** Code cleanup does NOT invalidate already-issued OAuth tokens or API keys. Any exposed credential must be rotated/revoked immediately — removing it from source is not sufficient.

---

## Requirements

- Claude Code with Workflow tool access
- A Catalyst by Zoho project directory
- Git (for history scan and recent changes review)
- Node.js `npm` (for dependency audit, optional)

---

## Contributing

Phase files (`phases/`) and component files (`components/`) are designed to be standalone agent prompts. Each can be updated independently:
- Add new Catalyst components by adding a file to `components/` and adding its slug to the `components_in_use` enum in `phases/01_discovery.md` and `skills/catalyst-security-audit/SKILL.md`
- Add new security checks to `phases/02_security.md`
- Update the orchestrator in `skills/catalyst-security-audit/SKILL.md` to include new agents — this is the single canonical copy; `commands/catalyst-security-audit.md` just points to it

---

## License

MIT
