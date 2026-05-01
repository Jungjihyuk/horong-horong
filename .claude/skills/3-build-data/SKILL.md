---
name: 3-build-data
description: 프로젝트의 데이터 명세서(3. 구현 / 5. 데이터 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web) 또는 정의서·요구사항 명세서의 단서를 보고 적합한 템플릿을 선택해 작성한다. 데스크톱·모바일은 로컬 스토어(SwiftData / Core Data / SQLite / UserDefaults / Keychain / Realm 등) 스키마·엔티티·마이그레이션·백업·동기화 정책을 다루고, 웹은 서버 DB(Postgres / MySQL 등) 스키마·인덱스·마이그레이션·운영 정책을 다룬다.
---

요구사항 명세서와 시스템 설계서를 기반으로 데이터 명세서를 작성하고, 합의된 내용을 문서에 즉시 반영한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web` 중 하나
- `sections_meta.5_data_spec`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `3. 구현/5. 데이터 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/구현/`)
  - `filenames`: 복사할 템플릿 파일들

**project_type 결정**: `docs-file.json`의 `project_type`이 우선. 없으면 `2-design-system` 또는 정의서 [5] 제품 운영의 단서로 판정.

**파일 합성 규칙**:
- 기본: `docs_root + template_path + filename.replace("{project_type}", project_type)`
- 예외 (web): `로컬 데이터 명세서 v1.0-template-web.md`가 없으면 `DB 스키마 명세서 v1.0-template-web.md`로 폴백 (서버 DB 명세서로 동작)
- 배치 위치: `docs_root + sections_meta.5_data_spec.path`

## 입력 / 출력

**입력**:
- `{2_requirements}/요구사항 명세서 v{버전}.md` + `requirements/NFR-*.md` (특히 마이그레이션 / 백업 / 보존 / 성능 NFR)
- `{3_system_design}/시스템 설계서 v{버전}.md` ([2.3] 데이터 계층, [3] 데이터 흐름)
- (있으면) `{4_ui_spec}/UI 명세서 v{버전}.md` (UI 상태와 데이터 의존)
- (브라운필드) 코드:
  - **desktop (Swift)**: `*/Models/*.swift` (`@Model`), `*App.swift`(`Schema([...])`), `*/Constants.swift`(`AppStorageKey` enum)
  - **mobile**: Realm / Room / Core Data 모델, AsyncStorage / SharedPreferences 키
  - **web**: ORM 모델 (Prisma / TypeORM / Sequelize / SQLAlchemy), 마이그레이션 폴더(`migrations/` / `prisma/migrations/`), 환경 변수 매니페스트

**출력 (반드시 갱신)**:
1. `{5_data_spec}/데이터 명세서 v{버전}.md` — 본 명세서
2. `{5_data_spec}/er.excalidraw.md` (선택) — 엔티티 관계도
3. `{5_data_spec}/migration-guide.md` (선택) — 마이그레이션 가이드 (스키마 변경 시 갱신)

## 운영 모드

### A. 그린필드
요구사항·시스템 설계에서 데이터 종류를 도출 → 스토어 매트릭스 / 엔티티 / 마이그레이션 정책 채움.

### B. 브라운필드
실제 코드에서 모델·키·스키마 추출. `Schema([...])` / ORM 모델 / 마이그레이션 폴더와 1:1 정합 검증.

## 공통 구조 (모든 project_type)

데이터 명세서는 다음 영역을 다룬다 ([N] 번호는 템플릿 따라 다를 수 있음).

- **[1] 스토어 결정 매트릭스** — `데이터 종류 | 스토어 | 이유 | 근거(NFR-NNN)` 표
- **[2] 엔티티 정의** — 속성 / 타입 / 인덱스 / 관계 / 삭제 규칙
- **[3] 스키마 등록 / 단일 출처** — `Schema([...])` 등록 위치(desktop/mobile) 또는 ORM 모델 정의 파일(web)
- **[4] 엔티티 관계도** — Excalidraw 또는 ERD
- **[5] 키-값 / 환경 정책** — UserDefaults / SharedPreferences / 환경 변수 키 일람 (직접 문자열 금지, enum / 매니페스트로 관리)
- **[6] 마이그레이션 전략** — 정책 + 실패 시 폴백 (사용자 데이터 손실 0건 보장)
- **[7] 백업 / 내보내기 / 가져오기 / 지우기** — 사용자 자기결정권 보장 인터페이스 (desktop / mobile) 또는 데이터 보존·삭제 정책 (web — GDPR / 개인정보보호법)
- **[8] 동기화 / 복제 (선택)** — iCloud / CloudKit / Firebase / DB 복제·읽기 복제본
- **[9] 보안 / 분류** — 민감 데이터 보관 위치(Keychain / 암호화 / KMS), 접근 제어
- **[10] 용량 / 성능** — 예상 최대 용량, 캐시 정책, 인덱스 전략, 모니터링 지표

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

- 스토어 매트릭스 행: SwiftData `@Model` / Core Data / SQLite / UserDefaults / Keychain / 파일 (Application Support / Caches)
- `Schema([...])` 등록은 `*App.swift`의 `modelContainer(for:)`에서 단일 관리
- UserDefaults 키는 `Utilities/Constants.swift`의 `AppStorageKey` enum에 강제 등록
- 마이그레이션: SwiftData lightweight vs versioned, 실패 시 폴백 (백업 자동 생성)
- iCloud / CloudKit 동기화 — 충돌 해소 정책
- 민감 정보 → Keychain (Sandbox container 평문 저장 금지)

### Mobile (`project_type === "mobile"`)

- 스토어 매트릭스 행: Realm / Core Data / Room / SQLite / SharedPreferences / Keychain / 파일
- 동기화 — Firebase / 자체 서버 / iCloud
- 백업 — iOS 자동 백업 정책, Android 자동 백업 룰
- 오프라인 → 재연결 동작 (큐잉 / 충돌 해소)

### Web (`project_type === "web"`)

- 스토어: RDB(Postgres / MySQL) / NoSQL(MongoDB / DynamoDB) / 캐시(Redis) / 검색(Elasticsearch / OpenSearch) / 객체 스토리지(S3)
- 스키마는 ORM(Prisma / TypeORM / SQLAlchemy 등) 단일 출처
- 마이그레이션 — `migrations/` 폴더 + 무중단 배포 정책 (down 마이그레이션 / 백워드 호환)
- 인덱스 / 파티셔닝 / 샤딩 전략
- 백업 / DR — RPO / RTO 명시
- GDPR / 개인정보보호법 — 보존 기간 / 익명화 / 삭제 절차
- 환경별 격리 (local / dev / staging / prod) — 시크릿 관리

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.5_data_spec`의 `path`, `template_path`, `filenames` 해석.
3. 요구사항·시스템 설계 읽기 — 데이터 종류와 NFR(특히 마이그레이션·백업·보존) 인덱싱.
4. `{5_data_spec}/데이터 명세서 v{버전}.md`가 없으면 `template_path`의 `로컬 데이터 명세서 v1.0-template-{project_type}.md`(또는 web의 경우 `DB 스키마 명세서 v1.0-template-web.md`)를 복사.
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**공통**:
- 어떤 데이터를 영속해야 하는가? (사용자 입력 / 캐시 / 설정 / 민감 정보)
- 보존 기간, 백업, 사용자 데이터 삭제 정책?
- 마이그레이션 실패 시 폴백?
- 민감 정보 분류와 보관 위치?

