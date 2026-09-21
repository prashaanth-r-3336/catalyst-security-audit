---
name: catalyst-security-audit
description: Comprehensive post-development security audit for Catalyst by Zoho projects. Trigger when the user asks to audit, review security, check for vulnerabilities, scan for secrets, or wants a security report on a Catalyst project. Covers OWASP Top 10 adapted for Catalyst (Security Rules / auth gaps, ZCQL injection, IDOR via row IDs, SSRF, secret leakage in tracked files and gitignored local files, git history credential scan, scripts/ directory audit, route-level auth audit, OAuth error injection, npm audit across all manifests), all 15 Catalyst components, scalability patterns (N+1 ZCQL, cold start, unbounded queries, job pools), recent code change review (last 30 days of commits), and explicit confirmation of every reviewed area. Produces a structured PASS/FAIL report with severity, file:line, description, impact, fix, and secure code example for every finding.
---

# Catalyst Security Audit

**Trigger:** `/catalyst-security-audit [optional: path/to/project]`
**Mode:** Post-development audit — point at an existing Catalyst project directory
**Output:** PASS/FAIL report with severity-ranked findings, exploit scenarios, and Catalyst-specific fixes

This is the single canonical orchestrator for this skill. `commands/catalyst-security-audit.md` (the slash command) and the Cursor rule at `.cursor-plugin/index.mdc` both point back to this file (Cursor's copy is self-contained since it has no Workflow-tool equivalent) — if you're updating audit logic, update it here first.

---

## Operating modes

- **Full audit mode** — the user explicitly runs `/catalyst-security-audit`, or asks for a full/comprehensive/end-to-end security audit or a report artifact. Run the complete six-phase workflow below and produce the PASS/FAIL report.
- **Guidance mode** — the user asks a narrow security question about a Catalyst project ("is this ZCQL query injectable?", "does this function need Security Rules?", "review this file for secrets") without asking for a full audit. Answer directly using the relevant check definitions from `phases/02_security.md`, `phases/03_scalability.md`, or the matching `components/*.md` file — do not fan out the Workflow tool, spin up parallel agents, or write report artifacts. If the request is ambiguous, ask one focused question before choosing a mode.

The rest of this document describes full audit mode.

## What This Skill Does

Performs a comprehensive post-development audit across six phases:

1. **Discovery** — project profile: components, functions, env vars, local secrets, git history, scripts
2. **Security** — OWASP Top 10 adapted for Catalyst: Security Rules / function auth gaps, ZCQL injection, IDOR via row IDs, SSRF, secret leakage (tracked files + gitignored local files + git history + scripts/), OAuth error injection, route-level auth gaps, dependency CVEs across all manifests
3. **Component correctness** — every Catalyst component in use audited against known anti-patterns
4. **Scalability** — N+1 ZCQL, cold start patterns, sync/async boundary violations, cache strategy gaps, job pool usage
5. **Recent code changes** — last 30 days of commits reviewed for regressions, new secrets, auth bypasses, dependency downgrades
6. **Verification** — every CRITICAL/HIGH candidate finding is re-checked by a fresh agent that tries to disprove it before it's allowed to drive the PASS/FAIL verdict (see `phases/06_verification.md`)

Plus **explicit clean-area confirmation** — every security area is reported as SECURE or FINDING — nothing is silently skipped.

**For every finding:** Severity · File:Line · Description · Impact · Recommended fix · Secure code example
**For every clean area:** Explicit "Reviewed — appears secure" with evidence

## Avoiding false positives

Findings from Phase 2 (Security/Scalability/Component/Recent-Changes agents) are **candidates**, not confirmed vulnerabilities, until the Verification phase (part of Step 2's Workflow, before Report) checks them. This skill has previously produced findings that turned out wrong in exactly these ways — watch for them in both hunting and verification:

- **Guessing a deployment/console fact instead of reading it from source.** Security Rules, Connections OAuth scopes, CORS domain allowlists, and production env var values may not be fully visible in tracked source. If the check depends on a fact the repo doesn't show, report it as **needs_validation** (see below) — do not assume the worst-case config and call it CRITICAL, and do not assume the best-case config and call it clean.
- **Inventing an SDK method or API shape that doesn't exist** (e.g. a `.invoke()` that isn't part of the real Connections API). Verify against `catalyst-by-zoho:catalyst-sdk`/`catalyst-by-zoho:catalyst-authentication` skill guidance or the actual SDK source in `node_modules`, not assumption.
- **Treating a checklist deviation as a vulnerability** when no real trust boundary is crossed (e.g. missing a defensive pattern that a different, present control already covers).
- **Reporting a stronger effect than what's actually observed** — a parser edge case is not automatically RCE; state only the effect the evidence supports.
- **Letting transitive/dev-dependency CVEs drive the verdict** — see the dependency scoping rule in `phases/04_report.md`.

---

## Step 0 — Resolve paths

```
SKILL_DIR = ${CLAUDE_PLUGIN_ROOT}
PROJECT   = the path argument if provided, otherwise the current working directory
```

`${CLAUDE_PLUGIN_ROOT}` is set automatically by Claude Code for plugin-installed skills and resolves to this repository's root — `phases/` and `components/` live directly under it (`${CLAUDE_PLUGIN_ROOT}/phases/`, `${CLAUDE_PLUGIN_ROOT}/components/`). If this skill was installed via `install.sh` instead of the plugin/marketplace system, `${CLAUDE_PLUGIN_ROOT}` will already have been substituted with the real absolute path at install time — treat any literal `${CLAUDE_PLUGIN_ROOT}` you see in an installed copy as a bug and fall back to the directory this file lives in.

**Important — don't assume `functions/` exists.** Every grep pattern in `phases/02_security.md`, `phases/03_scalability.md`, and `components/*.md` uses `functions/` as a placeholder for "wherever this project's function/AppSail/Stratus source actually lives." Substitute the real directories from the Discovery Project Profile (`appsail/`, `client/`, a custom src layout, etc.) — do not treat an empty `functions/` grep as a clean result on a project that doesn't use Functions.

---

## Step 1 — Discovery (sequential, everything depends on this)

Read `${SKILL_DIR}/phases/01_discovery.md` and apply it to `${PROJECT}`. Produce a Project Profile covering: components in use, all functions (name, type, entry point), env vars and Connections referenced, gitignored local files with live secrets, git history credential scan, scripts/ directory inventory, all package manifests, and every server route with its auth status.

**`components_in_use` must use exactly these slugs** (they map 1:1 to `components/*.md` filenames) — anything else and the fan-out in Step 2 silently audits nothing for that component:

```
functions | datastore | cache | nosql | filestore | appsail | circuits |
connections | smartbrowz | signals | pipelines | quickml | zia_services |
cron | stratus
```

---

## Step 2 — Parallel audit (fan out after Discovery)

Use the **Workflow tool**. Spawn, in parallel: Security (`phases/02_security.md`), Scalability (`phases/03_scalability.md`), Recent Changes (`phases/05_recent_changes.md`), and one agent per slug in `projectProfile.components_in_use` reading the matching `components/{slug}.md`. Then verify every CRITICAL/HIGH candidate (`phases/06_verification.md`) before running the Report agent (`phases/04_report.md`) to synthesize.

```javascript
export const meta = {
  name: 'catalyst-security-audit',
  description: 'Security, component, scalability, recent-changes, and verification audit for a Catalyst project',
  phases: [
    { title: 'Discovery' },
    { title: 'Security Audit' },
    { title: 'Component Audit' },
    { title: 'Scalability Audit' },
    { title: 'Recent Changes' },
    { title: 'Verification' },
    { title: 'Report' },
  ],
}

const SKILL_DIR = args.skillDir
const PROJECT = args.projectPath

phase('Discovery')
const projectProfile = await agent(
  `Read ${SKILL_DIR}/phases/01_discovery.md and apply it to ${PROJECT}.
   Return a structured Project Profile JSON. components_in_use[] must only contain values from
   this exact set: functions, datastore, cache, nosql, filestore, appsail, circuits, connections,
   smartbrowz, signals, pipelines, quickml, zia_services, cron, stratus.`,
  { phase: 'Discovery' }
)

phase('Security Audit')
const COMPONENTS = (projectProfile?.components_in_use || [])
const COMP_FILES = COMPONENTS.map(c => `${SKILL_DIR}/components/${c}.md`)

const [secFindings, scaleFindings, recentFindings, ...compFindings] = await parallel([
  () => agent(`Read ${SKILL_DIR}/phases/02_security.md. Audit ${PROJECT}. Project profile: ${JSON.stringify(projectProfile)}.
               "functions/" in that file is a placeholder — substitute this project's actual source
               directories (from the profile) wherever it appears; do not skip checks because a literal
               functions/ directory doesn't exist. Return all findings with file:line, severity,
               description, impact, fix, secure code example.`, { phase: 'Security Audit' }),
  () => agent(`Read ${SKILL_DIR}/phases/03_scalability.md. Audit ${PROJECT}. Same functions/ placeholder rule applies. Return all findings.`, { phase: 'Scalability Audit' }),
  () => agent(`Read ${SKILL_DIR}/phases/05_recent_changes.md. Review last 30 days of commits in ${PROJECT}. Return findings and secure_areas.`, { phase: 'Recent Changes' }),
  ...COMP_FILES.map(f => () => agent(`Read ${f}. Audit component usage in ${PROJECT}. Profile: ${JSON.stringify(projectProfile)}. Return findings.`, { label: f.split('/').pop(), phase: 'Component Audit' }))
])

phase('Verification')
const allCandidates = [
  ...(secFindings?.findings || []),
  ...(scaleFindings?.findings || []),
  ...(recentFindings?.findings || []),
  ...compFindings.filter(Boolean).flatMap(r => r?.findings || [])
]
const toVerify = allCandidates.filter(f => /critical|high/i.test(f?.severity || ''))
const alreadyClear = allCandidates.filter(f => !/critical|high/i.test(f?.severity || ''))

const verdicts = await parallel(toVerify.map(finding => () => agent(
  `Read ${SKILL_DIR}/phases/06_verification.md and follow it exactly.
   You did not write this finding — try to refute it from ${PROJECT}'s actual source.
   Candidate finding: ${JSON.stringify(finding)}.
   Return exactly one JSON object: {"verdict": "confirmed|needs_validation|rejected", "finding": {...}, "reason": "..."}.`,
  { label: `${finding?.id || finding?.title || 'finding'}`, phase: 'Verification' }
)))

const confirmed = verdicts.filter(v => v?.verdict === 'confirmed').map(v => v.finding)
const needsValidation = verdicts.filter(v => v?.verdict === 'needs_validation').map(v => ({ ...v.finding, blocker: v.reason }))
const rejected = verdicts.filter(v => v?.verdict === 'rejected').map(v => ({ ...v.finding, reason: v.reason }))

phase('Report')
const allFindings = [...confirmed, ...alreadyClear]

return await agent(
  `Read ${SKILL_DIR}/phases/04_report.md.
   Confirmed/unverified findings (${allFindings.length} total): ${JSON.stringify(allFindings)}.
   Needs-validation candidates (${needsValidation.length} total, blocked on a fact outside source — no severity): ${JSON.stringify(needsValidation)}.
   Rejected candidates (${rejected.length} total, disproved during verification — do not report as findings): ${JSON.stringify(rejected)}.
   Project profile: ${JSON.stringify(projectProfile)}.
   Recent changes: ${JSON.stringify(recentFindings)}.
   REQUIRED: Include "Areas Reviewed and Appearing Secure" table.
   REQUIRED: Include "Needs Validation" table for the needs-validation candidates — no severity, no verdict impact.
   REQUIRED: Include "Immediate Actions Required" table for CRITICAL/HIGH.
   REQUIRED: Note that code cleanup does NOT invalidate issued tokens — rotation required.
   Apply the Verdict Rules in phases/04_report.md exactly, including the blocking-vs-advisory
   dependency scoping and the confirmed-only verdict gate — do not FAIL on a rejected or
   needs_validation candidate, and do not FAIL solely on transitive/dev-dependency HIGH findings.
   Produce the final PASS/FAIL report.`,
  { phase: 'Report' }
)
```

Only CRITICAL/HIGH candidates go through Verification — those are the only ones that can flip the verdict to FAIL, so that's where a false positive costs the most. MEDIUM/LOW/INFO candidates pass through to the report unverified, same as before.

Adapt `args.skillDir`/`args.projectPath` to the resolved values from Step 0.

---

## Gate rules

- **Never skip Discovery.** All subsequent agents depend on the Project Profile.
- **Only audit components in use.** Discovery identifies which ones via the fixed slug list above — don't spawn agents for components not detected, and don't invent slugs.
- **Auth is never determined by function I/O type.** Both Basic I/O and Advanced I/O are public by default; the real gate is each function's Security Rules (`authentication: optional/required`) or API Gateway if that's the active layer. See `phases/02_security.md` SEC-01.
- **Every CRITICAL/HIGH candidate must survive Verification before it can drive the verdict.** Only `confirmed` CRITICAL/HIGH findings in direct/production-facing code = FAIL verdict. A `rejected` candidate is not a finding; a `needs_validation` candidate carries no severity and never causes a FAIL on its own — see `phases/06_verification.md` and the Verdict Rules in `phases/04_report.md`.
- **Transitive or dev-dependency-only HIGH findings from SEC-16/SEC-07 are advisory, not blocking** — see `phases/04_report.md` Verdict Rules.
- **Every area must appear in the report** — SECURE or FINDING. Nothing silently skipped.
- **Local workspace credential findings always require rotation** — code cleanup alone is not enough.
- **If the user provides a path:** use that path. If not, audit the current working directory.

---

## Finding format (required for every finding)

```
Severity:     Critical / High / Medium / Low
File:line:    functions/name/index.js:42
Description:  What the vulnerability is
Impact:       What happens if exploited
Fix:          Specific remediation
Secure code:  {corrected code snippet}
```

## Clean area format (required for every area with no findings)

```
Area: {name}
Result: Reviewed — appears secure
Evidence: {one line, e.g. "grep for eval/exec found nothing; all queries use sanitizeStr"}
```

---

## Quick reference — what each phase/component file does

| File | Description |
|---|---|
| `phases/01_discovery.md` | Project profile + local workspace + git history + scripts scan |
| `phases/02_security.md` | SEC-01 to SEC-16: Security Rules auth model, ZCQL injection, secrets, routes, OAuth, deps |
| `phases/03_scalability.md` | Catalyst-specific scalability patterns |
| `phases/04_report.md` | PASS/FAIL report with secure-areas table + needs-validation table + recent changes + immediate actions |
| `phases/05_recent_changes.md` | Last 30 days of commits — regression and new-secret review |
| `phases/06_verification.md` | Adversarial re-check of every CRITICAL/HIGH candidate before it can drive the verdict |
| `components/*.md` | One file per Catalyst component (see the slug list in Step 1) |

## Findings severity definitions

| Severity | Catalyst Definition |
|---|---|
| **CRITICAL** | Authentication bypass (Security Rules `optional` on sensitive data), mass data breach via ZCQL injection, RCE, cross-project data access |
| **HIGH** | IDOR via File Store row ID, secret leakage in function code, SSRF via Smart Browz, missing/misconfigured Security Rules |
| **MEDIUM** | Cache key enumeration, insecure Cron endpoint exposure, excessive Connection scopes, verbose error leakage |
| **LOW** | Cold start inefficiency, missing cache for hot ZCQL data, N+1 patterns, deprecated SDK patterns (e.g. new Cron functions instead of Job) |
| **INFO** | Scalability recommendations, architectural suggestions |
