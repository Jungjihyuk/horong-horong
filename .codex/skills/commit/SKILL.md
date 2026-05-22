---
name: commit
description: Git 커밋 컨벤션에 맞춰 staged 변경사항을 분석하고 적절한 타입과 메시지를 자동 생성하여 커밋을 수행한다.
---

## 동작 순서

### 1. 브랜치 확인
현재 브랜치를 확인한다. (`git branch --show-current`)

- 브랜치가 `main` 또는 `dv`이면 **경고 메시지를 출력하고 중단**한다:
  > ⚠️ 현재 브랜치가 `{branch}`입니다. `main`과 `dv`에서는 직접 커밋하지 않습니다.
  > feature 브랜치를 생성한 후 작업하세요. (`git checkout -b feature/#이슈번호-branch-name`)

### 2. Staged 변경사항 확인
`git diff --staged` 로 staged 변경사항을 분석한다.

- staged된 파일이 없으면 안내 후 중단한다:
  > ℹ️ staged된 변경사항이 없습니다. `git add {files}` 로 파일을 추가하세요.

### 3. 커밋 타입 자동 판별
변경 내용을 분석하여 아래 기준으로 `type`을 결정한다:

| type | 기준 |
|------|------|
| `feat` | 새로운 기능 파일 추가, 새 함수/클래스/API 엔드포인트 추가 |
| `fix` | 버그 수정, 에러 처리, 잘못된 로직 수정 |
| `docs` | README, 문서 파일(.md), 주석만 변경 |
| `refactor` | 로직 변경 없이 코드 구조/네이밍 변경 |
| `remove` | 파일 또는 코드 제거 |
| `chore` | 빌드 설정, 패키지 매니저, 환경 설정 파일 변경 |
| `test` | 테스트 코드 추가 또는 수정 |
| `enhance` | 기존 기능 성능 개선, 최적화 |

### 4. 커밋 헤더 메시지 생성
변경 내용을 요약한 영어 헤더를 작성한다:
- 영어로 작성
- 대문자로 시작
- 마침표 없음
- 간결하게 (동사 원형으로 시작 권장: Add, Fix, Update, Remove, Refactor 등)

### 5. 이슈 번호 추출
현재 브랜치명에서 이슈 번호를 추출한다.

- 브랜치명 패턴: `feature/#12-branch-name` → `#12`
- 이슈 번호가 없으면 footer를 생략한다.

### 6. 커밋 메시지 조합 및 커밋 실행
아래 형식으로 커밋 메시지를 구성한다:

```
type: Header message

#이슈번호
```

커밋 명령어 (HEREDOC 사용):
```bash
git commit -m "$(cat <<'EOF'
type: Header message

#이슈번호
EOF
)"
```

커밋 전 사용자에게 구성된 메시지를 보여주고 확인을 받은 후 실행한다.

---

## 커밋 메시지 예시

```
feat: Add JWT authentication endpoint

#3
```

```
fix: Resolve null pointer exception on article deletion

#7
```

```
refactor: Extract embedding logic into separate service module

#5
```
