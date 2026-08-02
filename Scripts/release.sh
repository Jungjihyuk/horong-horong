#!/usr/bin/env bash
set -euo pipefail

# 릴리즈 한 방 스크립트.
#
# 사람이 정하는 값은 VERSION 하나뿐이고, 나머지(빌드 번호, 서명값, 크기, 날짜, 릴리즈 노트)는
# 전부 앞 단계 산출물에서 파생된다. 옮겨 적다 틀리는 실수를 없애는 것이 목적이다.
#
# 절차 문서: docs/5. 운영/프로젝트 운영/12. 기술 문서/Build/release-checklist-and-automation-design.md
#
# 사용법:
#   make release VERSION=0.2.3
#   make release-dry-run VERSION=0.2.3     # 빌드·패키징까지만. 커밋/태그/푸시/배포 없음
#
# 공증(notarization)은 Developer ID 인증서가 없어 아직 건너뛴다. 유료 멤버십과 인증서가
# 준비되면 SKIP_NOTARIZE 기본값을 0 으로 바꾸고 notarize() 를 채우면 된다.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

VERSION="${VERSION:-}"
DRY_RUN="${DRY_RUN:-0}"
# 1 이면 GitHub Release 를 초안으로 만들고 거기서 멈춘다. appcast 는 배포하지 않는다 —
# 초안의 에셋 URL 은 아직 열려 있지 않아서, 먼저 올리면 사용자가 404 를 받는다.
DRAFT="${DRAFT:-0}"
# 초안을 확인한 뒤 마무리(공개 + appcast + 백머지)만 실행하는 모드.
PUBLISH_ONLY="${PUBLISH_ONLY:-0}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/dist}"
APPCAST="docs/updates/appcast.xml"
CHANGELOG="CHANGELOG.md"
REPO_URL="https://github.com/Jungjihyuk/horong-horong"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf '\n\033[1;31m오류: %s\033[0m\n' "$*" >&2; exit 1; }

project_value() {
  awk -F'"' -v key="$1" '$0 ~ key ":" { print $2; exit }' project.yml
}

# ─────────────────────────────────────────────── 0. 사전 조건

preflight() {
  step "0. 사전 조건 확인"

  [[ -n "$VERSION" ]] || die "VERSION 이 필요합니다. 예: make release VERSION=0.2.3"
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "VERSION 형식이 올바르지 않습니다: $VERSION"

  local branch
  branch="$(git branch --show-current)"
  [[ "$branch" == "main" ]] || die "릴리즈는 main 에서만 합니다. 현재: $branch"

  [[ -z "$(git status --short)" ]] || {
    git status --short >&2
    die "커밋되지 않은 변경이 있습니다. README·스크린샷 갱신을 먼저 커밋하세요."
  }

  git fetch --quiet origin main dev
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
    || die "로컬 main 이 origin/main 과 다릅니다. 먼저 동기화하세요."

  # dev 가 main 보다 «뒤처진» 것은 정상이다 — dev→main PR 을 머지하면 그 머지 커밋만큼 항상 뒤처지고,
  # 마지막 백머지 단계가 정리한다. 막아야 하는 것은 반대로 dev 에만 있는 커밋이다.
  # 그런 게 남아 있으면 13단계의 `merge --ff-only` 가 실패해 백머지가 또 밀린다.
  local dev_ahead
  dev_ahead="$(git rev-list --count origin/main..origin/dev)"
  [[ "$dev_ahead" -eq 0 ]] || die "origin/dev 에 main 으로 안 넘어온 커밋이 $dev_ahead 개 있습니다.
    먼저 dev → main PR 을 머지하세요. 그대로 두면 릴리즈 후 백머지가 실패합니다."

  git rev-parse "v$VERSION" >/dev/null 2>&1 && die "태그 v$VERSION 이 이미 있습니다."

  local current
  current="$(project_value MARKETING_VERSION)"
  [[ "$current" != "$VERSION" ]] || die "project.yml 이 이미 $VERSION 입니다."
  info "현재 $current → 새 버전 $VERSION"

  # ad-hoc 서명으로 릴리즈가 나가는 것을 막는다.
  if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
    die "SIGN_IDENTITY 를 지정하세요. ad-hoc(-) 서명은 배포할 수 없습니다.
    사용 가능한 신원: $(security find-identity -v -p codesigning | sed -n 's/.*"\(.*\)".*/\1/p' | paste -sd '; ' -)"
  fi

  grep -q '^## \[Unreleased\]' "$CHANGELOG" || die "$CHANGELOG 에 [Unreleased] 섹션이 없습니다."
  local unreleased_body
  unreleased_body="$(changelog_block "Unreleased" | sed '1d' | tr -d '[:space:]')"
  [[ -n "$unreleased_body" ]] || die "$CHANGELOG 의 [Unreleased] 가 비어 있습니다. 변경 사항을 먼저 적으세요."

  command -v gh >/dev/null || die "gh CLI 가 필요합니다."
  command -v xmllint >/dev/null || die "xmllint 가 필요합니다."
  [[ -n "$(find_sign_update)" ]] || die "Sparkle sign_update 를 찾지 못했습니다. 한 번 빌드한 뒤 다시 실행하세요."

  info "사전 조건 통과"
}

