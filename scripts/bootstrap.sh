#!/usr/bin/env bash
# bootstrap.sh — One-line setup for the Hermes + Harness orchestration template.
#
# Usage:
#   ./scripts/bootstrap.sh                  # full install
#   ./scripts/bootstrap.sh --skills-only    # skip Hermes, only install skills
#   ./scripts/bootstrap.sh --check          # verify install, install nothing
#
# Idempotent: safe to re-run.

set -euo pipefail

# ----- Config ---------------------------------------------------------------
SKILLS=(
  "development/senior-prompt-engineer"
  "development/brainstorming"
  "development/using-superpowers"
  "creative-design/frontend-design"
  "creative-design/ux-researcher-designer"
  "development/senior-architect"
  "development/senior-frontend"
  "development/senior-backend"
  "development/code-reviewer"
  "development/senior-qa"
  "development/senior-devops"
  "development/senior-security"
)

# External skills (installed via `npx skills add <repo>`)
# Format: "github-repo-url::skill-name"
EXTERNAL_SKILLS=(
  "https://github.com/coreyhaines31/marketingskills::marketing-psychology"
)

MODE="full"
for arg in "$@"; do
  case "$arg" in
    --skills-only) MODE="skills-only" ;;
    --check)       MODE="check" ;;
    *) echo "Unknown arg: $arg" >&2; exit 2 ;;
  esac
done

# ----- Color helpers --------------------------------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; NC=''
fi

ok()    { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}!${NC} %s\n" "$*"; }
err()   { printf "${RED}✗${NC} %s\n" "$*" >&2; }
step()  { printf "\n${BLUE}▸${NC} %s\n" "$*"; }

# ----- Prereq checks --------------------------------------------------------
step "Checking prerequisites"

have() { command -v "$1" >/dev/null 2>&1; }

MISSING=()
have node      || MISSING+=("node (>=18)")
have npm       || MISSING+=("npm")
have npx       || MISSING+=("npx")
have claude    || MISSING+=("claude (Claude Code CLI)")
have git       || MISSING+=("git")
if [ "$MODE" = "full" ]; then
  have hermes  || MISSING+=("hermes (Hermes Agent CLI)")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
  err "Missing required tools:"
  for m in "${MISSING[@]}"; do echo "    - $m"; done
  echo ""
  echo "Install hints:"
  echo "  Claude Code: https://docs.claude.com/claude-code"
  echo "  Hermes:      pip install hermes-agent  (or see hermes-agent.nousresearch.com)"
  exit 1
fi

ok "All required CLIs found"

# ----- Check mode exits here ------------------------------------------------
if [ "$MODE" = "check" ]; then
  step "Verifying installed skills"
  if [ -d ".claude/skills" ]; then
    INSTALLED=$(ls .claude/skills 2>/dev/null | wc -l | tr -d ' ')
    ok "$INSTALLED skill(s) found under .claude/skills/"
  else
    warn ".claude/skills/ does not exist yet — run without --check to install"
  fi
  exit 0
fi

# ----- Install skills -------------------------------------------------------
step "Installing ${#SKILLS[@]} skills from aitmpl.com"

mkdir -p .claude/skills
FAILED=()

for skill in "${SKILLS[@]}"; do
  printf "  installing %-50s " "$skill"
  if npx --yes claude-code-templates@latest --skill "$skill" --yes >/tmp/skill-install.log 2>&1; then
    printf "${GREEN}ok${NC}\n"
  else
    printf "${RED}failed${NC}\n"
    FAILED+=("$skill")
  fi
done

if [ ${#FAILED[@]} -gt 0 ]; then
  err "Some skills failed to install:"
  for s in "${FAILED[@]}"; do echo "    - $s"; done
  echo ""
  echo "See /tmp/skill-install.log for details. You can rerun this script — it's idempotent."
  exit 1
fi

ok "All skills installed"

# ----- Install external skills ----------------------------------------------
if [ ${#EXTERNAL_SKILLS[@]} -gt 0 ]; then
  step "Installing ${#EXTERNAL_SKILLS[@]} external skill(s)"
  EXT_FAILED=()
  for entry in "${EXTERNAL_SKILLS[@]}"; do
    repo="${entry%%::*}"
    skill="${entry##*::}"
    printf "  installing %-50s " "$skill"
    if npx --yes skills add "$repo" --skill "$skill" >/tmp/skill-install.log 2>&1; then
      printf "${GREEN}ok${NC}\n"
    else
      printf "${RED}failed${NC}\n"
      EXT_FAILED+=("$skill")
    fi
  done

  if [ ${#EXT_FAILED[@]} -gt 0 ]; then
    warn "Some external skills failed to install (non-blocking):"
    for s in "${EXT_FAILED[@]}"; do echo "    - $s"; done
  else
    ok "All external skills installed"
  fi
fi

# ----- State directory ------------------------------------------------------
step "Setting up .hermes-state/"
mkdir -p .hermes-state artifacts/A-pm artifacts/B-design artifacts/C-dev artifacts/D-ops

cat > .hermes-state/.gitignore <<'EOF'
# Hermes runtime state is not committed
*
!.gitignore
EOF
ok "State + artifact directories created"

# ----- gitignore additions --------------------------------------------------
step "Updating .gitignore"
touch .gitignore
for pattern in ".hermes-state/" "artifacts/draft/" ".claude/skills/*/node_modules/" "/tmp/skill-install.log"; do
  grep -qxF "$pattern" .gitignore || echo "$pattern" >> .gitignore
done
ok ".gitignore updated"

# ----- Hermes-only steps ----------------------------------------------------
if [ "$MODE" = "full" ]; then
  step "Verifying Hermes workflows"
  for wf in hermes/workflows/full-stack.yaml hermes/workflows/phase-A.yaml \
            hermes/workflows/phase-B.yaml hermes/workflows/phase-C.yaml \
            hermes/workflows/phase-D.yaml; do
    if [ -f "$wf" ]; then
      ok "$wf"
    else
      warn "$wf missing — restore from template"
    fi
  done

  step "Dry-running Hermes config"
  if hermes validate hermes/workflows/full-stack.yaml >/dev/null 2>&1; then
    ok "full-stack.yaml validates"
  else
    warn "hermes validate failed (this may be fine if your hermes version differs)"
  fi
fi

# ----- Done -----------------------------------------------------------------
echo ""
ok "Bootstrap complete."
echo ""
echo "Next steps:"
echo "  1. Edit CLAUDE.md with project-specific context"
echo "  2. Write your goal to artifacts/A-pm/goal.md"
if [ "$MODE" = "full" ]; then
  echo "  3. Start the pipeline: hermes run hermes/workflows/full-stack.yaml"
else
  echo "  3. Open Claude Code in this directory and run: /kickoff <your goal>"
fi
echo ""
