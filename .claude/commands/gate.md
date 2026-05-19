---
description: Review a phase gate artifact and approve or send back for revision
allowed-tools: Read(*), Edit(artifacts/*)
---

# /gate — Phase gate review

Argument: **$ARGUMENTS** (the phase letter: `A`, `B`, `C`, or `D`)

## Checklist

Read `artifacts/$ARGUMENTS/gate.md` and verify against the phase's exit criteria:

### Phase A exit criteria (PM)
- [ ] Problem statement is one paragraph, jargon-free
- [ ] At least 3 success metrics are measurable
- [ ] Non-goals are explicitly listed
- [ ] Target users are named with a primary persona

### Phase B exit criteria (Design)
- [ ] Every user flow from PRD has a wireframe
- [ ] Design tokens (color, type, spacing) are committed to `design/tokens.json`
- [ ] Accessibility contrast checks pass for all primary surfaces

### Phase C exit criteria (Development)
- [ ] All PR-level code passes `code-reviewer` skill
- [ ] No TODO comments in main branch code
- [ ] Test coverage ≥ 70% for new modules
- [ ] Build runs cleanly from a fresh checkout

### Phase D exit criteria (OPS)
- [ ] `senior-security` audit report has zero critical findings
- [ ] CI pipeline runs end-to-end without manual steps
- [ ] Smoke test deploys to staging successfully
- [ ] Rollback procedure is documented

## Output

Reply with one of:

- ✅ **Approve** — write `artifacts/$ARGUMENTS/APPROVED` (empty file) so Hermes
  can advance the DAG.
- ⏪ **Revise** — list the specific failing items and call `/phase $ARGUMENTS`
  again with the revision notes appended to the input.
- 🛑 **Abort** — stop the run and write a postmortem to `docs/postmortems/`.
