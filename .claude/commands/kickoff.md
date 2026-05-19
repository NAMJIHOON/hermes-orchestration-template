---
description: Kick off the full Hermes workflow from Phase A (PM / Direction)
allowed-tools: Bash(hermes:*), Read(*), Write(artifacts/*)
---

# /kickoff — Start the full pipeline

You are the entry point for a new project run. Do the following in order:

1. Read the user's goal from the rest of this message: **$ARGUMENTS**
2. Confirm scope back to the user in 2-3 sentences. Ask **only if** the goal is
   ambiguous; otherwise proceed.
3. Create `artifacts/A-pm/goal.md` containing the goal verbatim plus the
   confirmed scope.
4. Invoke the Hermes orchestrator:

   ```bash
   hermes run hermes/workflows/full-stack.yaml --goal-file artifacts/A-pm/goal.md
   ```

5. Stream Hermes' Kanban updates back to the user as they happen.
6. At each phase gate, summarize the gate artifact and wait for explicit user
   approval before letting Hermes advance.

## Gate approval format

When a phase completes, present:

- ✅ **Phase X complete.** [one-line summary of what was produced]
- 📄 **Gate artifact:** `artifacts/<phase>/<file>`
- ❓ **Approve and advance to Phase Y?** (yes / revise / abort)

Wait for the user's literal response before continuing.
