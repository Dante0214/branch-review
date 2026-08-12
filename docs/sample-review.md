# 실제 적용 결과 — pulse-frontend

`branch-review`를 팀 프로젝트 [HANCOM-E/pulse-frontend](https://github.com/HANCOM-E/pulse-frontend)의 작업 브랜치에 그대로 돌린 결과다. 아래 리포트는 사람이 다듬지 않은 도구의 실제 출력이다.

```
$ cd pulse-frontend
$ /branch-review:review
```

| | |
|---|---|
| 대상 | `feature/30-live-result-page` → `origin/dev` |
| 기준 문서 | `CLAUDE.md` (전용 규칙 파일 없음 → 폴백) |
| 리뷰 제외 근거 | `.prettierrc`, `eslint.config.mjs`, `.githooks/commit-msg` |
| 규모 | 파일 6개 · +405 −6 · 커밋 12개 |

---

## 1. 변경점 요약

`feature/30-live-result-page` → `origin/dev` · 파일 6개 · +405 −6 · 커밋 12개

- 참가자용 실시간 결과 화면 신규 구현 (`components/live/LiveResult.tsx`)
- 집계 폴링을 훅으로 격리 (`hooks/useFeedbackSnapshot.ts`) — 5초 주기, SSE 전환 대비
- 로딩 스켈레톤 추가 (`components/live/LiveSkeleton.tsx`)
- 참가자 공개 화면 공통 헤더를 레이아웃에 추가 (`app/e/[code]/layout.tsx`)
- 소감을 남긴 세션만 열람하도록 제한, 제출 직후 안내 배너용 `?submitted=1` 플래그 추가

## 2. 컨벤션 위반 (1건)

### [권장] 공개 페이지인데 초기 HTML에 콘텐츠가 실리지 않음 — `app/e/[code]/live/page.tsx:32-49`

> 근거: CLAUDE.md 확정된 기술 스택 — "공개 페이지는 SSR/SSG, 대시보드는 CSR"

`page.tsx`는 서버 컴포넌트지만 화면 내용 전체가 `LiveResult` 클라이언트 아일랜드 안에 있습니다. `LiveResult`가 `useSearchParams`를 쓰기 때문에 프리렌더가 가장 가까운 Suspense 경계까지 클라이언트 렌더로 떨어지고, 그 결과 참가자가 받는 첫 HTML에는 `LiveSkeleton`만 담깁니다. 이벤트명·세션 제목처럼 서버에서 이미 알 수 있는 값도 함께 빠집니다.

코드 주석이 이 동작을 정확히 인지하고 있고("초기 HTML에는 스켈레톤만 실립니다"), 배너를 제목 위에 두기 위한 의도적 선택이라고 밝히고 있습니다. 그래서 이 지적은 "고쳐라"가 아니라 **문서와 코드 중 어느 쪽을 맞출지 정하자**는 쪽입니다.

- 코드를 맞춘다면 — 이벤트명·세션 제목을 `page.tsx`에서 서버로 받아 `LiveResult`에 props로 내리고, 클라이언트 아일랜드는 집계 영역으로 좁힙니다.
- 문서를 맞춘다면 — CLAUDE.md에 "실시간 집계 화면은 예외"를 한 줄 넣습니다. 다음 사람이 같은 판단을 반복하지 않습니다.

`?sessionId=` 검증을 서버 `redirect`로 처리한 부분은 원칙에 맞습니다.

## 3. 개선 제안 (3건)

### [제안] heading 단계를 건너뛰어 스크린리더 목차가 끊김 — `components/live/LiveResult.tsx:188,197`

`h1` 다음이 바로 `h3`입니다. 페이지 어디에도 `h2`가 없습니다.

```
h1  세션 제목                 (177행)
h3  지금 청중 반응 · 소감 N개   (188행)   ← h2 건너뜀
h3  많이 나온 말               (197행)
```

스크린리더 사용자는 heading 목록으로 페이지를 훑는데, 단계가 끊기면 상위 항목이 누락된 것으로 읽힙니다. axe의 `heading-order` 규칙이 잡는 항목입니다.

커밋 `3b4a2d0`의 본문에 "h1에서 h3까지 heading order를 정리했다"고 적혀 있어, 정리 과정에서 의도가 반쯤 반영된 것으로 보입니다.

`h3`의 시각적 크기는 `text-xs`로 이미 클래스가 정하고 있으므로, 태그만 바꾸면 화면은 그대로입니다.

```tsx
// components/live/LiveResult.tsx:188
<h2 className="text-xs text-text-tertiary">
  지금 청중 반응 · 소감 {submissionCount}개
  {unclassifiedCount > 0 && ` (미분류 ${unclassifiedCount}개)`}
</h2>

// components/live/LiveResult.tsx:197
<h2 className="text-xs text-text-tertiary">많이 나온 말</h2>
```

### [제안] `?submitted=1`이 URL에 남아 재방문에도 등록 안내가 뜸 — `components/live/LiveResult.tsx:85`

```ts
const justSubmitted = searchParams.get('submitted') === '1';
```

이 값을 URL에서 떼는 코드가 없습니다(레포 전체에 `router.replace` 사용처가 없음). 그래서 배너를 한 번 본 뒤 새로고침하거나, 그 상태로 링크를 저장했다가 다음 날 다시 열면 "소감이 등록되었어요"가 또 뜹니다.

같은 파일 82-84행 주석이 제출 기록 대신 쿼리 플래그를 쓴 이유를 이렇게 적고 있습니다.

> 며칠 뒤 같은 링크를 다시 열었을 때도 안내가 뜨면 방금 낸 것처럼 읽힙니다.

플래그를 URL에 남겨두면 피하려던 상황이 그대로 재현됩니다. 배너를 그린 직후 쿼리만 떼어내면 됩니다.

```tsx
useEffect(() => {
  if (!justSubmitted) return;
  const next = new URLSearchParams(searchParams);
  next.delete('submitted');
  // 뒤로 가기 히스토리를 늘리지 않도록 replace를 씁니다.
  router.replace(`?${next.toString()}`, { scroll: false });
}, [justSubmitted, router, searchParams]);
```

### [제안] 로딩 상태가 스크린리더에 전달되지 않음 — `components/live/LiveSkeleton.tsx:11`

스켈레톤 전체에 `aria-hidden`이 걸려 있습니다. 회색 블록을 읽히지 않게 한 것은 맞지만, 대신 로딩 중이라는 사실을 알릴 수단이 남지 않았습니다. 스크린리더 사용자에게는 첫 스냅샷이 도착할 때까지 빈 화면입니다.

```tsx
<div className="flex animate-pulse flex-col gap-6" role="status" aria-live="polite">
  <span className="sr-only">실시간 결과를 불러오는 중</span>
  <div aria-hidden>
    {/* 기존 회색 블록들 */}
  </div>
</div>
```

## 4. 총평

머지 가능 여부: **가능**

`[필수]` 0건입니다. 컨벤션 위반 1건은 문서와 코드 중 어느 쪽을 맞출지 정하는 문제이고, 나머지는 접근성 개선 제안입니다.

폴링을 `useFeedbackSnapshot`으로 격리하면서 `refetchInterval`을 밖으로 내보내지 않고 `refreshIntervalMs` 하나만 노출한 설계가 좋습니다. CLAUDE.md가 예고한 SSE 전환 시점에 이 파일 내부만 바꾸면 화면은 손대지 않아도 됩니다. 훅 주석에 그 의도가 적혀 있어 다음 사람이 실수로 옵션을 꺼낼 여지도 막았습니다.

집계 전 상태(`isSnapshotPending`)와 집계 결과 0건을 스켈레톤으로 구분한 처리, 목록에 없는 `sessionId`를 걸러 "0개 소감 · 긍정 0%"라는 그럴듯한 빈 화면을 막은 처리도 실제 사고를 예방하는 자리입니다.

heading 두 줄은 태그만 바꾸면 되므로 이번에 같이 넣는 편이 낫습니다.

---

## 이 결과에서 확인한 것

**컨벤션 위반과 일반 제안을 나눈 효과.** 2번의 SSR 항목은 CLAUDE.md에 근거가 있어 "문서와 코드 중 하나를 고치자"는 결론까지 갈 수 있었다. 3번의 접근성 항목들은 근거가 일반 통념이라 작성자가 그냥 넘겨도 된다. 두 지적의 무게가 다르다는 것이 리포트 구조만으로 전달된다.

**도구가 잡는 항목이 리포트에서 빠졌다.** 커밋 12개는 모두 Conventional Commits 형식이지만, 이 형식은 `.githooks/commit-msg`가 애초에 강제하므로 리뷰가 언급하지 않았다. Prettier가 관리하는 따옴표·세미콜론·줄바꿈도 마찬가지다. 지적할 수 있었지만 지적하지 않은 항목이 리포트를 짧게 유지했다.

**억지 지적이 없다.** 1차 위반이 1건뿐이라는 결과를 그대로 냈다. 405줄 추가에 지적 4건이면 적은 편이지만, 이 브랜치는 실제로 컨벤션을 잘 지켰다. 건수를 채우려 했다면 리포트 전체의 신뢰가 깎였을 것이다.

**주석과 코드의 불일치를 잡았다.** `?submitted=1` 건은 주석에 적힌 의도와 구현이 어긋난 경우다. 코드만 보면 정상이고 주석만 보면 정상인데, 둘을 겹쳐 읽어야 드러난다. heading 건도 커밋 메시지의 "정리했다"는 주장과 실제 태그가 어긋난 경우다.
