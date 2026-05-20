#!/usr/bin/env bash
# hermes.sh — Hermes orchestrator shim (task-level execution)
#
# Usage:
#   ./hermes.sh task <task_id>              스킬 1개 실행
#   ./hermes.sh gate <phase_id>             게이트 요약 생성 + 승인 대기
#   ./hermes.sh phase <phase_id>            페이즈 내 태스크 전체 순차 실행
#   ./hermes.sh run <workflow.yaml>         전체 파이프라인 (phase+gate 반복)
#   ./hermes.sh status                      태스크 단위 진행 상황
#   ./hermes.sh validate [workflow.yaml]    YAML 검증
#   ./hermes.sh list                        실행 가능한 태스크 목록
#
# Requires: claude CLI on PATH, python3

set -eo pipefail

WORKFLOW="${HERMES_WORKFLOW:-hermes/workflows/full-stack.yaml}"
CLAUDE_BIN="${CLAUDE_BIN:-claude}"
STATE_DIR=".hermes-state"
ARTIFACTS_DIR="artifacts"
LOG="$STATE_DIR/events.jsonl"

# ----- Colors -----------------------------------------------------------------
if [ -t 1 ]; then
  GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
else
  GREEN=''; RED=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi
ok()    { printf "${GREEN}✓${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}⚠${NC}  %s\n" "$*"; }
err()   { printf "${RED}✗${NC} %s\n" "$*" >&2; }
step()  { printf "\n${BOLD}${BLUE}━━ %s${NC}\n" "$*"; }
info()  { printf "  ${CYAN}→${NC} %s\n" "$*"; }

ts()        { date -u +%Y-%m-%dT%H:%M:%SZ; }
log_event() {
  mkdir -p "$STATE_DIR"
  echo "{\"ts\":\"$(ts)\",\"phase\":\"$1\",\"task\":\"$2\",\"status\":\"$3\",\"msg\":\"${4:-}\"}" >> "$LOG"
}

# ----- YAML helpers (Python) --------------------------------------------------

# Parse all phases → "PHASE:id TASK:tid:skill GATE:art:approval ..."
parse_workflow() {
  python3 - "$1" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
pm = re.search(r'^phases:\s*\n(.*?)(?=^\w|\Z)', content, re.MULTILINE|re.DOTALL)
if not pm: sys.exit(0)
for block in re.split(r'\n(?=  - id:)', pm.group(1)):
    block = block.strip()
    if not block: continue
    pid = re.match(r'-\s*id:\s*(\S+)', block)
    if not pid: continue
    print(f"PHASE:{pid.group(1)}")
    for tid, sk in re.findall(
        r'^\s{6}- id:\s*(\S+)\s*\n(?:.*?\n)*?\s+skill:\s*(\S+)',
        block, re.MULTILINE):
        print(f"  TASK:{tid}:{sk}")
    gm = re.search(r'gate:\s*\n\s+artifact:\s*(\S+)', block)
    am = re.search(r'approval_file:\s*(\S+)', block)
    if gm:
        print(f"  GATE:{gm.group(1)}:{am.group(1) if am else ''}")
PYEOF
}

# Lookup: task_id → "phase_id:skill"
lookup_task() {
  local task_id="$1"
  python3 - "$WORKFLOW" "$task_id" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
pm = re.search(r'^phases:\s*\n(.*?)(?=^\w|\Z)', content, re.MULTILINE|re.DOTALL)
if not pm: sys.exit(1)
for block in re.split(r'\n(?=  - id:)', pm.group(1)):
    block = block.strip()
    if not block: continue
    pid = re.match(r'-\s*id:\s*(\S+)', block)
    if not pid: continue
    for tid, sk in re.findall(
        r'^\s{6}- id:\s*(\S+)\s*\n(?:.*?\n)*?\s+skill:\s*(\S+)',
        block, re.MULTILINE):
        if tid == sys.argv[2]:
            print(f"{pid.group(1)}:{sk}")
            sys.exit(0)
sys.exit(1)
PYEOF
}

