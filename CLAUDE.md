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

## Execution mode — when to use Hermes vs. direct execution

**Always decide this first before doing any work.**

| 상황 | 실행 모드 |
|------|----------|
| 목표가 모호하거나 기획부터 시작 ("새 기능 만들어줘") | **Hermes 풀 파이프라인** — Phase A→B→C→D |
| 설계 산출물은 있지만 구현이 필요 ("B 게이트 통과, 개발 시작") | **Hermes Phase C**부터 진입 |
| `artifacts/sprint/sprint-N-tasks.md` 파일이 존재하고 태스크가 명확히 정의됨 | **직접 실행 (Claude Code)** — Hermes 불필요 |
| 버그 수정 / 핫픽스 / 단일 파일 수정 | **직접 실행 (Claude Code)** |
| 분석·리뷰만 필요 (코드 작성 없음) | **직접 실행 (Claude Code)** |

### 스프린트 태스크 판단 기준

`artifacts/sprint/sprint-N-tasks.md`가 있을 때 다음을 확인하라:

1. 태스크마다 **파일 경로**와 **구체적 변경 내용**이 명시되어 있는가? → 직접 실행
2. "무엇을 만들지"가 아직 결정 안 된 태스크가 있는가? → 해당 태스크는 Phase A부터

> **원칙**: 스프린트는 이미 A→B 단계를 거친 결과물이다.
> 다시 파이프라인을 태우는 것은 낭비다. 바로 실행하라.

---

## 스프린트 준비 프로토콜 ← 필수

**"다음 스프린트 준비해줘"** 요청이 오면 반드시 아래 4개 관점을 **모두** 포함해 분석 문서를 작성하라.
하나라도 빠지면 불완전한 스프린트 준비다.

### 필수 4관점

| 관점 | 담당 스킬 | 핵심 질문 |
|------|----------|----------|
| 🎯 **기획(PM)** | `brainstorming`, `using-superpowers` | 지표 위험은? 다음 성장 레버는? |
| 📣 **마케팅** | `marketing-psychology` | 전환/리텐션에 쓸 심리 원칙은? 어떤 카피/프레이밍이 효과적? |
| 🎨 **디자인** | `frontend-design` | 시각적 완성도 갭은? 컴포넌트·패턴 일관성 문제는? |
| 🧭 **UX** | `ux-researcher-designer` | 사용자 흐름 단절 지점은? 다음 액션 명확성은? |

### 산출물 형식

```
artifacts/sprint/sprint-N-analysis.md   ← 4관점 분석 + 우선순위 매트릭스
artifacts/sprint/sprint-N-tasks.md      ← 태스크별 파일 경로 + 구체적 변경 내용
```

각 태스크에는 반드시 다음을 명시:
- 어느 관점(PM/마케팅/디자인/UX)에서 요청된 것인지
- 대상 파일 경로 (신규 파일이면 `(신규)` 표기)
- 구체적 UI/로직 변경 내용 (의사코드 또는 JSX 스케치 수준)

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
