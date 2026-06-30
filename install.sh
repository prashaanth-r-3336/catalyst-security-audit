#!/usr/bin/env bash
# Catalyst Security Audit — Claude Code Skill Installer
# Usage:
#   ./install.sh                          # global install → ~/.claude/skills/
#   ./install.sh --project /path/to/proj  # project install → /path/to/proj/.claude/skills/

set -euo pipefail

SKILL_NAME="catalyst-security-audit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_MODE=false
PROJECT_PATH=""

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|-p)
      PROJECT_MODE=true
      PROJECT_PATH="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: ./install.sh [--project /path/to/project]"
      echo ""
      echo "  No args       Install globally to ~/.claude/skills/"
      echo "  --project DIR Install into DIR/.claude/skills/ (per-project)"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# ── Determine target directory ────────────────────────────────────────────────
if $PROJECT_MODE; then
  if [[ -z "$PROJECT_PATH" ]]; then
    echo "Error: --project requires a path." >&2
    exit 1
  fi
  if [[ ! -d "$PROJECT_PATH" ]]; then
    echo "Error: project path does not exist: $PROJECT_PATH" >&2
    exit 1
  fi
  SKILLS_DIR="$PROJECT_PATH/.claude/skills"
  COMMANDS_DIR="$PROJECT_PATH/.claude/commands"
  INSTALL_MODE="project ($PROJECT_PATH)"
else
  SKILLS_DIR="$HOME/.claude/skills"
  COMMANDS_DIR="$HOME/.claude/commands"
  INSTALL_MODE="global (~/.claude/)"
fi

SKILL_DIR="$SKILLS_DIR/$SKILL_NAME"
SKILL_ENTRY="$SKILLS_DIR/$SKILL_NAME.md"
COMMAND_FILE="$COMMANDS_DIR/$SKILL_NAME.md"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo "Catalyst Security Audit — Skill Installer"
echo "────────────────────────────────────────────"
echo "  Install mode  : $INSTALL_MODE"
echo "  Skill files   : $SKILL_DIR/"
echo "  Slash command : $COMMAND_FILE"
echo ""
read -r -p "Proceed? [y/N] " confirm
case "$confirm" in
  [yY][eE][sS]|[yY]) ;;
  *) echo "Aborted."; exit 0 ;;
esac

# ── Install ───────────────────────────────────────────────────────────────────
echo ""
echo "Installing..."

mkdir -p "$SKILL_DIR/phases"
mkdir -p "$SKILL_DIR/components"
mkdir -p "$COMMANDS_DIR"

# Copy main skill and supporting files
cp "$SCRIPT_DIR/catalyst-security-audit.md" "$SKILL_DIR/"
cp "$SCRIPT_DIR/phases/"*.md "$SKILL_DIR/phases/"
cp "$SCRIPT_DIR/components/"*.md "$SKILL_DIR/components/"

# Create the skills/ entry point (for the skill tool reference)
cat > "$SKILL_ENTRY" << EOF
# Catalyst Security Audit Skill

When this skill is invoked, read and follow the instructions in:
${SKILL_DIR}/catalyst-security-audit.md

The supporting phase files are at: ${SKILL_DIR}/phases/
The component audit files are at:  ${SKILL_DIR}/components/

Follow the orchestration steps in the main skill file exactly, substituting
the above absolute paths wherever the skill references phase or component files.
EOF

# ── Register as a slash command (/catalyst-security-audit) ───────────────────
# Commands in ~/.claude/commands/ are invocable as slash commands in Claude Code.
# This is separate from the plugin skill system and is what enables /catalyst-security-audit.
cat > "$COMMAND_FILE" << EOF
Run a comprehensive post-development security audit of a Catalyst by Zoho project.

Project path: use the argument if provided, otherwise use the current working directory.

Read the full skill orchestrator at ${SKILL_DIR}/catalyst-security-audit.md and follow
its instructions exactly, using these absolute paths:
- SKILL_DIR = ${SKILL_DIR}
- Phases:     ${SKILL_DIR}/phases/
- Components: ${SKILL_DIR}/components/

The skill runs 5 parallel tracks via the Workflow tool:
1. Discovery — project profile, local workspace secrets, git history, scripts/, all routes
2. Security — SEC-01 to SEC-16 (OWASP adapted for Catalyst)
3. Scalability — N+1 ZCQL, cold start, unbounded queries, job pools
4. Recent changes — last 30 days of commits reviewed for regressions
5. Component audit — one agent per active Catalyst component

Produce a PASS/FAIL report with severity, file:line, description, impact, fix, and
secure code example for every finding. Include an "Areas Reviewed and Appearing Secure"
table covering every area checked.
EOF

echo ""
echo "✓ Installed successfully."
echo ""
echo "  Skill files   : $SKILL_DIR/"
echo "  Slash command : $COMMAND_FILE"
echo ""
echo "Usage in any Claude Code session:"
echo "  /catalyst-security-audit"
echo "  /catalyst-security-audit /path/to/your/catalyst-project"
echo ""