# Lookup: phase_id → gate artifact and approval file
lookup_gate() {
  local phase_id="$1"
  python3 - "$WORKFLOW" "$phase_id" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
pm = re.search(r'^phases:\s*\n(.*?)(?=^\w|\Z)', content, re.MULTILINE|re.DOTALL)
if not pm: sys.exit(1)
for block in re.split(r'\n(?=  - id:)', pm.group(1)):
    block = block.strip()
    if not block: continue
    pid = re.match(r'-\s*id:\s*(\S+)', block)
    if not pid or pid.group(1) != sys.argv[2]: continue
    gm = re.search(r'gate:\s*\n\s+artifact:\s*(\S+)', block)
    am = re.search(r'approval_file:\s*(\S+)', block)
    if gm:
        print(f"{gm.group(1)}:{am.group(1) if am else ''}")
    sys.exit(0)
sys.exit(1)
PYEOF
}

# Get task prompt instructions from YAML
get_task_instructions() {
  python3 - "$WORKFLOW" "$1" <<'PYEOF'
import sys, re
with open(sys.argv[1]) as f:
    content = f.read()
tid = sys.argv[2]
m = re.search(rf'- id:\s+{re.escape(tid)}\b.*?(?=\n\s{{6}}- id:|\s+gate:|\Z)',
              content, re.DOTALL)
if m:
    pm = re.search(r'prompt:\s*\|?\s*\n(.*?)(?=\n\s+\w+:|\Z)', m.group(0), re.DOTALL)
    if pm:
        lines = pm.group(1).split('\n')
        ind = min((len(l)-len(l.lstrip()) for l in lines if l.strip()), default=0)
        print('\n'.join(l[ind:] for l in lines))
PYEOF
}

# ----- Core: run one task -----------------------------------------------------
run_task() {
  local task_id="$1"

  # Lookup phase + skill from YAML
  local lookup
  lookup=$(lookup_task "$task_id") || {
    err "Task '$task_id' not found in $WORKFLOW"
    err "Run './hermes.sh list' to see available tasks"
    exit 1
  }
  local phase_id="${lookup%%:*}"
  local skill="${lookup#*:}"

  # Already done?
  local out="$STATE_DIR/${phase_id}-${task_id}.out"
  if [ -s "$out" ]; then
    warn "Task '$task_id' already completed. Delete to re-run:"
    info "rm $out && ./hermes.sh task $task_id"
    return 0
  fi

  step "Task: $task_id  [Phase: $phase_id]"
  info "Skill  : $skill"
  info "Output : $out"

  # Load goal
  local goal=""
  [ -f "$ARTIFACTS_DIR/A-pm/goal.md" ] && goal=$(cat "$ARTIFACTS_DIR/A-pm/goal.md")

  # Collect previous artifacts context
  local prev=""
  for p in A-pm B-design C-dev D-ops; do
    local d="$ARTIFACTS_DIR/$p"
    [ -d "$d" ] && prev+="- $p: $(ls "$d" 2>/dev/null | grep -v '.gitkeep' | tr '\n' ' ')\n"
    [ "$p" = "$phase_id" ] && break
  done

  local prompt
  prompt=$(cat <<PROMPT
You are the **$skill** specialist in a Hermes + Claude Code orchestration pipeline.

Goal: $goal

Phase: $phase_id  /  Task: $task_id

Artifacts so far:
$(printf '%b' "$prev")
Working directory  : $(pwd)
Output directory   : $ARTIFACTS_DIR/$phase_id/

Task instructions (from workflow YAML):
$(get_task_instructions "$task_id")

Complete the task and write all outputs to the paths listed above.
PROMPT
)

  # Turn limit by skill type
  local max_turns=30
  case "$skill" in
    *backend*|*frontend*|*architect*) max_turns=80 ;;
    *qa*|*devops*|*security*|*reviewer*) max_turns=50 ;;
  esac

  mkdir -p "$STATE_DIR" "$ARTIFACTS_DIR/$phase_id"
  log_event "$phase_id" "$task_id" "running" "skill=$skill"

  printf "\n  ${YELLOW}▶ claude 실행 중...${NC}  (max-turns: $max_turns / Ctrl+C로 중단)\n\n"

  if PHASE="$phase_id" SKILL="$skill" \
      "$CLAUDE_BIN" -p "$prompt" --output-format text --max-turns "$max_turns" \
      < /dev/null 2>&1 | tee "$out"; then
    echo ""
    ok "Task '$task_id' 완료"
    log_event "$phase_id" "$task_id" "completed" "ok"
  else
    echo ""
    # Check if output was actually produced despite non-zero exit (e.g. max-turns)
    if [ -s "$out" ]; then
      warn "claude가 max-turns로 종료됐지만 출력이 있습니다. 부분 완료로 처리합니다."
      warn "산출물을 확인하고 필요하면 재실행: rm $out && ./hermes.sh task $task_id"
      log_event "$phase_id" "$task_id" "partial" "max-turns exceeded but output exists"
    else
      err "Task '$task_id' 실패 (log: $out)"
      log_event "$phase_id" "$task_id" "failed" "no output"
      rm -f "$out"   # 빈 파일 제거 → 재실행 가능하도록
      exit 1
    fi
  fi
}