**desktop / mobile 추가**:
- 로컬 스토어 종류(SwiftData / Core Data / Realm / SQLite)?
- iCloud / CloudKit / Firebase 동기화 사용?
- 오프라인 동작 시 데이터 일관성?

**web 추가**:
- DB 종류(Postgres / MySQL / NoSQL)?
- ORM(Prisma / TypeORM / 등)?
- 마이그레이션 도구와 무중단 배포 가능?
- 캐시 / 검색 인덱스 사용?
- 환경별 데이터 격리?

## 핵심 원칙

- **사용자 데이터 손실 0건이 1순위** — 마이그레이션 실패 시 폴백을 항상 정의.
- **민감 정보는 Keychain (desktop / mobile) 또는 KMS / 암호화된 컬럼 (web)** — 평문 저장 금지.
- **스키마 단일 출처 유지** — `@Model` ↔ `Schema([...])` 동기화 / ORM 모델 ↔ 마이그레이션 동기화.
- **환경 변수 / 키는 enum 또는 매니페스트로** — 직접 문자열 금지.
- **시스템 설계서와 데이터 흐름 정합** — Repository / Service 명칭 일치.

## 보고 형식

- 반영 완료 영역 ([1]~[10] 중)
- 새로 정의된 엔티티 / 키 / 마이그레이션 (사실 vs 추정 표시)
- 시스템 설계서와의 정합 점검 결과
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- [1] 모든 영속 데이터가 스토어 매트릭스에 분류됨
- [2~3] 모든 엔티티 / 모델이 스키마 등록 위치(`Schema([...])` / ORM 모델)와 1:1 일치
- [4] 엔티티 관계도가 첨부됨 (Excalidraw / ERD)
- [5] 모든 키 / 환경 변수가 enum 또는 매니페스트에 등록됨 (코드 grep으로 직접 문자열 사용 0건 확인)
- [6] 마이그레이션 전략과 실패 시 폴백 명시
- [7] 백업 / 내보내기 / 가져오기 / 지우기 인터페이스 정의 (desktop / mobile) 또는 보존 / 삭제 정책 (web)
- [9] 민감 정보 보관 위치 명시 (Keychain / 암호화)
- 시스템 설계서 [2.3] 데이터 계층과 정합

## 종료 조건

- [1]~[10] 영역 모두 채워짐 (해당 없음이면 명시)
- 코드 스캔 결과와 스키마 등록 항목이 1:1 일치 (브라운필드)
- 마이그레이션 실패 시 사용자 데이터 보존이 보장되는 설계
- (desktop / mobile) 모든 UserDefaults / SharedPreferences 키가 enum에 등록됨
- (web) 모든 환경 변수가 매니페스트에 등록되고 환경별 격리 정책이 명시됨

## 다음 액션 (완료 시 제안)

1. **`3-build-integration`** 호출 — 외부 연동 / sidecar / 파일 포맷 / API 계약 (조건부)
2. **`2-design-system`** 갱신 — [2.3] 데이터 계층 표 동기화
3. **`5-operate-schedule`** 호출 — 데이터 작업 일정 / 마이그레이션 일정 반영
4. **`4-deploy-permission`** 호출 — 데이터 접근 권한 (desktop entitlements / mobile permission / web 인증·인가)
