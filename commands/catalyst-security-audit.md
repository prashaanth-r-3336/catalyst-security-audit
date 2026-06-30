Run a comprehensive post-development security audit of a Catalyst by Zoho project.

If a path was provided as an argument use that as the project path, otherwise use the current working directory.

Find the skill support files by running:
```bash
find ~/.claude -maxdepth 8 -name "01_discovery.md" -path "*catalyst-security-audit*" 2>/dev/null | head -1 | xargs -I{} dirname {} | xargs -I{} dirname {}
```

Then read that file (the main skill orchestrator) and follow its instructions exactly:
$HOME/.claude/plugins/cache/catalyst-security-audit/catalyst-security-audit/*/skills/catalyst-security-audit.md

If the above path doesn't exist, check:
- ~/.claude/skills/catalyst-security-audit/skills/catalyst-security-audit.md
- ~/.claude/commands/../skills/catalyst-security-audit/skills/catalyst-security-audit.md

The skill runs 5 parallel tracks via the Workflow tool:
1. Discovery — project profile, local workspace secrets, git history, scripts/, all routes
2. Security — SEC-01 to SEC-16 (OWASP adapted for Catalyst)
3. Scalability — N+1 ZCQL, cold start, unbounded queries, job pools
4. Recent changes — last 30 days of commits reviewed for regressions
5. Component audit — one agent per active Catalyst component

Produce a PASS/FAIL report with: severity, file:line, description, impact, fix, secure code example for every finding. Include an "Areas Reviewed and Appearing Secure" table covering every area checked.
