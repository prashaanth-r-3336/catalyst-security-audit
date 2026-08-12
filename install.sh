#!/usr/bin/env bash
# Catalyst Security Audit — Claude Code Skill Installer
#
# Fallback path only — prefer the plugin/marketplace install:
#   /plugin marketplace add prashaanth-r-3336/catalyst-security-audit
#   /plugin install catalyst-security-audit@catalyst-security-audit
#
# Usage:
#   ./install.sh                          # global install → ~/.claude/
#   ./install.sh --project /path/to/proj  # project install → /path/to/proj/.claude/
#   ./install.sh --yes                    # skip the confirmation prompt (CI / non-interactive)

set -euo pipefail

SKILL_NAME="catalyst-security-audit"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_MODE=false
PROJECT_PATH=""
ASSUME_YES=false

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project|-p)
      PROJECT_MODE=true
      PROJECT_PATH="$2"
      shift 2
      ;;
    --yes|-y)
      ASSUME_YES=true
      shift
      ;;
    --help|-h)
      echo "Usage: ./install.sh [--project /path/to/project] [--yes]"
      echo ""
      echo "  No args       Install globally to ~/.claude/"
      echo "  --project DIR Install into DIR/.claude/ (per-project)"
      echo "  --yes         Skip the confirmation prompt"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

# Non-interactive shells (CI, piped input) can't answer the confirm prompt —
# treat that the same as --yes instead of failing silently under set -e.
if [[ ! -t 0 ]]; then
  ASSUME_YES=true
fi

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
COMMAND_FILE="$COMMANDS_DIR/$SKILL_NAME.md"

# ── Confirm ───────────────────────────────────────────────────────────────────
echo ""
echo "Catalyst Security Audit — Skill Installer"
echo "────────────────────────────────────────────"
echo "  Install mode  : $INSTALL_MODE"
echo "  Skill files   : $SKILL_DIR/"
echo "  Slash command : $COMMAND_FILE"
echo ""

if $ASSUME_YES; then
  echo "Proceeding non-interactively (--yes or no TTY detected)."
else
  read -r -p "Proceed? [y/N] " confirm
  case "$confirm" in
    [yY][eE][sS]|[yY]) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ── Install ───────────────────────────────────────────────────────────────────
echo ""
echo "Installing..."

mkdir -p "$SKILL_DIR/phases"
mkdir -p "$SKILL_DIR/components"
mkdir -p "$COMMANDS_DIR"

# Copy phases and components as-is
cp "$SCRIPT_DIR/phases/"*.md "$SKILL_DIR/phases/"
cp "$SCRIPT_DIR/components/"*.md "$SKILL_DIR/components/"

# Copy the canonical SKILL.md, substituting ${CLAUDE_PLUGIN_ROOT} with the real
# install path — this installer isn't going through the plugin loader, so that
# variable is never set at runtime for this copy.
sed "s|\${CLAUDE_PLUGIN_ROOT}|${SKILL_DIR}|g" \
  "$SCRIPT_DIR/skills/catalyst-security-audit/SKILL.md" > "$SKILL_DIR/SKILL.md"

# Register as a slash command (/catalyst-security-audit).
# The command template's paths assume the plugin layout (CLAUDE_PLUGIN_ROOT = repo
# root, with skills/catalyst-security-audit/SKILL.md nested under it). This install
# puts SKILL.md directly at $SKILL_DIR, so replace the whole nested-path expression,
# not just the bare variable.
sed "s|\${CLAUDE_PLUGIN_ROOT}/skills/catalyst-security-audit/SKILL.md|${SKILL_DIR}/SKILL.md|g; \
     s|\${CLAUDE_PLUGIN_ROOT}|${SKILL_DIR}|g; \
     s|\$ARGUMENTS|\$1|g" \
  "$SCRIPT_DIR/commands/catalyst-security-audit.md" > "$COMMAND_FILE"

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
