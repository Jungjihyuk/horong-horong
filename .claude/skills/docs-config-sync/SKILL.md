---
name: docs-config-sync
description: 프로젝트의 `.claude/docs-file.json`을 템플릿(`docs/0. 템플릿/docs-file-template.json`) 기반으로 만들거나 갱신한다. 두 모드 — (init) 새 프로젝트에서 docs-file.json이 없을 때 템플릿을 복사하고 사용자의 실제 코드 경로로 code_mappings를 채워 만든다. (update) docs-file.json이 이미 있을 때 템플릿과 비교해 새 섹션 / 키 변경 / 구조 변경을 감지하고 동기화한다. project_type(desktop / mobile / web) 무관.
---

`docs-file.json`은 모든 빌더 스킬(`1-plan-*` ~ `5-operate-*`, `ralph-docs`)이 단일 출처로 참조하는 라우팅 설정이다. 이 스킬은 그 설정을 **템플릿 기반으로 생성·동기화**한다.

## 두 모드

스킬 호출 시 `.claude/docs-file.json` 존재 여부로 모드 자동 판정:
- 파일 없음 → **init 모드**
- 파일 있음 → **update 모드**

사용자가 명시적으로 `--mode init` 또는 `--mode update`로 강제 지정 가능.

## 입력 / 출력

**입력**:
- `{docs_root}/0. 템플릿/docs-file-template.json` — 표준 템플릿 (단일 출처)
- 사용자의 프로젝트 루트 — 코드 스캔 대상
- (update 모드) 기존 `.claude/docs-file.json`

**출력 (반드시 갱신)**:
- `.claude/docs-file.json` — 프로젝트별 설정 (생성 또는 갱신)

---

## Init 모드 — 새 프로젝트 docs-file.json 생성

### 절차

1. **사전 점검**:
   - `.claude/docs-file.json` 부재 확인. 있으면 update 모드로 전환할지 사용자에게 묻기.
   - 템플릿 파일 위치 결정:
     - 우선순위 1: 사용자가 지정한 경로
     - 우선순위 2: `./docs/0. 템플릿/docs-file-template.json`
     - 우선순위 3: 같은 워크스페이스의 다른 프로젝트에서 복사
   - 템플릿이 없으면 사용자에게 위치를 묻거나 fetch.

2. **템플릿 복사**:
   - 템플릿을 `.claude/docs-file.json`로 복사.
   - `_help` 같은 안내 키는 제거.

3. **최상위 메타 확정** (사용자 인터뷰):
   - `docs_root`: 기본 `./docs/`. 다른 경로면 변경.
   - `study_root`: 기본 `{docs_root}5. 운영/프로젝트 운영/12. 기술 문서/`.
   - `project_type`: `desktop` / `mobile` / `web` 중 택1.
     - 자동 추론 단서: `*.entitlements` 존재 → desktop / `Info.plist` + Android 폴더 동시 → mobile / `package.json` + `next.config|vite.config|app.module.ts` → web.
     - 단서가 모호하면 사용자에게 묻기.
   - `language`: 기본 `ko`.

4. **`code_mappings` 채우기** (핵심):
   - 템플릿의 각 섹션(`3_system_design` 등)의 `code_mappings`를 순회.
   - 각 항목의 `description` + `examples[project_type]`을 사용자에게 보여주고 실제 프로젝트 경로 매핑:
     ```
     [3_system_design / kind: entry-point]
     설명: 앱 / 서버 진입점. 부트스트랩, 환경 초기화, 의존성 등록이 일어나는 단일 파일
     예시 (desktop): <App 이름>App.swift (@main + AppDelegate / ModelContainer 등록)
     
     이 프로젝트에서 해당하는 파일은 어디인가요?
     ```
   - **자동 추정 모드** (사용자가 원하면):
     - `examples[project_type]`의 패턴을 실제 프로젝트 루트에서 glob으로 스캔
     - 매치되는 파일/폴더가 있으면 후보로 제시
     - 사용자가 yes/no로 확인하거나 다른 경로 입력
   - 매핑 결과로 `code_mappings`를 재구성:
     ```json
     "code_mappings": {
       "3_system_design": [
         { "path": "MyApp/MyAppApp.swift", "kind": "entry-point", "note": "@main + AppDelegate" },
         { "path": "MyApp/Features/", "kind": "domain-manager", "note": "도메인 매니저" }
       ],
       ...
     }
     ```
   - 매핑할 코드가 없으면(예: sidecar 없는 앱) 해당 항목은 빈 배열로 두거나 `"applicable": false` 표시.

