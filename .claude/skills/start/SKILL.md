---
name: start
description: 새로운 기능 브랜치 작업을 시작한다. 원격 dv 브랜치를 동기화한 뒤 이슈 번호 기반의 feature 브랜치를 생성하고 이동한다.
---

## 동작 순서

### 1. 현재 브랜치 확인
`git branch --show-current` 로 현재 브랜치를 확인한다.

- 현재 브랜치가 `dv`가 아니어도 계속 진행한다. (어느 브랜치에서든 실행 가능)

### 2. dv 동기화
원격의 최신 `dv` 코드를 로컬에 반영한다.

```bash
git checkout dv
git pull origin dv
```

- `git pull` 실패 시 중단하고 오류 내용을 출력한다.

### 3. 브랜치명 입력받기
사용자에게 아래 정보를 입력받는다:

- **이슈 번호** (숫자만): `#N` 형태로 사용
- **브랜치 설명** (영어 소문자, 하이픈 사용): 간결하게

입력받은 값으로 브랜치명을 조합한다:
```
feature/#N-branch-description
```

예시:
- 이슈 번호: `3`, 설명: `semantic-search` → `feature/#3-semantic-search`

### 4. feature 브랜치 생성 및 이동
```bash
git checkout -b feature/#N-branch-description
```

- 생성 완료 후 현재 브랜치를 확인하여 사용자에게 안내한다.

---

## 출력 예시

```
✅ dv 동기화 완료

브랜치명: feature/#3-semantic-search
으로 생성하고 이동했습니다.

이제 기능을 구현하고, 커밋할 때는 commit 스킬을 사용하세요.
```
