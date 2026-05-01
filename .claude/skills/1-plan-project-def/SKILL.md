---
name: 1-plan-project-def
description: 프로젝트의 정의서(1. 기획 / 1. 프로젝트 정의서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web) 또는 정의서 단서를 보고 적합한 템플릿(프로젝트 정의서 v1.0-template-{project_type}.md)을 선택해 작성한다. 새 프로젝트는 인터뷰로, 이미 코드가 있는 프로젝트는 코드/리소스를 읽어 채운다. 사용자가 비전·범위·KPI·ROI·제약·성공 기준·제품 운영을 확정하려 할 때 사용한다.
---

프로젝트 정의서를 **완성된 project_type별 템플릿**에 맞춰 채우고, 합의된 내용을 문서에 즉시 반영한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web` 중 하나
- `sections_meta.1_project_definition`: 이 섹션의 메타
  - `path`: 정의서가 들어갈 위치 (예: `1. 기획/1. 프로젝트 정의서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/기획/`)
  - `filenames`: 복사할 템플릿 파일들 (예: `프로젝트 정의서 v1.0-template-{project_type}.md`)

**project_type 결정 절차**:
1. `docs-file.json`의 `project_type`이 명시되어 있으면 그 값을 사용.
2. 없거나 모호하면 단서 추출:
   - **desktop**: macOS / Windows / Linux 명시, `*.entitlements`, `Info.plist` + `LSUIElement`, Swift / SwiftUI / Tauri / Electron, 메뉴바·Dock·Notarization
   - **mobile**: iOS / Android, 푸시·딥링크·위젯, Swift / Kotlin / React Native / Flutter, App Store / Play Store
   - **web**: 브라우저·SSR·SPA·CDN·DB·API 라우트, JS 프레임워크 + 백엔드 런타임
3. 단서로도 결정 못 하면 사용자에게 질문 후 `.claude/docs-file.json`에 기록.

**파일 합성 규칙**:
- 템플릿 원본: `docs_root + template_path + filename.replace("{project_type}", project_type)` → 예: `./docs/0. 템플릿/기획/프로젝트 정의서 v1.0-template-desktop.md`
- 배치 위치: `docs_root + sections_meta.1_project_definition.path`

## 운영 모드

### A. 그린필드 (코드 거의 없음)
인터뷰로 수집 → 합의된 항목만 즉시 문서에 반영. 미확정 항목은 `(placeholder)` 또는 `TODO`로 둔다.

### B. 브라운필드 (이미 코드/리소스가 있음)
프로젝트 루트의 신호를 읽어 정의서를 채운다. project_type별 단서:

**공통**:
- `README.md` / `AGENTS.md` / `CLAUDE.md` — 비전·문제·해결 방향
- 기존 `docs/` 하위 문서 — 기존 합의

**desktop**:
- `project.yml` / `Package.swift` / `*.xcodeproj` — 앱 이름, 최소 OS 버전, 모듈 구조
- `Info.plist` / entitlements — Sandbox / 권한 / URL Scheme
- `Sources/` / `Views/` / `Managers/` / `Models/` — 핵심 기능과 범위 추정
- `Shared/*Contracts/*.schema.json` — 외부 연동 / sidecar 존재 여부

**mobile**:
- `Info.plist` (iOS) / `AndroidManifest.xml` (Android) — 권한·기능 플래그
- `ios/<App>/` / `android/app/` 또는 RN/Flutter 프로젝트 구조
- 푸시·딥링크·위젯 익스텐션 폴더 존재
- 스토어 메타데이터 (앱 이름·아이콘·스크린샷)

**web**:
- `package.json` / `pnpm-workspace.yaml` / `Cargo.toml` — 프레임워크와 의존성
- `next.config.js` / `vite.config.ts` / `app.module.ts` — 배포 모드 (SSR / SPA)
- `Dockerfile` / `docker-compose.yml` / IaC — 배포 환경
- `prisma/schema.prisma` 등 — 데이터 스키마

읽어낸 내용은 **사실(코드 근거)**과 **추정(인터뷰 필요)**으로 구분해 채우고, 추정 항목은 사용자에게 확인 질문을 던진다.

## 기본 원칙

- **문서 우선**: 답변만 하지 말고 정의서 파일을 실제로 수정한다.
- **점진적 확정**: 확정된 항목만 본문에 반영하고 미확정은 `(placeholder)` 유지.
- **근거 명시**: KPI·ROI·일정·범위는 수치와 가정을 함께 기록한다.
- **양식 보존**: 템플릿의 헤더 구조(`[1]~[10]`), 콜아웃, 표 컬럼은 유지한다.

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.1_project_definition`의 `path`, `template_path`, `filenames` 해석.
3. `{1_project_definition}/프로젝트 정의서 v{버전}.md`를 읽는다.
4. 파일이 없으면 `template_path`의 `프로젝트 정의서 v1.0-template-{project_type}.md`를 복사해 만든다.
5. 프론트매터(`title`, `version`, `created`, `author`)를 먼저 확정한다.
6. 운영 모드(A 그린필드 / B 브라운필드)를 판정하고 알맞은 입력 수집 단계로 진행한다.

## 인터뷰 질문 세트

**공통 (그린필드)**:
- 해결하려는 **현재 문제**는 무엇인가? (구체적 상황 / 빈도 / 영향)
- 핵심 **사용자 시나리오**는 무엇인가? (`나는 ~를 하고 싶다 / 왜냐하면 ~`, US-N 단위)
- v1.0에서 반드시 들어가야 할 **핵심 기능**은? 의도적으로 **제외**할 항목은?
- **KPI**(현재 / 목표 / 측정 방법), **성공 기준**(수용 기준 / Done Definition), **ROI** 추정?
- **예산 / 인력 / 기술 제약**?
- **학습·성장 목표**(선택)?

**desktop 추가**:
- **대상 OS / 최소 버전**? (macOS 14.0+ 등)
- **배포 채널**? (Direct DMG / MAS / TestFlight / Homebrew Cask)
- **Sandbox / 권한 정책**? (App Sandbox 활성, Hardened Runtime, entitlements)
- **로컬 데이터** 종류? (SwiftData / Core Data / Keychain / 파일 / iCloud)
- **OS 통합 표면**? (메뉴바 / Dock / 단축키 / 알림 / URL Scheme)
- **오프라인 동작 정책**과 네트워크 의존도?
- **자동 업데이트** 방식? (Sparkle / MAS 자동)

**mobile 추가**:
- **대상 OS와 최소 버전**? (iOS 17+ / Android 12+ 등)
- **네이티브 vs 크로스플랫폼**? (Swift+Kotlin / React Native / Flutter)
- **배포 채널**? (App Store + Google Play 동시 / 단일)
- **권한 / 푸시 / 딥링크 / 위젯** 사용?
- **오프라인 동작과 동기화 정책**?
- **OTA 업데이트** 사용? (CodePush / EAS Update)

**web 추가**:
- **렌더링 방식**? (SSR / SPA / 정적 / 하이브리드)
- **프론트엔드 / 백엔드 분리** 또는 풀스택?
- **DB 종류**? (Postgres / MySQL / MongoDB / 캐시)
- **배포 환경**? (셀프 호스트 / Vercel / AWS / GCP / 컨테이너 / 서버리스)
- **인증·인가 방식**? (세션 / JWT / OAuth / SSO / MFA)
- **외부 연동**? (결제 / 메일 / SaaS / Webhook)

## 섹션별 반영 규칙 (10-섹션 템플릿 — project_type별 [5] 차이)

문서의 섹션 번호와 1:1 매칭으로 채운다.

- **[1] 프로젝트 배경** — 현재 문제점(불릿) + 해결 방안(1~2문단) + 핵심 기술(불릿)
- **[2] 사용자 시나리오** — `US-N | 나는 ~를 하고 싶다 | 왜냐하면 ~` 표. 최소 2건
- **[3] 핵심 기능 정의** — `기능 | 설명 | 관련 시나리오(US-N) | 버전` 표
- **[4] 프로젝트 범위** — In Scope (v1.0 테마 + 항목) / Out of Scope (제외 + 이유) / 제약사항(예산·인력·기술)
- **[5] 제품 운영** *(project_type별 분기)*:
  - **desktop**: 실행환경 / 배포 채널 / Sandbox / 로컬 데이터 / OS 통합 표면 / 오프라인 정책 / 자동 업데이트
  - **mobile**: 대상 OS·기기 / 네이티브 vs 크로스플랫폼 / 배포 채널 (App Store + Play Store) / 권한·푸시·딥링크·위젯 / 오프라인 / OTA 업데이트
  - **web**: 렌더링 방식 / 환경 분리 (local/dev/staging/prod) / DB·캐시·검색 / 인증·인가 / 외부 연동 / 배포·CDN
- **[6] 성과 지표 (KPI)** — `지표 | As-Is | To-Be | 측정 방법` 표. 수치가 없으면 추정 범위 + 검증 계획 한 줄
- **[7] 성공 기준** — 수용 기준 표(영역 / 측정 기준 / 달성 조건) + 프로젝트 종료 조건 체크리스트
- **[8] 투자 대비 효과 (ROI)** — 투자 비용 표 + 기대 가치 표 + ROI 계산식. 가정값 명시
- **[9] 학습 및 성장 목표** *(선택)* — 기술 영역 불릿
- **[10] 속성 정의** — 변경 없음 (템플릿 유지)

각 섹션 반영 후 사용자에게 **보고**한다.

## 보고 형식

- 반영 완료 섹션
- 새로 확정된 내용 (사실 vs 추정 표시)
- 아직 비어 있거나 추정으로 남은 항목
- 다음 질문 (최대 3개)

## project_type별 [5] 제품 운영 필수 체크리스트

`.claude/docs-file.json`의 `project_type` 값에 따라 다음을 점검:

**`desktop`**: [5]의 7개 하위 항목 모두 채워져야 함
1. 실행환경
2. 배포 채널
3. 보안 자세 (Sandbox)
4. 로컬 데이터 정책
5. OS 통합 표면
6. 오프라인 정책
7. 자동 업데이트

**`mobile`**: [5]의 6개 하위 항목 모두 채워져야 함
1. 대상 OS·기기
2. 네이티브 vs 크로스플랫폼 결정
3. 배포 채널
4. 권한·푸시·딥링크·위젯
5. 오프라인 동작 / 동기화
6. OTA 업데이트 정책

**`web`**: [5]의 6개 하위 항목 모두 채워져야 함
1. 렌더링 방식 (SSR / SPA / 정적 / 하이브리드)
2. 환경 분리 (local / dev / staging / prod)
3. DB / 캐시 / 검색 인프라
4. 인증·인가 방식
5. 외부 연동 (결제 / 메일 / SaaS / Webhook)
6. 배포 / CDN / 자동 스케일

미충족이면 종료하지 않고 추가 질문. 상세는 후속 명세(섹션 5~9)에서 다룬다 — 정의서에는 *결정과 근거*만 적는다.

## 종료 조건

아래를 모두 만족하면 정의서 초안 완료로 판단한다.
- 본문의 `(placeholder)` / `xxxx` / `(...)` 가 모두 제거되었거나, 남은 것은 명시적 `TODO`로 표시
- US-N 시나리오가 최소 2건 이상
- [3] 핵심 기능 표가 채워짐
- [4] In Scope / Out of Scope가 각 2개 이상
- [5] 제품 운영의 project_type별 필수 항목 모두 결정됨 (위 체크리스트)
- [6] KPI 표에 As-Is·To-Be·측정 방법이 모두 채워짐 (수치 없으면 추정 범위 명시)
- [7] 수용 기준과 종료 조건이 작성됨
- [8] ROI의 비용 / 기대 가치 / 가정이 명시됨
- 프론트매터의 `project_status`가 `📄 초안` 이상

완료 시 다음 액션을 제안한다.
1. **`1-plan-requirements`** 호출 — FR-NNN / NFR-NNN으로 요구사항 분해
2. **`2-design-system`** 호출 — 시스템 설계서 작성
3. 우선순위(`🚨 P0` / `⭐️ P1` / `🧩 P2` / `🛠️ P3`) 태깅
4. 1차 개발 범위(MVP) 확정
