# Catalyst Security Audit

**Trigger:** `/catalyst-security-audit [optional: path/to/project]`  
**Purpose:** Comprehensive post-development security audit of a Catalyst by Zoho project.

---

## Step 0 — Locate skill files

Before running, find where this skill's supporting files (phases/, components/) are installed. Run this command and store the result as `SKILL_DIR`:

```bash
find ~/.claude -maxdepth 8 -name "01_discovery.md" -path "*catalyst-security-audit*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {}
```

If that returns nothing, also try:
```bash
ls ~/.claude/skills/catalyst-security-audit/phases/01_discovery.md 2>/dev/null && echo ~/.claude/skills/catalyst-security-audit
```

`SKILL_DIR` is the directory that contains both `phases/` and `components/`.

`PROJECT` is the path the user provided, or default to the current working directory.

---

## Step 1 — Discovery (run first, sequential)

Read `${SKILL_DIR}/phases/01_discovery.md` and apply it to `${PROJECT}`. Produce a Project Profile covering:
- Which Catalyst components are in use
- All functions (name, type, entry point)
- Environment variables and Connections referenced
- Gitignored local files that exist on disk with live secrets
- Git history credential scan
- Scripts directory inventory
- All package.json / requirements.txt locations
- All server routes and whether each has auth middleware

---

## Step 2 — Parallel audit (fan out after Discovery)

Use the **Workflow tool** with a script that:

1. Reads the Project Profile from Step 1
2. Spawns these agents **in parallel**:
   - **Security** — reads `${SKILL_DIR}/phases/02_security.md`, audits `${PROJECT}` for SEC-01 through SEC-16
   - **Scalability** — reads `${SKILL_DIR}/phases/03_scalability.md`, audits `${PROJECT}`
   - **Recent changes** — reads `${SKILL_DIR}/phases/05_recent_changes.md`, reviews last 30 days of commits in `${PROJECT}`
   - **One agent per active component** — for each component in `projectProfile.components_in_use`, reads `${SKILL_DIR}/components/{component}.md` and audits `${PROJECT}`
3. Collects all findings
4. Runs the Report agent — reads `${SKILL_DIR}/phases/04_report.md` to synthesize the PASS/FAIL report

Use this Workflow script structure:

```javascript
export const meta = {
  name: 'catalyst-security-audit',
  description: 'Security, component, scalability, and recent-changes audit for Catalyst project',
  phases: [
    { title: 'Discovery' },
    { title: 'Security Audit' },
    { title: 'Component Audit' },
    { title: 'Scalability Audit' },
    { title: 'Recent Changes' },
    { title: 'Report' },
  ],
}

// Set at runtime from Step 0 discovery
const SKILL_DIR = args.skillDir
const PROJECT = args.projectPath

phase('Discovery')
const projectProfile = await agent(
  `Read ${SKILL_DIR}/phases/01_discovery.md and apply it to ${PROJECT}.
   Return a structured Project Profile JSON.`,
  { phase: 'Discovery' }
)

phase('Security Audit')
const COMPONENTS = (projectProfile?.components_in_use || [])
const COMP_FILES = COMPONENTS.map(c => `${SKILL_DIR}/components/${c}.md`)

const [secFindings, scaleFindings, recentFindings, ...compFindings] = await parallel([
  () => agent(`Read ${SKILL_DIR}/phases/02_security.md. Audit ${PROJECT}. Project profile: ${JSON.stringify(projectProfile)}. Return all findings with file:line, severity, description, impact, fix, secure code example.`, { phase: 'Security Audit' }),
  () => agent(`Read ${SKILL_DIR}/phases/03_scalability.md. Audit ${PROJECT}. Return all findings.`, { phase: 'Scalability Audit' }),
  () => agent(`Read ${SKILL_DIR}/phases/05_recent_changes.md. Review last 30 days of commits in ${PROJECT}. Return findings and secure_areas.`, { phase: 'Recent Changes' }),
  ...COMP_FILES.map(f => () => agent(`Read ${f}. Audit component usage in ${PROJECT}. Profile: ${JSON.stringify(projectProfile)}. Return findings.`, { label: f.split('/').pop(), phase: 'Component Audit' }))
])

phase('Report')
const allFindings = [
  ...(secFindings?.findings || []),
  ...(scaleFindings?.findings || []),
  ...(recentFindings?.findings || []),
  ...compFindings.filter(Boolean).flatMap(r => r?.findings || [])
]

return await agent(
  `Read ${SKILL_DIR}/phases/04_report.md. 
   Findings (${allFindings.length} total): ${JSON.stringify(allFindings)}.
   Project profile: ${JSON.stringify(projectProfile)}.
   Recent changes: ${JSON.stringify(recentFindings)}.
   REQUIRED: Include "Areas Reviewed and Appearing Secure" table.
   REQUIRED: Include "Immediate Actions Required" table for CRITICAL/HIGH.
   REQUIRED: Note that code cleanup does NOT invalidate issued tokens — rotation required.
   Produce the final PASS/FAIL report.`,
  { phase: 'Report' }
)
```

---

## Gate rules

- **Never skip Discovery.** All subsequent agents depend on the Project Profile.
- **Only audit components in use.** Discovery identifies which ones — don't spawn agents for components not detected.
- **CRITICAL or HIGH findings = FAIL verdict.**
- **Every area must appear in the report** — SECURE or FINDING. Nothing silently skipped.
- **Local workspace credential findings always require rotation** — code cleanup alone is not enough.

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
