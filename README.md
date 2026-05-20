# Hermes + Claude Code Orchestration Template

A drop-in project template: 4-phase pipeline (PM → Design → Dev → OPS) with
11 specialist skills, quality gates, and a `hermes.sh` orchestrator — ready in
under a minute.

> 실전 검증 완료 — 티켓 중고거래 플랫폼 전체 파이프라인에서 디버깅된 버전입니다.

## Quick start (any machine)

```bash
npx degit NAMJIHOON/hermes-orchestration-template my-project
cd my-project
chmod +x hermes.sh scripts/bootstrap.sh
./scripts/bootstrap.sh --skills-only

# 목표 작성
echo "내 프로젝트 목표" > artifacts/A-pm/goal.md

# 태스크 목록 확인
./hermes.sh list
```

## 권장 실행 방식 — Task 단위

전체 파이프라인을 한 번에 돌리면 시간이 너무 걸립니다.
**태스크 1개씩 실행하고 결과를 확인하는 방식을 권장합니다.**

```bash
# Phase A — PM
./hermes.sh task brainstorm          # ~3분
./hermes.sh task prompt-spec         # ~3분
./hermes.sh task leverage-superpowers
./hermes.sh gate A-pm                # gate.md 확인 후 승인 대기
# → 새 터미널: touch artifacts/A-pm/APPROVED

# Phase B — Design
./hermes.sh task ux-research
./hermes.sh task frontend-design
./hermes.sh gate B-design
# → touch artifacts/B-design/APPROVED

# Phase C — Dev
./hermes.sh task architect
./hermes.sh task backend             # ~10분 (max-turns 80)
./hermes.sh task frontend            # ~10분 (max-turns 80)
./hermes.sh task review
./hermes.sh gate C-dev
# → touch artifacts/C-dev/APPROVED

# Phase D — OPS
./hermes.sh task qa
./hermes.sh task security
./hermes.sh task devops
./hermes.sh gate D-ops
# → touch artifacts/D-ops/APPROVED
```

## 커맨드 참조

```bash
./hermes.sh list                     # 실행 가능한 전체 태스크 목록
./hermes.sh task <task_id>           # 스킬 1개 실행
./hermes.sh gate <phase_id>          # 게이트 요약 생성 + 승인 대기
./hermes.sh phase <phase_id>         # 페이즈 내 태스크 전체 순차 실행
./hermes.sh status                   # 태스크 단위 진행 상황
./hermes.sh run hermes/workflows/full-stack.yaml  # 전체 파이프라인 (자동)
./hermes.sh validate                 # YAML 검증
./scripts/bootstrap.sh --check       # 설치 상태 확인
```

## 파이프라인 구조

```
Phase A (PM)      brainstorm → prompt-spec → leverage-superpowers
      ↓ gate (artifacts/A-pm/gate.md)
Phase B (Design)  ux-research → frontend-design
      ↓ gate (artifacts/B-design/gate.md)
Phase C (Dev)     architect → backend → frontend → review
      ↓ gate (artifacts/C-dev/gate.md)
Phase D (OPS)     qa → security → devops
      ↓ gate (artifacts/D-ops/gate.md)
```

## 게이트 승인 방법

각 페이즈 완료 후 `gate.md`를 검토하고 승인합니다:

```bash
cat artifacts/A-pm/gate.md          # 내용 검토
touch artifacts/A-pm/APPROVED       # 승인 → 다음 페이즈 자동 진행
```

게이트는 **타임아웃 없음** — 충분히 검토 후 승인하세요.

## What you get

| Layer | 역할 |
|-------|------|
| `hermes.sh` | Task/Phase/Gate 단위 실행, 이벤트 로깅, 재시작 지원 |
| `.claude/settings.json` | 권한·훅·MCP 설정 |
| `hermes/workflows/*.yaml` | 전체/스프린트/페이즈별 워크플로우 DAG |
| 11 aitmpl 스킬 | PM·Design·Dev·OPS 전문가 역할 |

## 산출물 구조

```
artifacts/
├── A-pm/      # goal.md, brainstorm.md, prd.md, gate.md, APPROVED
├── B-design/  # user-journey-maps.md, wireframes.md, tokens.json, gate.md, APPROVED
├── C-dev/     # architecture.md, backend.md, frontend.md, review.md, gate.md, APPROVED
└── D-ops/     # qa.md, security-audit.md, devops.md, rollback-runbook.md, gate.md, APPROVED
src/           # 실제 생성 코드 (backend/, client/)
```

## 태스크 재실행

완료된 태스크는 자동 스킵됩니다. 재실행하려면:

```bash
rm .hermes-state/<phase>-<task>.out
./hermes.sh task <task_id>
```

## max-turns 기본값

| 스킬 유형 | max-turns |
|-----------|-----------|
| backend, frontend, architect | 80 |
| qa, security, devops, reviewer | 50 |
| 나머지 | 30 |

## 필요 도구

| 도구 | 설치 |
|------|------|
| Node.js ≥ 18 | https://nodejs.org |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| python3 | 대부분 기본 설치 |
| git | 대부분 기본 설치 |

## License

MIT
