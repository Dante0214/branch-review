---
name: review
description: Review the changed files on the current branch against the team's own conventions, then against general best practice. Reads the team rules from .claude/review-rules.md, or falls back to CLAUDE.md / AGENTS.md / lint configs. Reports in a fixed four-part structure — 변경점 요약, 컨벤션 위반, 개선 제안, 총평. Triggers on "코드 리뷰", "브랜치 리뷰", "리뷰해줘", "PR 올리기 전에 확인", "컨벤션 지켰는지 확인", "review my branch", "check conventions", "리뷰 부탁".
---

# Branch Review

현재 브랜치의 변경분을 **두 층으로** 나눠 본다.

1. **1차 — 컨벤션 위반**: 팀이 문서로 합의한 규칙을 어겼는가. 근거는 항상 팀 문서의 한 줄이다.
2. **2차 — 개선 제안**: 돌아가긴 하지만 더 나은 방법이 있는가. 근거는 일반 통념이다.

이 둘을 섞지 않는 것이 이 스킬의 핵심이다. 1차는 "고쳐야 한다", 2차는 "고려해 봐라"다. 근거의 무게가 다르므로 절대 같은 칸에 넣지 않는다.

## 절차

### 1. 수집

```bash
COLLECT="${CLAUDE_PLUGIN_ROOT}/skills/review/scripts/collect.sh"
[ -f "$COLLECT" ] || COLLECT=$(command -v branch-review-collect)
[ -f "$COLLECT" ] || COLLECT=$(ls -1d "$HOME"/.claude/plugins/cache/*/branch-review/*/skills/review/scripts/collect.sh 2>/dev/null | tail -1)
[ -f "$COLLECT" ] || { echo "!! 수집 스크립트를 찾지 못했습니다. /plugin 으로 재설치가 필요합니다."; exit 1; }

bash "$COLLECT"
```

`CLAUDE_PLUGIN_ROOT`가 비어 있는 환경이 있다. 그래서 폴백이 세 단계다 — 환경변수, PATH에 등록된 `branch-review-collect` 런처, 플러그인 캐시 경로 순. 위 블록을 통째로 실행하면 셋 중 하나가 걸린다. 플래그는 마지막 줄에 붙인다 (`bash "$COLLECT" --staged`).

| 플래그 | 의미 |
|---|---|
| `--base <ref>` | 비교 기준 브랜치 지정. 기본은 `origin/dev` → `origin/main` 순 자동 탐지 |
| `--max-lines <n>` | diff 출력 상한. 기본 1500 |
| `--files-only` | 변경 파일 목록만 (규모부터 가늠할 때) |
| `--staged` | 스테이징된 변경만 (커밋 직전 점검) |
| `--no-exclude` | lock 파일·빌드 산출물 기본 제외를 해제 |
| `-- <경로>...` | 대상 경로 제한 (예: `-- src/main/java`) |

돌아오는 섹션은 `TARGET`, `CONVENTION SOURCES`, `COMMITS`, `CHANGED FILES`, `UNTRACKED`, `DIFF`.

diff가 상한에 걸려 잘렸다면 **생략된 파일을 Read로 직접 읽는다**. 잘린 자리를 추측으로 메우면 없는 결함을 지어내게 된다. 읽지 않았으면 리뷰하지 않는다.

### 2. 기준 확보

`CONVENTION SOURCES`에 나온 파일을 읽는다. 우선순위가 곧 권위의 순서다.

- `[전용규칙]` — 이 도구를 위해 팀이 직접 쓴 규칙. 있으면 이것이 최우선이다.
- `[폴백]` — `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`. 전용 규칙이 없을 때 여기서 **검사 가능한 항목만** 추려낸다.
- `[도구설정]` — `.prettierrc`, `.editorconfig`, ESLint, Spotless 설정.

`[도구설정]`은 **무엇을 지적하지 말아야 하는지**를 알려주는 용도다. 세미콜론·따옴표·들여쓰기·import 정렬처럼 포매터가 저장할 때 자동으로 고치는 항목은 리뷰에서 빼야 한다. 사람이 고칠 수 없는 걸 지적하면 리뷰 전체의 신뢰가 떨어진다.

기준 파일이 하나도 없으면 멈추고 사용자에게 알린다. 그리고 `templates/review-rules.md`를 복사해 채우도록 제안한다. 기준 없는 리뷰는 취향 표명일 뿐이다.

폴백 문서에서 규칙을 뽑을 때는 **판정 가능한 문장만** 가져온다. "가독성 좋게 작성한다"는 규칙이 아니다. "`any` 금지, 불가피하면 `unknown` + 좁히기"는 규칙이다.

자세한 판정 기준은 `references/criteria.md`를 읽는다.

### 3. 판정

변경 파일의 확장자로 스택을 보고 해당 체크리스트를 읽는다.

| 대상 | 파일 |
|---|---|
| 공통 | `references/checklist-common.md` |
| `.ts` `.tsx` `.js` `.jsx` | `references/checklist-frontend.md` |
| `.java` `.gradle` | `references/checklist-backend.md` |

1차는 팀 문서에 근거가 **있는 것만** 넣는다. 근거 문장을 인용할 수 없으면 그건 1차가 아니라 2차다.

2차는 체크리스트를 훑되, **해당하는 것만** 쓴다. 체크리스트를 처음부터 끝까지 채우려 들면 리뷰가 아니라 설문지가 된다.

각 지적은 세 가지를 반드시 갖춘다. 하나라도 못 채우면 그 지적은 버린다.

