---
description: Run the final ship sequence — security audit, QA, deploy
allowed-tools: Bash(hermes:*), Bash(git:*), Bash(npm:test), Bash(npm:run:*), Read(*), Write(*)
---

# /ship — Final release

Run only after Phase D gate is approved.

## Sequence

1. **Re-run security audit** — `hermes run hermes/workflows/phase-D.yaml --only senior-security`
2. **Run full QA suite** — `npm test && npm run e2e`
3. **Verify CI green** — `gh run list --limit 1 --json conclusion` should return `success`
4. **Tag the release** — derive version from `package.json`, run `git tag v$VERSION`
5. **Trigger deploy** — `hermes run hermes/workflows/deploy.yaml --env production`
6. **Post-deploy smoke** — call the health endpoint, verify 200

## Abort conditions

Stop immediately if any of these are true:
- Security audit finds **any** critical-severity issue
- Test coverage drops below 70%
- Staging smoke test fails
- The user has not approved the Phase D gate

When aborting, write `artifacts/D-ops/ship-aborted.md` with the reason.
