---
description: 단발성 업무 요청 — 스킬 1개, 승인 없이 즉시 실행
allowed-tools: Read(*), Write(*), Edit(*), Bash(git:*), Bash(npm:*), Bash(python:*), Bash(pytest:*)
---

# /task — 단발 태스크 실행

요청: **$ARGUMENTS**

## 스킬 자동 선택

요청 문장에서 동사와 대상을 파악해 아래 표에서 스킬을 선택한다.

| 요청 패턴 | 스킬 |
|-----------|------|
| 버그 수정, API 수정, DB 쿼리 | `senior-backend` |
| 컴포넌트, 화면, CSS, 반응형 | `senior-frontend` |
| 구조 설계, 의존성 정리 | `senior-architect` |
| PR 리뷰, 코드 품질 | `code-reviewer` |
| 테스트, E2E, 커버리지 | `senior-qa` |
| 배포, CI, Dockerfile | `senior-devops` |
| 보안 점검, 취약점 | `senior-security` |
| 기획서, 요구사항 정리 | `senior-prompt-engineer` |
| 아이디어 탐색, 브레인스토밍 | `brainstorming` |
| UX 분석, 사용자 흐름 | `ux-researcher-designer` |
| UI 디자인, 디자인 시스템 | `frontend-design` |

## 실행

선택된 스킬로 Claude Code를 print 모드로 호출한다:
```bash
claude -p "<요청 내용>" \
  --allowedTools "Read,Write,Edit,Bash" \
  --max-turns 20 \
  --skill "<선택된 스킬 경로>"
```

## 완료 기준

- 코드 변경 → `git diff`로 변경 요약 출력
- 문서 작성 → 파일 경로와 분량 출력
- 오류 발생 → 오류 내용과 다음 단계 제안

승인 없이 완료하고, 작업 내용을 `.hermes-state/activity.log`에 한 줄로 기록한다.