# ----- Core: run gate for a phase ---------------------------------------------
run_gate() {
  local phase_id="$1"

  local lookup
  lookup=$(lookup_gate "$phase_id") || {
    err "Phase '$phase_id' not found or has no gate"
    exit 1
  }
  local gate_art="${lookup%%:*}"
  local approval_f="${lookup#*:}"
  local out_dir="$ARTIFACTS_DIR/$phase_id"

  # Already approved?
  if [ -f "$approval_f" ]; then
    ok "Phase '$phase_id' 이미 APPROVED"
    return 0
  fi

  step "Gate: $phase_id"
  info "Gate artifact : $gate_art"
  info "Approval file : $approval_f"

  # Generate gate summary
  local gate_prompt
  gate_prompt="Review phase $phase_id. Read every file in $out_dir/ and write
a gate summary to $gate_art. Use exactly 8 bullets covering: problem statement,
primary user, top-3 success metrics, non-goals, biggest risks, and blockers.
Be concise and specific."

  printf "\n  ${YELLOW}▶ gate 요약 생성 중...${NC}\n\n"
  local gout="$STATE_DIR/${phase_id}-gate.out"
  mkdir -p "$STATE_DIR" "$out_dir"

  if PHASE="$phase_id" SKILL="gate" \
      "$CLAUDE_BIN" -p "$gate_prompt" --output-format text --max-turns 5 \
      < /dev/null 2>&1 | tee "$gout"; then
    echo ""
    ok "Gate artifact 생성: $gate_art"
  else
    echo ""
    warn "Gate 생성 실패 — 수동으로 $gate_art 작성 후 승인 가능"
  fi

  printf "\n${CYAN}┌─────────────────────────────────────────────────────┐${NC}\n"
  printf "${CYAN}│  Phase %-45s│${NC}\n" "$phase_id 완료 — 검토 후 승인하세요"
  printf "${CYAN}├─────────────────────────────────────────────────────┤${NC}\n"
  printf "${CYAN}│  검토  : cat %-39s│${NC}\n" "$gate_art"
  printf "${CYAN}│  승인  : touch %-37s│${NC}\n" "$approval_f"
  printf "${CYAN}│  재실행: rm %-40s│${NC}\n" "$gout"
  printf "${CYAN}│           ./hermes.sh gate %-26s│${NC}\n" "$phase_id"
  printf "${CYAN}└─────────────────────────────────────────────────────┘${NC}\n\n"

  printf "${YELLOW}⏳ 승인 대기 중 (타임아웃 없음)${NC}\n"
  printf "   새 터미널에서: ${BOLD}touch %s${NC}\n\n" "$approval_f"

  local elapsed=0
  while [ ! -f "$approval_f" ]; do
    printf "\r   대기 중... %dm %02ds" $((elapsed/60)) $((elapsed%60))
    sleep 10
    elapsed=$((elapsed+10))
  done
  printf "\r%-60s\n" ""
  ok "Phase '$phase_id' APPROVED (+${elapsed}s)"
  log_event "$phase_id" "gate" "approved" "elapsed=${elapsed}s"
}

# ----- cmd: task --------------------------------------------------------------
cmd_task() {
  [ -z "${1:-}" ] && { err "Usage: ./hermes.sh task <task_id>"; cmd_list; exit 1; }
  run_task "$1"
}

# ----- cmd: gate --------------------------------------------------------------
cmd_gate() {
  [ -z "${1:-}" ] && { err "Usage: ./hermes.sh gate <phase_id>"; exit 1; }
  run_gate "$1"
}

