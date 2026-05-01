---
name: 2-design-system
description: 프로젝트의 시스템 설계서(2. 설계 / 3. 시스템 설계서)를 채우거나 갱신한다. docs-file.json의 `project_type`(desktop / mobile / web) 또는 정의서·요구사항 명세서의 단서를 보고 적합한 템플릿(시스템 설계서 v1.0-template-{project_type}.md)을 선택해 작성한다. 7-섹션 공통 구조를 유지하되 project_type별 컴포넌트 분류와 핵심 관심사가 다르다.
---

요구사항 명세서를 기반으로 시스템 설계서를 작성하고, 합의된 내용을 문서에 즉시 반영한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web` 중 하나
- `sections_meta.3_system_design`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `2. 설계/3. 시스템 설계서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/설계/`)
  - `filenames`: 복사할 템플릿 파일들 (예: `시스템 설계서 v1.0-template-{project_type}.md`)

**project_type 결정 절차**:
1. `docs-file.json`의 `project_type`이 명시되어 있으면 그 값을 사용.
2. 없거나 모호하면 정의서 `[5] 제품 운영 / 실행환경` 또는 요구사항 명세서의 카테고리(`os_integration` 존재 여부, 플랫폼 명시)에서 단서를 추출:
   - 데스크톱 단서: macOS / Windows / Linux 명시, 메뉴바·Dock·entitlements·Sandbox·Notarization, Swift / SwiftUI / AppKit
   - 모바일 단서: iOS / Android 명시, 푸시·딥링크·위젯·생체인증, Swift / Kotlin / React Native / Flutter
   - 웹 단서: 브라우저·SSR·SPA·CDN·DB·API 라우트, JS 프레임워크 / 백엔드 런타임
3. 단서로도 결정 못 하면 사용자에게 질문 후 `docs-file.json`에 기록.

**파일 합성 규칙**:
- 템플릿 원본: `docs_root + template_path + filename.replace("{project_type}", project_type)` → 예: `./docs/0. 템플릿/설계/시스템 설계서 v1.0-template-desktop.md`
- 배치 위치: `docs_root + sections_meta.3_system_design.path`

## 입력 / 출력

**입력**:
- `{1_project_definition}/프로젝트 정의서 v{버전}.md`
- `{2_requirements}/요구사항 명세서 v{버전}.md` + `{2_requirements}/requirements/`
- `{4_ui_spec}/` (있으면) — 화면 흐름과 OS 통합 표면
- (브라운필드) 코드/리소스 — `code_mappings`로 매핑된 경로

**출력 (반드시 갱신)**:
1. `{3_system_design}/시스템 설계서 v{버전}.md` — 메인 설계서 (7-섹션)
2. `{3_system_design}/architecture.excalidraw.md` (선택) — 상세 아키텍처
3. (project_type별 추가 다이어그램) — desktop이면 `lifecycle-diagram.excalidraw.md`, web이면 `request-flow.excalidraw.md` 등

## 운영 모드

### A. 그린필드
요구사항 명세서를 기반으로 컴포넌트와 흐름을 설계 → 인터뷰로 빈 곳 채움.

### B. 브라운필드
요구사항 + 코드 신호로 실제 모듈을 추출. project_type별 코드 시그니처:
- **desktop (Swift)**: `final class .*Manager / .*Service`, `@main App`, `NSStatusItem`, `MenuBarExtra`, `@Model`, `Process`(sidecar), `*.entitlements`
- **mobile (네이티브 또는 RN/Flutter)**: `ViewModel`, `Repository`, navigation routes, `Info.plist` / `AndroidManifest.xml`, push 토큰 처리, `WidgetKit` / `App Widget`
- **web**: `pages/` / `app/` 라우트, API 핸들러, ORM 모델, 미들웨어, `next.config` / `vite.config`, 환경 변수 매니페스트

## 7-섹션 공통 구조 (모든 project_type)

세 변형 템플릿(desktop / mobile / web) 모두 동일한 섹션 골격을 사용한다. **컴포넌트 분류와 핵심 관심사만 다르다.**

- **[1] 전체 시스템 아키텍처**
  - 1.1 아키텍처 개요 (Mermaid `graph TB`)
  - 1.2 플랫폼 / 환경 전략 (project_type별 분기)
  - 1.3 상세 다이어그램 (Excalidraw 위키링크)
- **[2] 컴포넌트 설계** — 4계층 (project_type별 분류)
- **[3] 데이터 흐름과 상태 전이**
  - 3.1 라이프사이클 / 요청 흐름 (project_type별 분기)
  - 3.2 핵심 사용자 시나리오 시퀀스
  - 3.3 오류 / 비정상 흐름
- **[4] 요구사항 반영 및 추적성**
  - 4.1 FR / NFR → 설계 요소
  - 4.2 사용자 시나리오 → 화면 → 도메인 → 저장소 (project_type별 명칭)
  - 4.3 비기능 요구 대응 설계 (NFR 그룹 1:1)
- **[5] 빌드 · 배포 · 업데이트 전략** (project_type별 분기)
- **[6] 가정 및 오픈 이슈**
- **[부록] 기술 스택 상세** — 계층 매트릭스 + 디렉토리 구조
- **[7] 속성 정의**

> 본 문서는 **상위 인덱스**. 세부 명세(권한 / 데이터 / 연동 / 배포 등)는 별도 명세서로 분리하고 여기서는 *요약 + 위키링크*만.

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

- **플랫폼 전략 [1.2]**: `macOS v1.0 | iOS·iPadOS v2.0+ | 공통화 전략` 표 + `#if os(macOS)` 분기 가이드
- **컴포넌트 4계층 [2]**:
  - 2.1 View — SwiftUI / AppKit (NSStatusItem, NSPopover, NSWindow 등 AppKit 의존부 명시)
  - 2.2 Manager — `final class @MainActor` 도메인 로직, `@MainActor` / `actor` / `Task` 동시성
  - 2.3 데이터 — SwiftData @Model / UserDefaults / Keychain / 파일 (세부는 `[[로컬 데이터 명세서]]`)
  - 2.4 OS 통합 / Sidecar — 메뉴바 / 핫키 / 알림 / URL Scheme / sidecar 프로세스