5. **결과 저장 + 검증**:
   - JSON 유효성 검증 (key 일관성, conditional 섹션 활성 조건 등).
   - 사용자에게 최종 요약 보고:
     - 생성된 파일 경로
     - 활성 섹션 / 비활성 섹션
     - `code_mappings`에 매핑된 코드 경로 수
     - 누락 / 비활성 항목 (다음 단계에 추가 가능)

### Init 모드 보고 형식

- 생성된 `.claude/docs-file.json` 경로
- `project_type` 결정과 근거
- 13개 섹션 활성 / 비활성 상태 표
- `code_mappings` 매핑 결과 표
- 다음 액션: `ralph-docs` (코드 있으면) 또는 `1-plan-project-def` (그린필드)

---

## Update 모드 — 기존 docs-file.json 동기화

### 언제 사용
- 템플릿(`docs-file-template.json`)이 갱신됐을 때 (예: 새 섹션 추가, 키 이름 변경, 스킬 이름 변경)
- 프로젝트 코드 구조가 바뀌었을 때 (예: `Features/` → `Modules/` 폴더 이동)
- 새 sidecar / 외부 연동 추가로 새 코드 경로가 생겼을 때

### 절차

1. **기존 `.claude/docs-file.json` 로드**.
2. **현재 템플릿 `docs-file-template.json` 로드**.
3. **Diff 분석** — 5가지 차이를 식별:

   **a. 새 섹션 추가** (템플릿에는 있는데 actual에 없는 섹션 키)
   - 사용자에게 알리고 추가 여부 확인.
   - 추가 시 템플릿 값 그대로 복사.

   **b. 섹션 제거** (actual에 있는데 템플릿에 없는 섹션 키)
   - 사용자에게 알리고 보존 / 삭제 결정.
   - 삭제 결정 시 archive하거나 별도 백업.

   **c. 키 이름 변경** (예: 옛 `5_local_data_spec` → 새 `5_data_spec`)
   - 자동 매핑 규칙 (`docs-file-template.json`의 `_migrations` 같은 보조 맵이 있다면 따른다).
   - 매핑이 모호하면 사용자에게 확인.
   - 변경 시 `code_mappings`의 해당 키도 같이 변경.

   **d. title / path 변경**
   - 템플릿의 새 title/path를 actual에 반영할지 확인.
   - 사용자 동의 시 적용. 단, 폴더 실제 이동은 별도 작업(이 스킬이 파일시스템 폴더는 옮기지 않음).

   **e. 스킬 이름 변경** (예: `local-data-spec-builder` → `3-build-data`)
   - 자동 적용 (스킬 폴더 rename은 별도 — 스킬 자체에 부담 없음).

4. **`code_mappings` 보존**:
   - actual의 `code_mappings`는 프로젝트 특화 — 보존이 우선.
   - 단, 섹션 키가 변경되면 `code_mappings` 키도 따라 변경.
   - 새 섹션이 추가되고 매핑 후보가 있으면 init 모드의 매핑 절차를 1회 실행.

