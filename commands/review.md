---
description: 현재 브랜치의 변경 파일을 팀 컨벤션 기준으로 리뷰
argument-hint: "[--base origin/dev] [--staged] [--files-only] [-- <경로>...]"
---

`review` 스킬을 따라 현재 브랜치를 리뷰합니다.

스킬 본문(`skills/review/SKILL.md`)이 대화에 아직 안 보인다면 — 예를 들어 Skill 툴이 "이미 로드됨"이라고만 답하고 실제 내용을 안 준 경우 — 아래 경로로 직접 찾아 Read 툴로 엽니다. 위치는 결정적이므로 `find /`나 워크스페이스 전역 검색으로 헤매지 않습니다.

```bash
SKILL="${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md"
[ -f "$SKILL" ] || SKILL=$(ls -1d "$HOME"/.claude/plugins/cache/*/branch-review/*/skills/review/SKILL.md 2>/dev/null | tail -1)
[ -f "$SKILL" ] || { echo "!! 스킬 파일을 찾지 못했습니다. /plugin 으로 재설치가 필요합니다."; exit 1; }
echo "$SKILL"
```

수집 스크립트에 그대로 넘길 인자: $ARGUMENTS

인자가 없고 현재 디렉토리가 git 레포가 아니면, 리뷰할 레포 경로를 사용자에게 물어봅니다.

리포트는 스킬이 정한 네 부분 구조(변경점 요약 / 컨벤션 위반 / 개선 제안 / 총평)를 그대로 지킵니다. 파일은 수정하지 않습니다.