- **라이프사이클 [3.1]**: launch / foreground / background / sleep / wake → Manager → 데이터
- **NFR 대응 [4.3]**: Sandbox · Hardened Runtime · Notarization · Code Signing
- **빌드·배포 [5]**: Debug / Release Direct / Release MAS / TestFlight, Sparkle / MAS 자동 업데이트

### Mobile (`project_type === "mobile"`)

- **플랫폼 전략 [1.2]**: `iOS / Android / 공통` 표 + 듀얼 네이티브 vs 크로스플랫폼(RN / Flutter) 선택 근거
- **컴포넌트 4계층 [2]**:
  - 2.1 View / ViewModel — SwiftUI / Compose / RN / Flutter
  - 2.2 서비스 / Use Case — 도메인 로직
  - 2.3 데이터 — 로컬 (SQLite / Realm / Room) + 원격 (REST / GraphQL)
  - 2.4 OS 통합 — 푸시 / 딥링크 / 위젯 / 생체인증 / 백그라운드 작업 / 공유
- **라이프사이클 [3.1]**: app launch / scene 활성화 / background 진입 / 메모리 경고 / 푸시 수신
- **NFR 대응 [4.3]**: 배터리 / 네트워크 효율 / 오프라인 / 접근성 / 다국어
- **빌드·배포 [5]**: TestFlight / Internal Testing → App Store / Play Store, OTA(CodePush/EAS), 강제 업데이트 정책

### Web (`project_type === "web"`)

- **환경 전략 [1.2]**: `local | dev | staging | prod` 환경 분리, 시크릿 관리, 데이터 격리
- **컴포넌트 4계층 [2]**:
  - 2.1 Page / Frontend — SSR / SPA / 정적 라우팅
  - 2.2 API 라우트 / 도메인 서비스 — REST / GraphQL / RPC
  - 2.3 데이터 — RDB(Postgres / MySQL) / NoSQL / 캐시(Redis) / 검색(ES) — 세부는 DB 스키마 명세서
  - 2.4 외부 연동 — 결제 / 인증(OAuth, SAML) / 메일 / 파일 스토리지 / CDN / WAF