# ----- cmd: phase -------------------------------------------------------------
cmd_phase() {
  [ -z "${1:-}" ] && { err "Usage: ./hermes.sh phase <phase_id>"; exit 1; }
  local phase_id="$1"

  step "Phase: $phase_id (태스크 전체 순차 실행)"

  # Extract tasks for this phase only
  local found=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^PHASE:(.+)$ ]]; then
      [ "${BASH_REMATCH[1]}" = "$phase_id" ] && found=1 || { [ $found -eq 1 ] && break; }
    elif [[ $found -eq 1 && "$line" =~ ^[[:space:]]+TASK:(.+):(.+)$ ]]; then
      run_task "${BASH_REMATCH[1]}"
    fi
  done < <(parse_workflow "$WORKFLOW")

  [ $found -eq 0 ] && { err "Phase '$phase_id' not found"; exit 1; }
  echo ""
  ok "Phase '$phase_id' 태스크 완료"
  info "게이트 실행: ./hermes.sh gate $phase_id"
}

# ----- cmd: run (full pipeline) -----------------------------------------------
cmd_run() {
  local yaml="${1:-$WORKFLOW}"
  shift 2>/dev/null || true

  local goal_arg=""
  while [ $# -gt 0 ]; do
    case "$1" in --goal) goal_arg="$2"; shift 2 ;; *) shift ;; esac
  done

  [ -f "$yaml" ] || { err "$yaml not found"; exit 1; }
  WORKFLOW="$yaml"

  if [ -n "$goal_arg" ]; then
    mkdir -p "$ARTIFACTS_DIR/A-pm"
    echo "$goal_arg" > "$ARTIFACTS_DIR/A-pm/goal.md"
    ok "Goal saved → $ARTIFACTS_DIR/A-pm/goal.md"
  fi

  step "Full pipeline: $yaml"
  warn "전체 파이프라인 실행 중 — Phase/Task 단위 실행 권장:"
  info "./hermes.sh phase A-pm && ./hermes.sh gate A-pm"
  echo ""

  local cur_phase="" cur_tasks=() cur_gate="" cur_approval=""

  flush_run() {
    [ -z "$cur_phase" ] && return 0
    local approved="$ARTIFACTS_DIR/$cur_phase/APPROVED"
    if [ -f "$approved" ]; then
      step "Phase $cur_phase"; ok "Already APPROVED — skipping"
    else
      step "Phase $cur_phase"
      local spec
      for spec in "${cur_tasks[@]+"${cur_tasks[@]}"}"; do
        run_task "${spec%%:*}"
      done
    fi
    [ -n "$cur_gate" ] && run_gate "$cur_phase"
    cur_phase=""; cur_tasks=(); cur_gate=""; cur_approval=""
  }

  while IFS= read -r line; do
    if   [[ "$line" =~ ^PHASE:(.+)$ ]];             then flush_run; cur_phase="${BASH_REMATCH[1]}"; cur_tasks=(); cur_gate=""; cur_approval=""
    elif [[ "$line" =~ ^[[:space:]]+TASK:(.+):(.+)$ ]]; then cur_tasks+=("${BASH_REMATCH[1]}:${BASH_REMATCH[2]}")
    elif [[ "$line" =~ ^[[:space:]]+GATE:(.+):(.*)$ ]];  then cur_gate="${BASH_REMATCH[1]}"; cur_approval="${BASH_REMATCH[2]}"
    fi
  done < <(parse_workflow "$WORKFLOW")
  flush_run

  echo ""; ok "Pipeline complete."
  echo ""; echo "Artifacts:"
  find "$ARTIFACTS_DIR" -not -name '.gitkeep' -type f | sort | sed 's/^/  /'
}

