---
description: Run a single phase of the orchestration workflow
allowed-tools: Bash(hermes:*), Read(*), Write(artifacts/*)
---

# /phase — Run one phase

Argument: **$ARGUMENTS** (one of: `A`, `B`, `C`, `D`, or a specific skill name)

## Mapping

| Arg | Phase | Skills invoked in order |
|-----|-------|-------------------------|
| `A` | PM / Direction | brainstorming → senior-prompt-engineer → using-superpowers |
| `B` | Design | ux-researcher-designer → frontend-design |
| `C` | Development | senior-architect → senior-backend ∥ senior-frontend → code-reviewer |
| `D` | OPS | senior-qa → senior-security → senior-devops |

`∥` = parallel execution.

If the argument is a specific skill name (e.g. `senior-architect`), invoke that
skill directly without going through the phase chain.

## Behavior

1. Read the most recent gate artifact from the previous phase.
2. Pass it as input to this phase via:

   ```bash
   hermes run hermes/workflows/phase-$ARGUMENTS.yaml \
     --input artifacts/$(prev_phase)/gate.md \
     --output-dir artifacts/$ARGUMENTS/
   ```

3. On completion, write a gate summary to `artifacts/$ARGUMENTS/gate.md` and
   present it to the user for approval.