- **요청 흐름 [3.1]**: 사용자 → CDN → 라우트 → 미들웨어(인증·인가) → 핸들러 → DB
- **NFR 대응 [4.3]**: 성능(P95 응답시간 / TTFB) / 보안(OWASP / CSRF / XSS) / 확장성(수평 / 캐싱) / 가용성(SLA / DR)
- **빌드·배포 [5]**: CI(lint/test/build) → 컨테이너 / 서버리스 → 트래픽 점진 전환(canary / blue-green), 롤백 전략

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정 (위 절차).
2. `sections_meta.3_system_design`의 `path`, `template_path`, `filenames`를 해석.
3. 정의서 + 요구사항 명세서 + UI 명세서(있으면) 읽기. FR / NFR / US-N 모두 인덱싱.
4. `{3_system_design}/시스템 설계서 v{버전}.md`가 없으면 `template_path`의 `시스템 설계서 v1.0-template-{project_type}.md`를 복사해 만든다.
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**공통**:
- 핵심 사용자 시나리오 1~2개를 시퀀스로 표현하면 어떻게 흐르는가?
- 오류 / 비정상 시나리오 시 사용자에게 어떻게 노출하고 어떻게 복구하는가?
- 각 NFR 그룹(성능 / 보안 / 안정성 / 코드 품질 / 인프라·배포)에 대해 어떤 대응 설계를 둘 것인가?

**desktop 추가**:
- macOS / iOS·iPadOS 동시 지원? View 공통화 vs 분기 비율?
- Manager 도메인 분할? `@MainActor` 경계?
- AppKit 의존부(메뉴바 등)?
- Sidecar / 외부 프로세스?

**mobile 추가**:
- iOS / Android 듀얼 네이티브 vs RN / Flutter?
- 푸시 / 딥링크 / 위젯 사용?
- 오프라인 동작 범위?

**web 추가**:
- SSR / SPA / 하이브리드?
- 환경 분리(local/dev/staging/prod)?
- 캐싱 / CDN 전략?
- 외부 연동(결제 / OAuth 등)?

## 작성 규칙

- **상위 인덱스 원칙** — 세부 명세는 별도 문서로 위임, 본 문서는 *요약 + 위키링크*.
- **각 표 행에 `근거(FR-NNN / NFR-NNN / US-N)` 컬럼 필수** — 추적성 고리 끊기지 않게.
- **project_type별 분기 가이드는 위 섹션에서 가져옴** — 템플릿 본문이 이미 project_type에 맞춰져 있으므로 그 구조를 그대로 따른다.

## 보고 형식

- 반영 완료 섹션 ([1]~[7] 중)
- 새로 확정된 컴포넌트 / 흐름 (사실 vs 추정 표시)
- FR / NFR / US-N 추적 매트릭스의 빈칸
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- [1.1] 아키텍처 다이어그램이 사용자 접점 → App/Backend → 데이터 순서로 그려짐
- [1.2] 플랫폼 / 환경 전략 표가 채워짐 (project_type별 컬럼)
- [2.1~2.4] 4계층 표가 모두 채워졌고 각 행에 `근거(FR-NNN)` 있음
- [3.1~3.3] 라이프사이클·요청 흐름 + 사용자 시나리오 + 오류 흐름 모두 작성
- [4.1] 모든 FR / NFR이 설계 요소에 1회 이상 매핑됨 (빈칸 없음)
- [4.2] 모든 US-N이 화면 → 도메인 → 저장소 흐름에 매핑됨
- [4.3] NFR 그룹 5행 모두 대응 설계 채워짐
- [5] 빌드 / 배포 / 업데이트 결정 사항 명시 (project_type별)
- 부록 디렉토리 구조가 프로젝트 컨벤션과 정합

## 종료 조건

- 7-섹션 + 부록 + 속성 정의 모두 채워짐 (해당 없음이면 명시)
- 컴포넌트 표가 코드 스캔 결과와 일치 (브라운필드)
- 추적성 매트릭스에 빈칸 없음
- project_type별 핵심 관심사(desktop: Sandbox·Sidecar / mobile: 푸시·OTA / web: CDN·환경분리)가 [4.3] 또는 [5]에 다뤄짐

## 다음 액션 (완료 시 제안)

1. **`2-design-ui`** 호출 — 화면 와이어프레임 + 단축키·제스처 + 접근성 + IME 명세
2. **`3-build-data`** 호출 — 데이터 스키마 + 마이그레이션 명세
3. **`3-build-integration`** 호출 — JSON Schema / 외부 연동 / sidecar / API 계약 (조건부)
4. **`4-deploy-permission`** 호출 — 권한 명세 (desktop: entitlements / mobile: 권한 / web: 인증·인가)
5. **`4-deploy-os`** 호출 — OS 통합 명세 (desktop: 메뉴바 / mobile: 푸시·딥링크·위젯)
6. **`4-deploy-release`** 호출 — 빌드·배포 명세 (desktop: Code Signing / mobile: TestFlight·Play Store / web: CI·인프라)