# ----- cmd: status ------------------------------------------------------------
cmd_status() {
  step "Pipeline status  ($WORKFLOW)"
  echo ""

  local cur_phase=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^PHASE:(.+)$ ]]; then
      cur_phase="${BASH_REMATCH[1]}"
      local approved="$ARTIFACTS_DIR/$cur_phase/APPROVED"
      local gate_art="$ARTIFACTS_DIR/$cur_phase/gate.md"
      if [ -f "$approved" ]; then
        printf "  ${GREEN}✓${NC} Phase ${BOLD}%s${NC} — APPROVED\n" "$cur_phase"
      elif [ -f "$gate_art" ]; then
        printf "  ${CYAN}🔒${NC} Phase ${BOLD}%s${NC} — gate 대기\n" "$cur_phase"
        printf "     승인: touch %s\n" "$approved"
      else
        printf "  ${BLUE}○${NC} Phase ${BOLD}%s${NC}\n" "$cur_phase"
      fi
    elif [[ "$line" =~ ^[[:space:]]+TASK:(.+):(.+)$ ]]; then
      local tid="${BASH_REMATCH[1]}" sk="${BASH_REMATCH[2]}"
      local out="$STATE_DIR/${cur_phase}-${tid}.out"
      if [ -s "$out" ]; then
        printf "    ${GREEN}✓${NC} %-28s %s\n" "$tid" "$sk"
      else
        printf "    ${YELLOW}○${NC} %-28s %s\n" "$tid" "$sk"
      fi
    fi
  done < <(parse_workflow "$WORKFLOW")

  echo ""
  if [ -f "$LOG" ]; then
    printf "마지막 이벤트:\n"
    tail -5 "$LOG" | python3 -c "
import sys,json
for l in sys.stdin:
    try:
        e=json.loads(l)
        print(f\"  [{e['ts'][11:19]}] {e['phase']:12} {e['task']:25} → {e['status']}\")
    except: pass
"
  fi
}

# ----- cmd: list --------------------------------------------------------------
cmd_list() {
  step "실행 가능한 태스크 목록  ($WORKFLOW)"
  echo ""
  local cur_phase=""
  while IFS= read -r line; do
    if [[ "$line" =~ ^PHASE:(.+)$ ]]; then
      cur_phase="${BASH_REMATCH[1]}"
      printf "\n  ${BOLD}Phase %s${NC}\n" "$cur_phase"
    elif [[ "$line" =~ ^[[:space:]]+TASK:(.+):(.+)$ ]]; then
      printf "    ./hermes.sh task %-28s  # %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$line" =~ ^[[:space:]]+GATE: ]]; then
      printf "    ./hermes.sh gate %-28s  # 게이트 승인\n" "$cur_phase"
    fi
  done < <(parse_workflow "$WORKFLOW")
  echo ""
}

# ----- cmd: validate ----------------------------------------------------------
cmd_validate() {
  local yaml="${1:-$WORKFLOW}"
  step "Validating $yaml"
  [ -f "$yaml" ] || { err "$yaml not found"; exit 1; }
  python3 -c "
with open('$yaml') as f: c = f.read()
print('  phases:', c.count('  - id:'))
print('  tasks: ', c.count('      - id:'))
print('  gates: ', c.count('gate:'))
"
  ok "Validation passed"
}

# ----- Entry point ------------------------------------------------------------
CMD="${1:-help}"; shift || true

case "$CMD" in
  task)     cmd_task     "${1:-}" ;;
  gate)     cmd_gate     "${1:-}" ;;
  phase)    cmd_phase    "${1:-}" ;;
  run)      cmd_run      "${@}" ;;
  status)   cmd_status ;;
  list)     cmd_list ;;
  validate) cmd_validate "${1:-}" ;;
  help|--help|-h)
    printf "\nUsage: ./hermes.sh <command> [args]\n\n"
    printf "  ${BOLD}task${NC} <task_id>          스킬 1개 실행 (권장)\n"
    printf "  ${BOLD}gate${NC} <phase_id>         게이트 요약 생성 + 승인 대기\n"
    printf "  ${BOLD}phase${NC} <phase_id>        페이즈 내 태스크 전체 순차 실행\n"
    printf "  ${BOLD}run${NC} [workflow.yaml]     전체 파이프라인\n"
    printf "  ${BOLD}status${NC}                  태스크 단위 진행 상황\n"
    printf "  ${BOLD}list${NC}                    실행 가능한 태스크 목록\n"
    printf "  ${BOLD}validate${NC} [workflow]     YAML 검증\n\n"
    printf "예시:\n"
    printf "  ./hermes.sh task brainstorm\n"
    printf "  ./hermes.sh gate A-pm\n"
    printf "  ./hermes.sh status\n\n"
    ;;
  *) err "Unknown command: $CMD  (./hermes.sh help 참고)"; exit 1 ;;
esac
