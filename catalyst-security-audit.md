# Catalyst Security Audit Skill

**Trigger:** `/catalyst-security-audit`  
**Mode:** Post-development audit — point at an existing Catalyst project directory  
**Output:** PASS/FAIL report with severity-ranked findings, exploit scenarios, and Catalyst-specific fixes

---

## What This Skill Does

Performs a comprehensive post-development audit across five tracks:

1. **Security** — OWASP Top 10 adapted for Catalyst: ZCQL injection, function auth bypass, IDOR via row IDs, SSRF, secret leakage (tracked files + gitignored local files + git history + scripts/), OAuth error injection, route-level auth gaps, dependency CVEs across all manifests
2. **Component correctness** — Every Catalyst component in use (Data Store, Cache, NoSQL, File Store, AppSail, Circuits, Connections, Smart Browz, Signals, Pipelines, QuickML, Zia Services, Functions, Cron/Job Scheduling, Stratus) audited against known anti-patterns
3. **Scalability** — N+1 ZCQL, cold start patterns, sync/async boundary violations, cache strategy gaps, job pool usage
4. **Recent code changes** — Last 30 days of commits reviewed for regressions, new secrets, auth bypasses, dependency downgrades
5. **Explicit clean-area confirmation** — Every security area is reported as SECURE or FINDING — nothing is silently skipped

**For every finding:** Severity · File:Line · Description · Impact · Recommended fix · Secure code example  
**For every clean area:** Explicit "Reviewed — appears secure" with evidence

---

## How to Run This Audit

When this skill is invoked, execute the following steps in order:

### Step 1 — Discovery (Sequential, Everything Depends on This)

Read and execute `phases/01_discovery.md`. Produce a **Project Profile** before proceeding. The Project Profile identifies:
- Which Catalyst components are actually used in this project
- All function names, types (Advanced I/O / Basic I/O / Cron / Event / Event Listener), and entry points
- All environment variable references
- All Connections referenced
- All external integrations
- Dependency inventory across ALL `package.json` / `requirements.txt` files
- Gitignored local files that exist on disk (potential secret holders)
- Git history summary (any credentials ever committed)
- Scripts directory contents and credential usage

### Step 2 — Parallel Audit (Fan Out)

After Discovery completes, use the **Workflow tool** to spawn parallel audit agents. Use this script as the basis:

```javascript
export const meta = {
  name: 'catalyst-security-audit',
  description: 'Comprehensive security, component, scalability, and recent-changes audit for Catalyst project',
  phases: [
    { title: 'Discovery' },
    { title: 'Security Audit' },
    { title: 'Component Audit' },
    { title: 'Scalability Audit' },
    { title: 'Recent Changes' },
    { title: 'Report' },
  ],
}

// Phase 1: Discovery — sequential, all audits depend on this
phase('Discovery')
const projectProfile = await agent(
  `Read phases/01_discovery.md and apply it to the Catalyst project at ${args.projectPath}. 
   Produce a structured Project Profile JSON with: components_in_use[], functions[], env_vars[], 
   connections[], external_integrations[], dependencies[].`,
  { schema: PROJECT_PROFILE_SCHEMA, phase: 'Discovery' }
)

// Phase 2: Fan out — security + scalability + component audits + recent changes in parallel
phase('Security Audit')
const COMPONENT_FILES = projectProfile.components_in_use.map(c => `components/${c}.md`)

const [securityFindings, scalabilityFindings, recentChangesFindings, ...componentFindings] = await parallel([
  // Cross-cutting security audit (includes local workspace, git history, scripts, routes, deps)
  () => agent(`Read phases/02_security.md. Audit the Catalyst project at ${args.projectPath} 
               using project profile: ${JSON.stringify(projectProfile)}.
               SEC-11 through SEC-16 are new checks — pay special attention to:
               - Local gitignored files (${projectProfile.local_workspace?.gitignored_files_with_secrets})
               - Git history credentials (${projectProfile.git_history})
               - Scripts directory (${projectProfile.scripts})
               - Every server route for auth middleware presence
               - npm audit across all manifests
               Return all findings as structured objects with file:line for each.`,
    { schema: FINDINGS_SCHEMA, phase: 'Security Audit' }),

  // Cross-cutting scalability audit
  () => agent(`Read phases/03_scalability.md. Audit the Catalyst project at ${args.projectPath}
               using project profile: ${JSON.stringify(projectProfile)}.
               Return all findings as structured objects.`,
    { schema: FINDINGS_SCHEMA, phase: 'Scalability Audit' }),

  // Recent code changes review
  () => agent(`Read phases/05_recent_changes.md. Review the last 30 days of git commits
               for the Catalyst project at ${args.projectPath}.
               Check for: new secrets introduced, auth regressions, dependency downgrades,
               new unprotected routes, sensitive files accidentally tracked.
               Return all findings as structured objects.`,
    { schema: FINDINGS_SCHEMA, phase: 'Recent Changes' }),

  // One agent per active component
  ...COMPONENT_FILES.map(componentFile => () =>
    agent(`Read ${componentFile}. Audit all usages of this component in the Catalyst project 
           at ${args.projectPath}. Project profile: ${JSON.stringify(projectProfile)}.
           Return all findings as structured objects with file:line for each.`,
      { label: componentFile, schema: FINDINGS_SCHEMA, phase: 'Component Audit' })
  )
])

// Phase 3: Synthesize report
phase('Report')
const allFindings = [
  ...(securityFindings?.findings || []),
  ...(scalabilityFindings?.findings || []),
  ...(recentChangesFindings?.findings || []),
  ...componentFindings.filter(Boolean).flatMap(r => r?.findings || [])
]

const report = await agent(
  `Read phases/04_report.md. You have ${allFindings.length} total findings across security, 
   scalability, component, and recent-changes audits. Project: ${JSON.stringify(projectProfile)}.
   Findings: ${JSON.stringify(allFindings)}.
   REQUIRED: Include the "Areas Reviewed and Appearing Secure" table — list every area
   checked with SECURE or FINDING status. Do not leave this section blank.
   REQUIRED: Include the "Recent Code Changes" section with commits reviewed.
   REQUIRED: Include the "Immediate Actions Required" table for all CRITICAL/HIGH items.
   Produce the final PASS/FAIL security report.`,
  { phase: 'Report' }
)

return report
```