find_sign_update() {
  # DerivedData/<프로젝트-해시>/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update
  find ~/Library/Developer/Xcode/DerivedData -maxdepth 8 \
    -path '*/artifacts/sparkle/Sparkle/bin/sign_update' -type f 2>/dev/null | head -1
}

# CHANGELOG 에서 `## [<이름>]` 부터 다음 `## [` 직전까지 잘라낸다.
changelog_block() {
  awk -v want="$1" '
    /^## \[/ {
      inside = ($0 ~ "^## \\[" want "\\]")
    }
    inside { print }
  ' "$CHANGELOG"
}

# ─────────────────────────────────────────────── 1~2. 버전 갱신

# 버전을 올린 뒤 어디서 죽든 원래대로 돌려놓는다.
# 실패한 자리에 버전 변경이 남으면 다음 실행이 «클린 트리» 검사에서 막힌다.
# 실제 릴리즈가 10단계까지 갔다면 이미 커밋된 상태라 이 복원은 아무 일도 하지 않는다.
restore_version() {
  git checkout --quiet -- project.yml HorongHorong.xcodeproj 2>/dev/null || true
}

bump_version() {
  step "1. 버전 갱신"

  trap restore_version EXIT

  local build
  build="$(( $(project_value CURRENT_PROJECT_VERSION) + 1 ))"

  sed -i '' "s/^\( *MARKETING_VERSION: \).*/\1\"$VERSION\"/" project.yml
  sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \).*/\1\"$build\"/" project.yml

  BUILD_NUMBER="$build"
  info "MARKETING_VERSION=$VERSION CURRENT_PROJECT_VERSION=$build"

  step "2. 프로젝트 재생성 (xcodegen)"
  make generate >/dev/null
  info "완료"
}

# ─────────────────────────────────────────────── 3. 빌드 + 패키징

build_and_package() {
  step "3. Release 빌드 · 서명 · 패키징"

  local extra=()
  [[ "$DRY_RUN" -eq 1 ]] && extra+=(--skip-clean-check)

  # macOS 기본 bash 는 3.2 라, `set -u` 에서 빈 배열을 `"${extra[@]}"` 로 펼치면
  # "unbound variable" 로 죽는다. 아래 형태는 배열이 비어 있으면 아무 인자도 만들지 않는다.
  SIGN_IDENTITY="$SIGN_IDENTITY" \
  VERSION="$VERSION" \
  BUILD_NUMBER="$BUILD_NUMBER" \
  OUTPUT_DIR="$OUTPUT_DIR" \
    Scripts/package-release.sh "${extra[@]+"${extra[@]}"}"

  ZIP_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.zip"
  DMG_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.dmg"
  [[ -f "$ZIP_PATH" ]] || die "zip 이 만들어지지 않았습니다: $ZIP_PATH"
}

