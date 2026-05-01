---
name: finish
description: 기능 구현 완료 후 원격 dv 브랜치를 동기화하고 merge한 뒤 feature 브랜치를 push한다. 충돌 발생 시 안내 후 중단한다.
---

## 동작 순서

### 1. 현재 브랜치 확인
`git branch --show-current` 로 현재 브랜치를 확인한다.

- `feature/`로 시작하지 않으면 **중단**한다:
  > ⚠️ feature 브랜치에서만 실행할 수 있습니다. (현재: `{branch}`)

### 2. uncommitted 변경사항 확인
`git status --short` 로 커밋되지 않은 변경사항이 있는지 확인한다.

- 미커밋 변경사항이 있으면 **중단**한다:
  > ⚠️ 커밋되지 않은 변경사항이 있습니다. `commit` 스킬로 먼저 커밋하세요.

### 3. 원격 dv 동기화
```bash
git checkout dv
git pull origin dv
```

- `git pull` 실패 시 중단하고 오류 내용을 출력한다.

### 4. feature 브랜치로 복귀 후 dv merge
```bash
git checkout {feature-branch}
git merge dv
```

- **충돌이 발생한 경우** (`git merge`가 0이 아닌 종료 코드 반환, 또는 `git status`에 `UU`/`AA`/`DD` 표시):
  > ⚠️ 충돌이 발생했습니다. 아래 파일을 직접 해결하세요:
  > - {충돌 파일 목록}
  >
  > 해결 후 `git add .` 하고 `finish` 스킬을 다시 실행하세요.

  **여기서 중단한다. 사람이 직접 충돌을 해결해야 한다.**

- **충돌이 없는 경우** (fast-forward 또는 충돌 없는 merge): 다음 단계로 진행한다.

### 5. 충돌 해결 재진입 감지
`git status`로 merge 진행 중인지 확인한다. (`MERGE_HEAD` 파일 존재 여부)

- merge가 아직 완료되지 않았으면 (충돌 해결 후 재실행한 경우):
  - `git status`로 아직 unresolved 파일이 남아있으면 **중단** 후 안내한다.
  - 모두 resolved이면 `git commit` 으로 merge commit을 완료한다.

### 6. push 확인 및 실행
사용자에게 push할 브랜치를 보여주고 확인을 받는다.

```
feature/#N-branch-name → origin/feature/#N-branch-name
```

확인 후 실행:
```bash
git push origin {feature-branch}
```

완료 후 PR 생성을 안내한다:
> ✅ push 완료! PR을 생성하려면 `pr` 스킬을 실행하세요.

---

## 출력 예시 (충돌 없는 경우)

```
✅ dv 동기화 완료 (fast-forward)
✅ dv → feature/#3-semantic-search merge 완료

push 대상: feature/#3-semantic-search → origin
진행할까요?
```

## 출력 예시 (충돌 발생)

```
✅ dv 동기화 완료
⚠️ 충돌이 발생했습니다. 아래 파일을 직접 해결하세요:

  - backend/app/api/search.py
  - frontend/src/pages/SearchPage.jsx

해결 후 git add . 하고 finish 스킬을 다시 실행하세요.
```
