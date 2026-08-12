#!/usr/bin/env bash
# branch-review collector — 현재 브랜치의 변경분과 리뷰 기준 파일 위치를 모아 평문으로 찍는다.
# 판단은 하지 않는다. 사실만 수집하고, 아무것도 쓰지 않는다.

IFS=$'\n\t'

BASE=""
MAX_LINES=1500
NO_EXCLUDE=0
FILES_ONLY=0
STAGED_ONLY=0
USER_PATHS=()

usage() {
  cat <<'EOF'
사용법: collect.sh [옵션] [-- <경로>...]

  --base <ref>     비교 기준 브랜치를 직접 지정 (기본: origin/dev → origin/main → … 순서로 자동 탐지)
  --max-lines <n>  diff 출력 상한 (기본 1500). 초과분은 파일명만 나열
  --files-only     diff 없이 변경 파일 목록만
  --staged         워킹트리 대신 스테이징된 변경만 대상으로
  --no-exclude     lock 파일·빌드 산출물 기본 제외를 끔
  -- <경로>...     대상 경로 제한 (예: -- src app)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --base)      BASE="$2"; shift 2 ;;
    --max-lines) MAX_LINES="$2"; shift 2 ;;
    --files-only) FILES_ONLY=1; shift ;;
    --staged)    STAGED_ONLY=1; shift ;;
    --no-exclude) NO_EXCLUDE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    --)          shift; USER_PATHS=("$@"); break ;;
    *) echo "알 수 없는 인자: $1" >&2; usage >&2; exit 2 ;;
  esac
done

TOP=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$TOP" ]; then
  echo "!! git 레포가 아닙니다. 리뷰할 레포 안에서 실행해야 합니다."
  exit 1
fi
cd "$TOP" || exit 1

TMP=$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/branch-review.$$")
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT

CURRENT=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

# 기본 제외: 리뷰해봤자 소음인 것들. 사람이 손으로 쓰지 않는 파일이 기준이다.
EXCLUDES=()
if [ "$NO_EXCLUDE" = "0" ]; then
  EXCLUDES=(
    ':(exclude)package-lock.json'
    ':(exclude)yarn.lock'
    ':(exclude)pnpm-lock.yaml'
    ':(exclude)*.lock'
    ':(exclude)*.min.js'
    ':(exclude)*.min.css'
    ':(exclude)*.map'
    ':(exclude)dist/**'
    ':(exclude)build/**'
    ':(exclude).next/**'
    ':(exclude)gradle/wrapper/**'
    ':(exclude)*.png' ':(exclude)*.jpg' ':(exclude)*.jpeg'
    ':(exclude)*.gif' ':(exclude)*.ico' ':(exclude)*.woff' ':(exclude)*.woff2'
  )
fi
PATHSPEC=("${USER_PATHS[@]}" "${EXCLUDES[@]}")

# --- 비교 기준 결정 ---------------------------------------------------------
# 현재 브랜치 자기 자신은 기준이 될 수 없다. dev에서 작업 중이면 기준이 없고,
# 그 경우 커밋되지 않은 변경만 리뷰 대상이 된다 (그리고 그 사실 자체가 컨벤션 신호다).
BASE_NOTE=""
if [ -z "$BASE" ]; then
  for cand in origin/dev origin/develop origin/main origin/master dev develop main master; do
    short=${cand#origin/}
    [ "$short" = "$CURRENT" ] && continue
    if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
      BASE="$cand"; break
    fi
  done
  BASE_NOTE="(자동 탐지)"
else
  BASE_NOTE="(--base 지정)"
fi

ON_BASE_BRANCH=0
case "$CURRENT" in
  main|master|dev|develop) ON_BASE_BRANCH=1 ;;
esac

if [ -n "$BASE" ]; then
  MERGE_BASE=$(git merge-base "$BASE" HEAD 2>/dev/null)
fi

if [ "$STAGED_ONLY" = "1" ]; then
  DIFF_ARGS=(--cached)
  SCOPE="스테이징된 변경만 (--staged)"
elif [ -n "$MERGE_BASE" ]; then
  # merge-base부터 워킹트리까지 — 커밋된 것과 아직 커밋 안 한 것을 모두 포함한다.
  DIFF_ARGS=("$MERGE_BASE")
  SCOPE="$BASE 분기점 이후 (커밋 + 미커밋)"
else
  DIFF_ARGS=(HEAD)
  SCOPE="HEAD 대비 미커밋 변경"
fi

echo "== TARGET =="
echo "repo:    $(basename "$TOP")"
echo "branch:  $CURRENT"
if [ -n "$BASE" ]; then
  echo "base:    $BASE $BASE_NOTE"
  echo "분기점:  ${MERGE_BASE:0:12}"
else
  echo "base:    (없음 — 비교 대상 브랜치를 찾지 못했습니다)"
fi
echo "범위:    $SCOPE"
if [ "$ON_BASE_BRANCH" = "1" ]; then
  echo "!! 현재 통합 브랜치($CURRENT)에서 직접 작업 중입니다."
fi
echo