# ─────────────────────────────────────────────── 4~7. 공증 (보류)

notarize() {
  if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
    step "4~7. 공증 건너뜀"
    info "Developer ID 인증서가 준비되면 SKIP_NOTARIZE=0 으로 켭니다."
    info "지금 배포되는 앱은 사용자가 첫 실행 시 Gatekeeper 경고를 봅니다."
    return
  fi

  die "공증은 아직 구현되지 않았습니다. 절차 문서 1.4 절을 참고해 채워 주세요."
}

# ─────────────────────────────────────────────── 8. 서명값 산출

compute_signature() {
  step "8. 서명값 산출"

  local sign_update
  sign_update="$(find_sign_update)"

  # sign_update 출력 예: sparkle:edSignature="..." length="..."
  local output
  output="$("$sign_update" "$ZIP_PATH")"
  ED_SIGNATURE="$(sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' <<<"$output")"
  LENGTH="$(stat -f%z "$ZIP_PATH")"
  PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

  [[ -n "$ED_SIGNATURE" ]] || die "edSignature 를 얻지 못했습니다: $output"
  info "length=$LENGTH"
  info "pubDate=$PUB_DATE"
}

# ─────────────────────────────────────────────── 9. CHANGELOG 확정

finalize_changelog() {
  step "9. CHANGELOG 확정"

  local today
  today="$(date '+%Y-%m-%d')"

  # [Unreleased] → [VERSION] - 날짜 로 바꾸고, 비어 있는 [Unreleased] 를 새로 연다.
  perl -0pi -e "s/## \\[Unreleased\\]\n/## [Unreleased]\n\n## [$VERSION] - $today\n/" "$CHANGELOG"

  # 링크 참조 갱신
  perl -0pi -e "s{\\[Unreleased\\]: .*\n}{[Unreleased]: $REPO_URL/compare/v$VERSION...HEAD\n[$VERSION]: $REPO_URL/releases/tag/v$VERSION\n}" "$CHANGELOG"

  info "[$VERSION] - $today 블록 확정"
}

# ─────────────────────────────────────────────── 10. 커밋 + 태그

commit_and_tag() {
  step "10. 커밋 · 태그 · push"

  git add project.yml HorongHorong.xcodeproj "$CHANGELOG"
  git commit --quiet -m "chore: Release v$VERSION"
  git tag "v$VERSION"
  git push --quiet origin main "v$VERSION"
  info "v$VERSION 태그 push 완료"
}

# ─────────────────────────────────────────────── 11. GitHub Release

publish_release() {
  step "11. GitHub Release 생성"

  local notes
  notes="$(mktemp)"
  changelog_block "$VERSION" | sed '1d' > "$notes"

  local draft=()
  [[ "$DRAFT" -eq 1 ]] && draft+=(--draft)

  gh release create "v$VERSION" "$ZIP_PATH" "$DMG_PATH" \
    --title "v$VERSION" \
    --notes-file "$notes" \
    "${draft[@]+"${draft[@]}"}"

  rm -f "$notes"
  info "$REPO_URL/releases/tag/v$VERSION"
}

# ─────────────────────────────────────────────── 12. appcast

update_appcast() {
  step "12. appcast 갱신"

  # 손으로 고치지 않고 통째로 생성한다. sed 로 기존 XML 을 손보다 태그가 깨진 적이 있다.
  cat > "$APPCAST" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>HorongHorong Updates</title>
    <link>https://jungjihyuk.github.io/horong-horong/updates/appcast.xml</link>
    <description>Update feed for direct distribution builds.</description>
    <item>
      <title>Version $VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <pubDate>$PUB_DATE</pubDate>
      <enclosure
        url="$REPO_URL/releases/download/v$VERSION/HorongHorong-$VERSION.zip"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

  xmllint --noout "$APPCAST" || die "생성한 appcast 가 유효하지 않습니다."

  git add "$APPCAST"
  git commit --quiet -m "chore: Update appcast for v$VERSION"
  git push --quiet origin main
  info "appcast 배포 완료"
}