5. **변경 사항 사용자에게 표 형태로 보고 → 적용 여부 묻기**:
   ```
   변경 사항 미리보기:
   [추가] 새 섹션: 13_observability (모니터링·관측 명세서)
   [변경] 키 이름: 5_local_data_spec → 5_data_spec
   [변경] title: "로컬 데이터 명세서" → "데이터 명세서"
   [변경] path: "3. 구현/5. 로컬 데이터 명세서/" → "3. 구현/5. 데이터 명세서/"
   [변경] skill: "local-data-spec-builder" → "3-build-data"
   [보존] code_mappings.5_data_spec (3개 항목 — 키 자동 마이그레이션)
   
   적용할까요? (y/n)
   ```

6. **적용 + 백업**:
   - 변경 전 `.claude/docs-file.json.bak.<timestamp>` 백업 생성.
   - 변경 적용.
   - 사용자에게 결과 보고.

### Update 모드 보고 형식

- 적용된 변경 사항 (추가 / 제거 / 키 변경 / title 변경 / skill 변경)
- 보존된 항목 (`code_mappings` 등 프로젝트 특화)
- 백업 파일 경로
- 다음 액션: 변경된 섹션의 빌더 스킬 호출 권장 (예: 키 변경된 섹션은 빌더가 새 키 기준으로 동작)

---

## 핵심 원칙

- **템플릿이 진실** — 구조(키 / 그룹 / 스킬 이름)는 템플릿이 단일 출처.
- **`code_mappings`는 프로젝트 진실** — 사용자 코드 경로는 actual이 단일 출처. 템플릿의 `description`/`examples`는 매핑 가이드일 뿐.
- **파괴적 작업 전 항상 백업** — update 모드는 변경 전 `.bak.<timestamp>` 자동 생성.
- **사용자 확인** — 새 섹션 추가 / 제거는 자동 적용하지 않고 항상 묻는다.
- **JSON 유효성 검증** — 저장 전 키 일관성, conditional 활성 조건 등 자동 검증.

## 시작 절차 (자동 판정)

1. 워킹 디렉토리에서 `.claude/docs-file.json` 존재 여부 확인.
2. 템플릿 위치 결정 (`./docs/0. 템플릿/docs-file-template.json` 또는 사용자 지정).
3. 모드 자동 결정:
   - 없으면 init
   - 있으면 update (사용자가 init 강제 시 백업 후 재생성)
4. 모드별 절차 실행.

## 인터뷰 질문 세트

**init 공통**:
- `docs_root`?
- `project_type`? (자동 추론 결과 확인)
- `language`?

**init / `code_mappings` 매핑**:
- 각 `kind`별 — "이 프로젝트에서 [설명]에 해당하는 경로는?"
- 자동 스캔 결과를 후보로 제시 → yes/no/직접 입력

**update**:
- 새 섹션을 추가할지?
- 제거된 섹션을 보존할지 / 삭제할지?
- 키 / title / path / skill 변경을 적용할지?

## 보고 형식

- 모드 (init / update)
- 변경 / 생성된 항목 표
- 보존된 항목 (특히 `code_mappings`)
- 백업 파일 경로 (update 모드)
- 다음 액션 제안

## 품질 체크리스트

- 결과 JSON이 유효 (파싱 가능)
- 모든 섹션 키가 `groups`의 prefix 규칙(`<group_id>_<...>`) 준수
- `code_mappings` 키가 모두 `sections` 키에 존재
- conditional 섹션의 `activation_condition` 명시
- skill 필드의 스킬 이름이 실제 `~/.claude/skills/<이름>/` 폴더 존재 (또는 null)

## 종료 조건

- `.claude/docs-file.json` 저장 완료 + 유효성 검증 통과
- 사용자가 모든 변경 사항을 확인·승인
- 다음 액션이 제시됨

## 관련 스킬

- 모든 빌더 스킬(`1-plan-*` ~ `5-operate-*`)이 이 파일을 라우팅 설정으로 사용
- `ralph-docs`가 `code_mappings`를 따라 코드 → 섹션 매핑
- 템플릿 자체 갱신은 `docs/0. 템플릿/docs-file-template.json` 직접 편집
