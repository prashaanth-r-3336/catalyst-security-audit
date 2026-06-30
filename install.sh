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
  INSTALL_MODE="project ($PROJECT_PATH)"
else
  SKILLS_DIR="$HOME/.claude/skills"
  INSTALL_MODE="global (~/.claude/skills/)"
fi

SKILL_DIR="$SKILLS_DIR/$SKILL_NAME"
SKILL_ENTRY="$SKILLS_DIR/$SKILL_NAME.md"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo "Catalyst Security Audit — Skill Installer"
echo "────────────────────────────────────────────"
echo "  Install mode : $INSTALL_MODE"
echo "  Skill files  : $SKILL_DIR/"
echo "  Skill entry  : $SKILL_ENTRY"
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

# Copy main skill
cp "$SCRIPT_DIR/catalyst-security-audit.md" "$SKILL_DIR/"

# Copy phases
cp "$SCRIPT_DIR/phases/"*.md "$SKILL_DIR/phases/"

# Copy components
cp "$SCRIPT_DIR/components/"*.md "$SKILL_DIR/components/"

# Create the entry point Claude Code uses to invoke /catalyst-security-audit
# It tells Claude where to find the full skill and how to use it.
cat > "$SKILL_ENTRY" << EOF
# Catalyst Security Audit Skill

When this skill is invoked (/catalyst-security-audit), read and follow the instructions in:
${SKILL_DIR}/catalyst-security-audit.md

The supporting phase files are at:
${SKILL_DIR}/phases/

The component audit files are at:
${SKILL_DIR}/components/

Follow the orchestration steps in the main skill file exactly, substituting the above
absolute paths wherever the skill references phase or component files.
EOF

echo ""
echo "✓ Installed successfully."
echo ""
echo "Skill entry : $SKILL_ENTRY"
echo "Skill files : $SKILL_DIR/"
echo ""
echo "Usage: In any Claude Code session, type:"
echo "  /catalyst-security-audit"
echo "  /catalyst-security-audit /path/to/your/catalyst-project"
echo ""
