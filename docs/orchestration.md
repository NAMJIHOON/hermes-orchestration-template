# Orchestration architecture

A drop-in template that combines **Hermes Agent** (orchestrator) and
**Claude Code** (harness/worker) with 11 specialist skills from
[aitmpl.com](https://www.aitmpl.com/).

## Three-layer model

```
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 1 · Hermes Agent (orchestrator)                              │
│  - reads workflows/*.yaml                                           │
│  - owns the DAG, gates, iteration budget, Kanban board              │
│  - delegates each task to Claude Code via `claude -p`               │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 2 · Claude Code (harness / worker)                           │
│  - executes one skill per invocation                                │
│  - enforces tool permissions from .claude/settings.json             │
│  - runs hooks (linters, blockers, logging)                          │
│  - reads CLAUDE.md for project context                              │
└────────────────────────────────┬────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│  Layer 3 · aitmpl Skills (the 11 specialists)                       │
│                                                                     │
│  Phase A · PM       Phase B · Design   Phase C · Dev   Phase D · OPS│
│  ───────────────    ────────────────   ──────────────  ─────────── │
│  brainstorming      ux-researcher       senior-architect   senior-qa │
│  senior-prompt-eng  frontend-design     senior-frontend    devops    │
│  using-superpowers                      senior-backend     security  │
│                                         code-reviewer                │
└─────────────────────────────────────────────────────────────────────┘
```

## Why three layers

| Concern | Layer | File |
|---|---|---|
| "What's the next step?" | Hermes | `hermes/workflows/*.yaml` |
| "Which tools may run?" | Claude Code | `.claude/settings.json` |
| "How does this role think?" | aitmpl skill | `.claude/skills/<skill>/SKILL.md` |
| "What's the project about?" | Project context | `CLAUDE.md` |

Keeping these separated means you can:
- Swap Hermes for a different orchestrator (LangGraph, Inngest, plain make)
  without touching the skills
- Swap Claude Code for Codex CLI or another harness without touching workflows
- Add/remove/upgrade skills without touching workflows (just edit `agents.yaml`)
- Reuse the whole stack on any new project by running `bootstrap.sh`

## Quality gates

Every phase ends in a gate. The gate is a checkpoint where:
1. Hermes writes a summary to `artifacts/<phase>/gate.md`
2. The DAG halts until `artifacts/<phase>/APPROVED` exists
3. The user (or you, via `/gate <phase>`) decides to approve, revise, or abort

Auto-fail conditions (skip the user, just halt):
- Phase D security audit lists any critical finding
- Phase C test coverage drops below 70%
- Any phase exceeds the per-phase USD budget

## Iteration budget

The full DAG runs under a single shared `IterationBudget` (Hermes feature) so
that a runaway Phase A can't starve Phase D. Defaults:

- 90 total LLM turns
- $5 total USD
- 30 turns and $1.50 per phase

Override per-run with `--max-budget-usd` and `--max-iterations`.

## File map

```
project-root/
├── CLAUDE.md                          # Claude Code reads this first every session
├── package.json                       # npm script wrappers
├── .claude/
│   ├── settings.json                  # permissions, hooks, MCP servers
│   ├── commands/
│   │   ├── kickoff.md                 # /kickoff — start the full DAG
│   │   ├── phase.md                   # /phase A|B|C|D — run one phase
│   │   ├── gate.md                    # /gate A|B|C|D — review and approve
│   │   └── ship.md                    # /ship — final release
│   └── skills/                        # populated by bootstrap.sh
│       ├── senior-prompt-engineer/
│       ├── brainstorming/
│       └── ... (9 more)
├── hermes/
│   ├── agents.yaml                    # skill ↔ subagent role mapping
│   └── workflows/
│       ├── full-stack.yaml            # master DAG
│       ├── phase-A.yaml               # standalone phase runners
│       ├── phase-B.yaml
│       ├── phase-C.yaml
│       └── phase-D.yaml
├── scripts/
│   └── bootstrap.sh                   # one-line installer
├── artifacts/                         # phase outputs land here
│   ├── A-pm/
│   ├── B-design/
│   ├── C-dev/
│   └── D-ops/
├── .hermes-state/                     # runtime state (gitignored)
│   ├── kanban.json
│   ├── events.jsonl
│   ├── cost.jsonl
│   └── activity.log
└── docs/
    └── orchestration.md               # you are here
```

## Daily operations

### Start a new project
```bash
cp -R orchestration-template my-new-project
cd my-new-project
./scripts/bootstrap.sh
echo "Build a customer-support triage tool" > artifacts/A-pm/goal.md
hermes run hermes/workflows/full-stack.yaml
```

### Re-run a single phase
```bash
npm run phase:B          # re-run design after PRD changes
```

### Approve a gate without opening Claude
```bash
touch artifacts/A-pm/APPROVED
hermes resume                            # advance past Phase A's gate
```

### Inspect the Kanban
```bash
npm run kanban
```

### Cost check
```bash
jq -s 'map(.usd) | add' .hermes-state/cost.jsonl
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `claude: command not found` | Claude Code not installed | https://docs.claude.com/claude-code |
| `hermes: command not found` | Hermes not installed | `pip install hermes-agent` |
| Skill install fails | Network or npm cache | Re-run `./scripts/bootstrap.sh` (idempotent) |
| Phase advances without approval | Stale `APPROVED` file | `find artifacts -name APPROVED -delete` |
| Hooks not firing | settings.json schema | `claude config validate` |
| Hermes hangs at a gate | Waiting for `APPROVED` file | Run `/gate <phase>` or `touch APPROVED` |

## Extending

### Add a new skill
1. Find its path on aitmpl.com (e.g. `data/data-scientist`)
2. Add it to the `SKILLS` array in `scripts/bootstrap.sh`
3. Add an entry to `hermes/agents.yaml`
4. Reference it in the relevant phase task in `full-stack.yaml`
5. Re-run `./scripts/bootstrap.sh`

### Swap workers
To use Codex CLI instead of Claude Code for one phase, change the task's
`worker` field:
```yaml
- id: backend
  worker: codex
  worker_mode: pty
  skill: development/senior-backend
```

### Add a new gate condition
Edit the `gate.generator` field in `full-stack.yaml`. Hermes treats any
generator output containing the literal string `BLOCK:` as an auto-rejection.
