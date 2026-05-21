# Project Orchestration Context

This project uses a **Hermes (orchestrator) + Claude Code (harness/worker)** stack
with 11 specialist skills sourced from [aitmpl.com](https://www.aitmpl.com/),
plus 1 external skill (`marketing-psychology` — coreyhaines31/marketingskills).

Hermes owns the workflow DAG and quality gates. Claude Code executes the actual
file edits, code generation, and tool calls. Skills are the role definitions that
get loaded per phase.

---

## Phase map

| Phase | Skills | Output |
|-------|--------|--------|
| **A · PM / Direction** | `senior-prompt-engineer`, `brainstorming`, `using-superpowers`, `marketing-psychology` | PRD, problem statement, requirements, conversion strategy |
| **B · Design** | `frontend-design`, `ux-researcher-designer` | Wireframes, design tokens, user flows |
| **C · Development** | `senior-architect`, `senior-frontend`, `senior-backend`, `code-reviewer` | Implementation, PR-ready code |
| **D · OPS** | `senior-qa`, `senior-devops`, `senior-security` | Tests, CI/CD, security audit, ship |

Between every phase there is a **gate** — work does not advance until the gate
artifact is checked in. See `docs/orchestration.md` for the full gate spec.

---

## Skill routing rules (for Claude Code)

When Claude Code is invoked **directly** (without Hermes orchestrating), pick the
skill by the verb in the user request:

- "psychology / mental models / why people buy / conversion / persuasion / pricing / loss aversion / social proof / anchoring / scarcity" → `marketing-psychology`
- "brainstorm / explore / what should we build" → `brainstorming`
- "write the prompt / improve the system prompt" → `senior-prompt-engineer`
- "design / mock / wireframe / UI" → `frontend-design` (visual) or `ux-researcher-designer` (research)
- "architect / system design / how should we structure" → `senior-architect`
- "implement frontend / React / Vue / component" → `senior-frontend`
- "implement backend / API / database / service" → `senior-backend`
- "review this PR / lint / code quality" → `code-reviewer`
- "test / QA / coverage" → `senior-qa`
- "deploy / CI / pipeline / infra" → `senior-devops`
- "audit / vulnerability / threat model" → `senior-security`

When in doubt, run **`/kickoff`** to enter the full DAG from Phase A.

---

## Hermes invocation

The Hermes orchestrator reads `hermes/workflows/*.yaml`. The default workflow is
`full-stack.yaml`. Trigger a run with:

```bash
hermes run hermes/workflows/full-stack.yaml --goal "<one-line goal>"
```

Hermes will call Claude Code in print mode (`claude -p ...`) for each phase,
passing the corresponding skill name and the artifacts from the previous phase.

---

## Iteration & budget guardrails

- Per-phase `--max-turns`: 30 (override in workflow yaml if needed)
- Per-run total iteration budget: 90 (Hermes default)
- Per-run USD budget: $5.00 — gate fires a `clarify_callback` if exceeded
- Per-tool permission: see `.claude/settings.json`

---

## Local conventions

- All generated code lives under `src/`; all generated docs under `docs/`
- All artifacts produced by phases land in `artifacts/<phase>/`
- Hermes Kanban board state is `.hermes-state/` (gitignored)
- Never commit anything from `.hermes-state/` or `artifacts/draft/`

---

## When this CLAUDE.md is wrong

If the project's actual structure diverges from what's documented here, fix this
file first, then continue. The orchestrator trusts this file.
