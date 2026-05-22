---
name: pr
description: PR 컨벤션에 맞는 제목과 본문을 커밋 히스토리와 변경사항 분석을 통해 자동 생성하고 gh CLI로 GitHub PR을 생성한다. base 브랜치는 dev이다.
---

## 동작 순서

### 1. 현재 브랜치 확인
`git branch --show-current` 로 현재 브랜치를 확인한다.

- `feature/`로 시작하지 않으면 **중단**한다:
  > ⚠️ feature 브랜치에서만 실행할 수 있습니다. (현재: `{branch}`)

### 2. 커밋 히스토리 분석
`git log dev..HEAD --oneline` 으로 현재 브랜치의 커밋 목록을 파악한다.

- 커밋이 없으면 **중단**한다:
  > ⚠️ dev 브랜치 대비 커밋이 없습니다. 기능을 구현하고 커밋한 후 실행하세요.

### 3. 변경사항 전체 파악
`git diff dev...HEAD` 로 전체 변경 파일 및 내용을 분석한다.

### 4. 이슈 번호 추출
현재 브랜치명에서 이슈 번호를 추출한다.

- 브랜치명 패턴: `feature/#12-branch-name` → `#12`
- 이슈 번호가 없으면 Issue Tag를 생략한다.

### 5. PR 제목 생성
커밋 히스토리와 변경사항을 분석하여 아래 형식으로 제목을 생성한다:

```
[TYPE] 한글 제목
```

- `TYPE`: 커밋의 주요 변경 성격에 따라 결정 (영어 대문자)

| TYPE | 기준 |
|------|------|
| `FEAT` | 새로운 기능 추가 |
| `FIX` | 버그 수정 |
| `DOCS` | 문서 작업 |
| `REFACTOR` | 코드 구조 개선 (로직 변경 없음) |
| `REMOVE` | 파일 또는 코드 제거 |
| `CHORE` | 빌드 설정, 패키지, 환경 설정 |
| `TEST` | 테스트 코드 |
| `ENHANCE` | 기존 기능 성능 개선 |

- `제목`: 한글로 작성, 마침표 없음, 간결하게

### 6. PR 본문 생성
변경사항을 분석하여 아래 구조로 본문을 작성한다:

```markdown
## Overview
업로드한 코드에 대한 전반적인 설명

## Change Log
- 추가/변경된 주요 사항을 항목별로 간략하게 설명

## To Reviewer
- 리뷰어가 특별히 확인해야 할 사항
- 설계 결정, 트레이드오프, 주의할 로직 등

## Issue Tag
Closes #이슈번호
```

### 7. PR 생성 확인 및 실행
생성할 PR 제목과 본문을 사용자에게 보여주고 확인을 받는다.

확인 후 실행:
```bash
gh pr create --base dev --title "[TYPE] 한글 제목" --body "$(cat <<'EOF'
## Overview
...

## Change Log
...

## To Reviewer
...

## Issue Tag
Closes #이슈번호
EOF
)"
```

- `gh` CLI가 설치되어 있지 않으면 안내한다:
  > ⚠️ `gh` CLI가 필요합니다. `brew install gh` 로 설치 후 `gh auth login` 으로 인증하세요.

- PR 생성 완료 후 PR URL을 출력한다.

---

## 출력 예시

```
📋 생성할 PR 내용:

제목: [FEAT] 아티클 CRUD API 구현

본문:
  ## Overview
  아티클 생성/조회/수정/삭제 REST API 엔드포인트를 구현했습니다.
  FastAPI 기반으로 작성되었으며 SQLModel ORM을 사용합니다.

  ## Change Log
  - POST /api/articles 엔드포인트 추가
  - GET /api/articles 페이지네이션 구현
  - PUT /api/articles/{id} 수정 엔드포인트 추가
  - DELETE /api/articles/{id} 소프트 딜리트 처리

  ## To Reviewer
  - 소프트 딜리트 방식을 적용했습니다. is_deleted 필터 로직을 확인해주세요.
  - 페이지네이션은 cursor 기반이 아닌 offset 방식입니다.

  ## Issue Tag
  Closes #2

base: dev ← feature/#2-article-crud

PR을 생성할까요?
```