- **위치** — `파일:라인`
- **근거** — 1차는 규칙 원문 인용, 2차는 무엇이 어떻게 잘못될 수 있는지
- **개선안** — 그대로 붙여넣을 수 있는 코드

### 4. 보고

아래 네 부분을 **항상 이 순서로** 낸다. 해당 없는 부분도 생략하지 말고 "없음"이라고 적는다. 구조가 고정되어야 리뷰끼리 비교가 된다.

````markdown
## 1. 변경점 요약

`feature/30-live-result-page` → `origin/dev` · 파일 7개 · +212 −38 · 커밋 4개

- 실시간 결과 페이지 신규 추가 (`app/live/[id]/page.tsx`)
- 집계 폴링 훅 분리 (`hooks/useLiveResult.ts`)
- 감정 온도계 컴포넌트 추가 (`components/SentimentGauge.tsx`)

## 2. 컨벤션 위반 (2건)

### [필수] `any` 사용 — `hooks/useLiveResult.ts:24`

> 근거: CLAUDE.md 코드 규칙 — "`any`는 금지하며, 불가피하면 `unknown` + 좁히기를 사용해야 합니다."

```ts
// 현재
const parse = (raw: any) => raw.items;

// 개선안
const parse = (raw: unknown): LiveItem[] => {
  if (!isLiveResponse(raw)) throw new Error('예상과 다른 응답 형태');
  return raw.items;
};
```

### [권장] 커밋 메시지 body 누락 — `a1b2c3d`

> 근거: CLAUDE.md Git 규칙 — "body: 무엇을 왜 바꿨는지, 그리고 세션 중 겪은 애로사항·트러블슈팅을 기재해야 합니다."

`feat(live): 결과 페이지 추가` 한 줄뿐입니다. 폴링 간격을 5초로 정한 이유를 body에 남기면 다음 사람이 SSE 전환할 때 근거를 찾습니다.

## 3. 개선 제안 (1건)

### [제안] 폴링 정리 누락으로 인한 요청 누수 — `hooks/useLiveResult.ts:31-40`

컨벤션에 걸리는 건 아니지만, 언마운트 후에도 `setInterval`이 남습니다. 페이지를 빠르게 오가면 타이머가 중첩되어 요청이 배로 늘어납니다.

```ts
useEffect(() => {
  const id = setInterval(fetchResult, 5000);
  return () => clearInterval(id);   // 추가
}, [fetchResult]);
```

## 4. 총평

머지 가능 여부: **수정 후 가능**

`any` 하나만 처리하면 컨벤션상 막을 이유는 없습니다. 훅으로 폴링을 격리한 구조는 CLAUDE.md가 예고한 SSE 전환과 잘 맞습니다. 타이머 정리는 지금 같이 넣는 편이 낫습니다.
````

**심각도 표기**

| 표기 | 뜻 | 판단 기준 |
|---|---|---|
| `[필수]` | 머지 전에 반드시 고친다 | 컨벤션에 "금지"·"반드시"로 적혀 있거나, 동작이 깨진다 |
| `[권장]` | 고치는 편이 맞다 | 컨벤션 위반이지만 동작에는 지장 없음 |
| `[제안]` | 판단은 작성자 몫 | 컨벤션 밖의 개선 아이디어 |

**총평의 머지 가능 여부**는 세 가지 중 하나다.

- **가능** — `[필수]` 0건
- **수정 후 가능** — `[필수]` 있으나 국소적
- **재작업 필요** — 설계를 되돌려야 하거나 `[필수]`가 여러 파일에 퍼져 있음

### 5. 이후 제안

먼저 하지 말고 물어본다.

- 지적 사항 자동 수정 (`[필수]`만 / 전부)
- PR 본문 초안 작성
- 특정 항목을 팀 규칙으로 승격 — 2차에서 반복해 걸리는 항목은 `.claude/review-rules.md`에 넣을 후보다

## 규칙

- **수집 스크립트를 찾아 헤매지 않는다.** 위 세 경로가 전부다. 셋 다 실패하면 플러그인 설치가 깨진 것이므로 `/plugin`으로 재설치하라고 알리고 멈춘다. 워크스페이스 전역 glob이나 `find /`로 뒤지는 것은 금지한다 — 리뷰 대상 레포 안에 플러그인 파일이 있을 리 없고, 시간만 버린다.
- **읽지 않은 코드는 리뷰하지 않는다.** diff가 잘렸으면 파일을 열거나, 못 봤다고 밝힌다.
- **근거 없는 지적은 버린다.** 팀 문서 인용도 못 하고 실패 시나리오도 못 대면 그건 취향이다.
- **포매터·린터가 잡는 건 지적하지 않는다.** Prettier/ESLint/Spotless가 강제하는 항목은 이미 해결된 문제다.
- **컨벤션이 침묵하는 곳에서 규칙을 지어내지 않는다.** 문서에 없으면 2차로 내리거나, 규칙 신설을 제안한다.
- **잘 된 것도 한 줄 쓴다.** 총평에서. 지적만 나열된 리뷰는 다음번에 안 돌린다.
- **파일을 수정하지 않는다.** 사용자가 명시적으로 요청할 때만 고친다.
- **검증 명령을 임의로 돌리지 않는다.** `lint`/`test`/`build` 등은 `collect.sh`가 주는 diff·커밋 로그만으로 판정이 끝나지 않을 때조차, 사용자가 명시적으로 요청하지 않는 한 실행하지 않는다.
- **지적 건수를 채우려 하지 않는다.** 깨끗하면 "위반 없음"이 정답이다. 억지로 만든 지적 하나가 진짜 지적 열 개의 신뢰를 깎는다.
- 사용자 언어에 맞춘다.