Adapt the `args.projectPath` to the actual path provided by the user, or default to the current working directory.

### Step 3 — Report

The final report (from `phases/04_report.md`) is printed to the user. See that file for the exact format.

---

## Gate Rules

- **Never skip Discovery.** All agents need the Project Profile, including the local workspace and git history inventory.
- **Only audit components that are actually in use.** The Discovery phase identifies active components; don't spawn agents for unused ones.
- **CRITICAL and HIGH findings block PASS.** The report verdict is FAIL if any CRITICAL or HIGH findings remain unresolved.
- **CRITICAL from local workspace scan always requires credential rotation** — code cleanup alone is not sufficient.
- **Every area must appear in the secure-areas table.** If an area has no findings, write "Reviewed — appears secure" with one line of evidence. Never leave the table empty.
- **If the user provides a path:** use that path. If not, audit the current working directory.

---

## Quick Reference — What Each Phase/Component File Does

| File | Agents | Description |
|---|---|---|
| `phases/01_discovery.md` | 1 (sequential) | Project profile + local workspace + git history + scripts scan |
| `phases/02_security.md` | 1 (parallel) | Security checks: OWASP, local secrets, routes, OAuth, deps (SEC-01 to SEC-16) |
| `phases/03_scalability.md` | 1 (parallel) | Catalyst scalability patterns |
| `phases/04_report.md` | 1 (sequential, last) | PASS/FAIL report with secure-areas table + recent changes + immediate actions |
| `phases/05_recent_changes.md` | 1 (parallel) | Last 30 days of commits — regression and new-secret review |
| `components/functions.md` | 1 per project | Functions (all types) audit |
| `components/datastore.md` | 1 per project | Data Store / ZCQL audit |
| `components/cache.md` | 1 per project | Catalyst Cache audit |
| `components/nosql.md` | 1 per project | Catalyst NoSQL audit |
| `components/filestore.md` | 1 per project | File Store audit |
| `components/appsail.md` | 1 per project | AppSail audit |
| `components/circuits.md` | 1 per project | Circuits audit |
| `components/connections.md` | 1 per project | Connections (OAuth) audit |
| `components/smartbrowz.md` | 1 per project | Smart Browz audit |
| `components/signals.md` | 1 per project | Signals audit |
| `components/pipelines.md` | 1 per project | Pipelines audit |
| `components/quickml.md` | 1 per project | QuickML audit |
| `components/zia_services.md` | 1 per project | Zia Services audit |
| `components/cron.md` | 1 per project | Cron / Job Scheduling audit |
| `components/stratus.md` | 1 per project | Stratus (CDN/Static) audit |

---

## Findings Severity Definitions

| Severity | Catalyst Definition |
|---|---|
| **CRITICAL** | Authentication bypass, mass data breach via ZCQL injection, RCE, cross-project data access |
| **HIGH** | IDOR via File Store row ID, secret leakage in function code, SSRF via Smart Browz, missing function-level auth |
| **MEDIUM** | Cache key enumeration, insecure Cron endpoint exposure, excessive Connection scopes, verbose error leakage |
| **LOW** | Cold start inefficiency, missing cache for hot ZCQL data, N+1 patterns, deprecated SDK patterns |
| **INFO** | Scalability recommendations, architectural suggestions |
