# Hermes + Claude Code Orchestration Template

A drop-in project template: 4-phase pipeline (PM → Design → Dev → OPS) with
11 specialist skills, quality gates, and a `hermes.sh` orchestrator — ready in
under a minute.

## Quick start (any machine)

```bash
npx degit YOUR_GITHUB_USERNAME/hermes-orchestration-template my-project
cd my-project
chmod +x hermes.sh scripts/bootstrap.sh
./scripts/bootstrap.sh --skills-only
echo "내 프로젝트 목표를 여기에 작성" > artifacts/A-pm/goal.md
./hermes.sh run hermes/workflows/full-stack.yaml
```

> `YOUR_GITHUB_USERNAME`을 실제 GitHub 유저명으로 교체하세요.

## What you get

| Layer | 역할 |
|-------|------|
| `hermes.sh` | DAG 실행, 게이트 대기, 이벤트 로깅 |
| `.claude/settings.json` | 권한·훅·MCP 설정 |
| `hermes/workflows/*.yaml` | 전체/스프린트/페이즈별 워크플로우 |
| 11 aitmpl 스킬 | PM·Design·Dev·OPS 전문가 역할 |

## 파이프라인 구조

```
Phase A (PM)      brainstorming → senior-prompt-engineer → using-superpowers
      ↓ gate
Phase B (Design)  ux-researcher → frontend-design
      ↓ gate
Phase C (Dev)     senior-architect → [backend ‖ frontend] → code-reviewer
      ↓ gate
Phase D (OPS)     senior-qa → senior-security → senior-devops
      ↓ gate
```

## 업무 요청 3단계

| 레벨 | 커맨드 | 스킬 수 | 승인 |
|------|--------|---------|------|
| Task (단발) | `/task` | 1개 | 불필요 |
| Sprint (묶음) | `./hermes.sh run hermes/workflows/sprint.yaml` | 2~4개 | 1회 |
| Project (전체) | `./hermes.sh run hermes/workflows/full-stack.yaml` | 전체 | 페이즈마다 |

## 게이트 승인

각 페이즈 완료 후 `artifacts/<phase>/gate.md`를 검토하고:

```bash
touch artifacts/A-pm/APPROVED   # Phase A 승인 → Phase B 자동 시작
```

## 필요 도구

| 도구 | 설치 |
|------|------|
| Node.js ≥ 18 | https://nodejs.org |
| Claude Code CLI | `npm install -g @anthropic-ai/claude-code` |
| git | 대부분 기본 설치 |

## 커맨드 참조

```bash
./hermes.sh run hermes/workflows/full-stack.yaml   # 전체 파이프라인
./hermes.sh run hermes/workflows/sprint.yaml       # 스프린트
./hermes.sh validate hermes/workflows/full-stack.yaml  # YAML 검증
./hermes.sh status                                  # 페이즈 진행 상황
./scripts/bootstrap.sh --check                      # 설치 상태 확인
```

## License

MIT