# ─────────────────────────────────────────────── 13. 백머지

backmerge() {
  step "13. main → dev 백머지"

  git checkout --quiet dev
  git merge --quiet --ff-only main
  git push --quiet origin dev
  git checkout --quiet main
  info "dev 동기화 완료"
}

# ─────────────────────────────────────────────── 마무리 전용 모드

# DRAFT=1 로 만들어 둔 초안을 확인한 뒤 실행한다.
# 초안 공개 → appcast 배포 → 백머지 순서를 지킨다. 에셋이 공개된 뒤에야 appcast 를 올려야
# 사용자가 404 를 받지 않는다.
publish_finish() {
  step "마무리: 초안 공개 · appcast · 백머지"

  [[ -n "$VERSION" ]] || die "VERSION 이 필요합니다."
  [[ "$(git branch --show-current)" == "main" ]] || die "main 에서 실행하세요."
  [[ -z "$(git status --short)" ]] || die "커밋되지 않은 변경이 있습니다."
  git rev-parse "v$VERSION" >/dev/null 2>&1 || die "태그 v$VERSION 이 없습니다. 먼저 릴리즈를 만드세요."

  ZIP_PATH="$OUTPUT_DIR/HorongHorong-$VERSION.zip"
  [[ -f "$ZIP_PATH" ]] || die "zip 이 없습니다: $ZIP_PATH
    appcast 의 서명값은 배포한 그 파일에서 뽑아야 합니다. 릴리즈를 만든 산출물을 그대로 두세요."

  BUILD_NUMBER="$(project_value CURRENT_PROJECT_VERSION)"
  compute_signature

  step "초안 공개"
  gh release edit "v$VERSION" --draft=false
  info "$REPO_URL/releases/tag/v$VERSION"

  update_appcast
  backmerge

  step "릴리즈 v$VERSION 완료"
  info "이전 버전 앱에서 «업데이트 확인»이 새 버전을 잡는지 한 번 확인하세요."
}

# ─────────────────────────────────────────────── 실행

main() {
  if [[ "$PUBLISH_ONLY" -eq 1 ]]; then
    publish_finish
    return
  fi

  preflight
  bump_version
  build_and_package
  notarize
  compute_signature

  if [[ "$DRY_RUN" -eq 1 ]]; then
    step "DRY RUN 종료"
    info "여기까지 성공했습니다. 커밋·태그·배포는 하지 않았습니다."
    info "zip: $ZIP_PATH"
    info "edSignature: $ED_SIGNATURE"

    info "project.yml 과 xcodeproj 는 원래대로 되돌립니다."
    info "실제 릴리즈: make release VERSION=$VERSION SIGN_IDENTITY=\"$SIGN_IDENTITY\""
    return
  fi

  finalize_changelog
  commit_and_tag
  publish_release

  if [[ "$DRAFT" -eq 1 ]]; then
    step "초안까지 완료 — 여기서 멈춥니다"
    info "릴리즈 페이지를 열어 에셋과 노트를 확인하세요."
    info "$REPO_URL/releases/tag/v$VERSION"
    info ""
    info "appcast 는 아직 배포하지 않았습니다. 초안의 에셋 URL 이 열려 있지 않아,"
    info "먼저 올리면 사용자가 내려받다 404 를 받습니다."
    info ""
    info "확인이 끝나면: make release-publish VERSION=$VERSION"
    return
  fi

  update_appcast
  backmerge

  step "릴리즈 v$VERSION 완료"
  info "$REPO_URL/releases/tag/v$VERSION"
  info "이전 버전 앱에서 «업데이트 확인»이 새 버전을 잡는지 한 번 확인하세요."
}

main "$@"