# --- 리뷰 기준 파일 위치 ----------------------------------------------------
# 우선순위: 전용 규칙 파일 > 프로젝트 AI 가이드 > 도구 설정.
# 스크립트는 존재 여부만 알린다. 실제 내용은 스킬이 읽는다.
echo "== CONVENTION SOURCES =="
found_primary=0
check() {
  if [ -f "$1" ]; then
    printf "  %-12s %s\n" "$2" "$1"
    [ "$2" = "[전용규칙]" ] && found_primary=1
  fi
}
check ".claude/review-rules.md" "[전용규칙]"
check ".claude/conventions.md"  "[전용규칙]"
check "CLAUDE.md"               "[폴백]"
check ".claude/CLAUDE.md"       "[폴백]"
check "AGENTS.md"               "[폴백]"
check "CONTRIBUTING.md"         "[폴백]"
check ".github/PULL_REQUEST_TEMPLATE.md" "[폴백]"
check ".editorconfig"           "[도구설정]"
check ".prettierrc"             "[도구설정]"
check ".prettierrc.json"        "[도구설정]"
check "eslint.config.mjs"       "[도구설정]"
check "eslint.config.js"        "[도구설정]"
check ".eslintrc.json"          "[도구설정]"
check "build.gradle"            "[도구설정]"
check "build.gradle.kts"        "[도구설정]"
check "pom.xml"                 "[도구설정]"
check ".githooks/commit-msg"    "[도구설정]"
if [ "$found_primary" = "0" ]; then
  echo "  (전용 규칙 파일 없음 — 폴백 문서에서 규칙을 추출해야 합니다)"
fi
echo

# --- 커밋 ------------------------------------------------------------------
# 커밋 메시지도 컨벤션 검사 대상이다. 본문까지 봐야 Conventional Commits 준수를 판정할 수 있다.
echo "== COMMITS =="
if [ -n "$MERGE_BASE" ]; then
  n=$(git rev-list --no-merges --count "$MERGE_BASE..HEAD" 2>/dev/null)
  if [ "${n:-0}" = "0" ]; then
    echo "  (분기점 이후 커밋 없음)"
  else
    git log --no-merges --reverse --format='  %h %s%n%w(100,6,6)%b' "$MERGE_BASE..HEAD" 2>/dev/null
  fi
else
  echo "  (비교 기준이 없어 생략)"
fi
echo

# --- 변경 파일 --------------------------------------------------------------
git diff --name-status "${DIFF_ARGS[@]}" -- "${PATHSPEC[@]}" > "$TMP/namestatus.txt" 2>/dev/null
git diff --numstat     "${DIFF_ARGS[@]}" -- "${PATHSPEC[@]}" > "$TMP/numstat.txt" 2>/dev/null

echo "== CHANGED FILES =="
if [ ! -s "$TMP/namestatus.txt" ]; then
  echo "  (변경 없음)"
else
  awk -F'\t' '
    NR==FNR {
      p = $3; if (NF > 3) p = $4
      add[p] = $1; del[p] = $2; next
    }
    {
      st = $1; p = $2; if (NF > 2) p = $3
      a = (p in add) ? add[p] : "?"
      d = (p in del) ? del[p] : "?"
      printf "  %-4s %-58s +%s -%s\n", st, p, a, d
    }
  ' "$TMP/numstat.txt" "$TMP/namestatus.txt"
  echo
  git diff --shortstat "${DIFF_ARGS[@]}" -- "${PATHSPEC[@]}" 2>/dev/null | sed 's/^ */  합계: /'
fi
echo

untracked=$(git -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null)
if [ -n "$untracked" ]; then
  echo "== UNTRACKED =="
  echo "$untracked" | head -30 | sed 's/^/  /'
  un=$(echo "$untracked" | wc -l | tr -d ' ')
  [ "$un" -gt 30 ] && echo "  ... 외 $((un - 30))개"
  echo "  (git에 추가되지 않은 파일입니다. 새 소스 파일이 여기 있으면 add 누락일 수 있습니다.)"
  echo
fi

[ "$FILES_ONLY" = "1" ] && exit 0

# --- diff ------------------------------------------------------------------
# 파일 단위로 붙이다가 상한을 넘으면 나머지는 이름만 남긴다.
# 잘린 diff로 리뷰하면 없는 문제를 지어내게 되므로, 잘렸다는 사실을 반드시 알린다.
echo "== DIFF =="
if [ ! -s "$TMP/namestatus.txt" ]; then
  echo "  (변경 없음)"
  exit 0
fi

total=0
skipped=""
while IFS=$'\t' read -r st p extra; do
  [ -n "$extra" ] && p="$extra"
  [ -z "$p" ] && continue
  d=$(git -c core.quotepath=false diff "${DIFF_ARGS[@]}" -- "$p" 2>/dev/null)
  [ -z "$d" ] && continue
  n=$(printf '%s\n' "$d" | wc -l | tr -d ' ')
  if [ $((total + n)) -gt "$MAX_LINES" ]; then
    skipped="${skipped}    $p (${n}줄)"$'\n'
    continue
  fi
  printf '%s\n' "$d"
  total=$((total + n))
done < "$TMP/namestatus.txt"

if [ -n "$skipped" ]; then
  echo
  echo "-- 상한(${MAX_LINES}줄) 초과로 생략된 파일 --"
  printf '%s' "$skipped"
  echo "  이 파일들은 직접 열어서 읽어야 합니다. 생략된 내용을 추측해서 리뷰하면 안 됩니다."
  echo "  전체를 보려면: --max-lines <더 큰 수>, 또는 -- <경로>로 범위를 좁혀 다시 실행하십시오."
fi
