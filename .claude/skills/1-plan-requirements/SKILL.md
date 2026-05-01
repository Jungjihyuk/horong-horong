---
name: 1-plan-requirements
description: 프로젝트의 요구사항 명세서(1. 기획 / 2. 요구사항 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web)에 따라 카테고리·NFR 표준 영역이 다르다. 프로젝트 정의서를 입력으로 받아 FR/NFR로 분해하고, 개별 요구사항 카드(FR-NNN, NFR-NNN)와 대시보드를 생성한다.
---

프로젝트 정의서를 **완성된 project_type별 요구사항 템플릿**에 따라 요구사항 명세서로 변환하고, 합의된 항목을 문서에 즉시 반영한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web`
- `sections_meta.2_requirements`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `1. 기획/2. 요구사항 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/기획/`)
  - `filenames`: 복사할 템플릿 파일들 (예: `요구사항 명세서 v1.0-template-{project_type}.md`, `FR-001.md`, `NFR-001.md`)

**project_type 결정**: `docs-file.json`의 `project_type`이 우선. 없으면 `1-plan-project-def`이 결정한 값을 따른다.

**파일 합성 규칙**:
- 메인 명세서: `docs_root + template_path + filename.replace("{project_type}", project_type)`
- 카드 템플릿(`FR-001.md`, `NFR-001.md`)은 모든 project_type 공통 — `path` 안의 `requirements/` 하위 폴더에 인스턴스화 (예: `requirements/FR-002.md`)

## 입력 / 출력

**입력**:
- `{1_project_definition}/프로젝트 정의서 v{버전}.md` — 확정된 사용자 시나리오(US-N), 핵심 기능, 범위, 제약, KPI, 성공 기준, [5] 제품 운영
- (브라운필드) 프로젝트 코드/리소스 — `code_mappings`로 매핑된 경로

**출력 (반드시 갱신)**:
1. `{2_requirements}/요구사항 명세서 v{버전}.md` — 대시보드 (Dataview로 `requirements/` 자동 집계)
2. `{2_requirements}/requirements/FR-NNN.md` — 개별 기능 요구사항 카드
3. `{2_requirements}/requirements/NFR-NNN.md` — 개별 비기능 요구사항 카드

## 운영 모드

### A. 그린필드
정의서의 확정 항목을 FR/NFR로 분해 → 인터뷰로 빈 곳 채움.

### B. 브라운필드
정의서 + 코드 신호로 기존 기능을 FR로 추출, 빌드/설정에서 NFR 추출. project_type별 코드 시그니처:

**desktop (Swift / 기타)**:
- View / Manager / Service 모듈 → FR
- entitlements / Info.plist Privacy 키 → NFR (보안·권한)
- 빌드 설정(`ENABLE_APP_SANDBOX`, `MACOSX_DEPLOYMENT_TARGET`) → NFR (인프라·배포)
- Instruments / MetricKit → NFR (성능)

**mobile (네이티브 / RN / Flutter)**:
- 화면·라우트·서비스 모듈 → FR
- iOS Info.plist + privacy manifest, Android AndroidManifest.xml permissions → NFR (보안·권한)
- 빌드 설정 / 푸시 / OTA → NFR (배포)
- 배터리·네트워크 효율 측정 → NFR (성능)

**web**:
- API 라우트 / 페이지 / 컴포넌트 → FR
- 인증 미들웨어 / CORS / CSP / 시크릿 매니페스트 → NFR (보안)
- CI / 배포 워크플로 / IaC → NFR (인프라·배포)
- P95 응답시간 / SLA / 가용성 측정 → NFR (성능·안정성)

## 카드 파일 형식 (YAML frontmatter only)

각 요구사항 카드는 `requirements/` 폴더의 개별 파일이며, **YAML frontmatter만** 작성하고 본문은 비운다.

템플릿 원본: `0. 템플릿/기획/FR-001.md`, `0. 템플릿/기획/NFR-001.md` (project_type 무관 공통)

| 필드 | 설명 | 값 예시 |
| --- | --- | --- |
| `id` | 고유 ID. FR은 `FR-001`부터, NFR은 `NFR-001`부터 순차 | `FR-001`, `NFR-015` |
| `group` | 대시보드 섹션 매핑. FR은 `"1.N"`, NFR은 `"2.N"` | `"1.1"`, `"2.3"` |
| `completed` | 구현 완료 여부 | `false` |
| `category` | 카테고리(아래 표 참조) | `ui`, `performance` |
| `description` | 한 줄 요약 (대시보드에 표시) | `메뉴바 단일 진입점` |
| `detail` | 상세 + 수용 기준 (측정 가능한 표현) | `... 풀스크린 앱 전환 없이 6개 탭 모두 도달` |
| `keywords` | 검색용 키워드 | `메뉴바, 팝오버` |
| `requirement_priority` | 우선순위 | `🚨 P0 (필수 기능)` |
| `incharge` | 담당자 | `🧑🏻‍💻 정지혁` |
| `related_apis` | 관련 컴포넌트 / API 링크 | `- "[[managers/MenuBarController]]"` |
| `tags` | 반드시 `requirement` 포함 | `- requirement` |

### category (project_type별 표준)

**FR 카테고리** (택1):
- **desktop**: `ui`, `local_data`, `integration`, `os_integration`, `distribution`, `entitlements`, `swift_app`
- **mobile**: `ui`, `navigation`, `local_data`, `push`, `deeplink`, `widget`, `permission`, `distribution`
- **web**: `ui`, `api`, `data`, `auth`, `integration`, `infra`

**NFR 카테고리** (택1):
- **공통**: `performance`, `reliability`, `security`, `accessibility`, `localization`
- **desktop 추가**: `migration`, `os_compat`
- **mobile 추가**: `battery`, `offline`, `os_compat`
- **web 추가**: `scalability`, `availability`, `compliance`

### 우선순위 체계 (project_type 무관)

| 값 | 의미 |
| --- | --- |
| `🚨 P0 (필수 기능)` | MVP 필수. 없으면 출시 불가 |
| `⭐️ P1 (핵심 기능)` | 핵심 사용자 가치. MVP 직후 즉시 |
| `🧩 P2 (중요하지만 급하지 않음)` | 있으면 좋지만 출시 가능 |
| `🛠️ P3 (개선사항)` | 기존 기능 강화 |

### group 매핑 (대시보드 섹션 1:1)

- FR 섹션은 `"1.N"` (요구사항 명세서의 [1] 기능적 요구사항 하위 그룹)
- NFR 섹션은 `"2.N"` (요구사항 명세서의 [2] 비기능적 요구사항 하위 그룹)

**project_type별 표준 NFR 그룹**:

**desktop**:
- `2.1` 성능 — cold start, 메모리, 배터리, UI 응답성
- `2.2` 보안 — Sandbox, Hardened Runtime, Keychain, 코드 서명
- `2.3` 안정성 — 크래시 리포트, 데이터 무결성, 자동 복구
- `2.4` 코드 품질 — Swift 컨벤션, SwiftLint, 테스트
- `2.5` 인프라 / 배포 — XcodeGen, CI/CD, Notarization

**mobile**:
- `2.1` 성능 — 콜드 스타트, 메모리, 배터리, 네트워크 효율
- `2.2` 보안 — 권한, 데이터 암호화, Keychain·Keystore
- `2.3` 안정성 — 크래시 리포트, 오프라인 / 재연결
- `2.4` 코드 품질 — 컨벤션, lint, 테스트
- `2.5` 배포 — 스토어 심사, OTA, 강제 업데이트

**web**:
- `2.1` 성능 — TTFB, P95 응답시간, Core Web Vitals
- `2.2` 보안 — OWASP, 인증·인가, 시크릿 관리
- `2.3` 가용성 — SLA, DR, 자동 복구
- `2.4` 확장성 — 수평 / 수직 스케일, 캐싱
- `2.5` 인프라 / 배포 — CI/CD, 컨테이너, IaC

FR 그룹은 정의서의 핵심 기능 단위로 명명 (예: desktop `1.1` 메뉴바 / mobile `1.1` 홈 화면 / web `1.1` 인증).

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.2_requirements`의 `path`, `template_path`, `filenames` 해석.
3. `{1_project_definition}/프로젝트 정의서 v{버전}.md`를 읽고 확정 / 미확정 항목 구분.
4. `{2_requirements}/요구사항 명세서 v{버전}.md`가 없으면 `template_path`의 `요구사항 명세서 v1.0-template-{project_type}.md`를 복사해 만든다.
5. `{2_requirements}/requirements/` 폴더의 기존 카드를 스캔해 다음 ID 번호 파악.
6. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**공통 (그린필드)**:
- 사용자에게 반드시 제공해야 하는 **핵심 기능 3가지**는?
- MVP에서 의도적으로 **제외**할 기능은?
- 각 요구사항의 **우선순위** 판단 기준은?

**desktop 추가**:
- **OS 권한 요구사항** — Accessibility / ScreenCaptureKit / Notification / Login Items 중 무엇이 필요한가? 트리거 / UX / 거부 폴백?
- **OS 통합 NFR** — 메뉴바 토글 응답, Dock 클릭, 전역 핫키 충돌?
- **오프라인 / 네트워크 NFR**?
- **로컬 데이터 NFR** — 마이그레이션 정책, 백업 / 내보내기 / 지우기?
- **성능 NFR** — cold start ms, idle 메모리 MB, CPU 점유율?
- **배포·서명·공증 NFR** — Notarization 통과율, Sparkle / MAS SLA?
- **접근성 / 단축키 NFR** — VoiceOver, 한국어 IME?

**mobile 추가**:
- **권한 NFR** — 카메라 / 위치 / 알림 / 마이크 등 트리거와 거부 폴백?
- **푸시 / 딥링크 NFR** — 미설치 폴백, 도착 SLA?
- **오프라인 NFR** — 오프라인 가능 기능 / 데이터 일관성?
- **성능 NFR** — 콜드 스타트, 메모리, 배터리?
- **배포 NFR** — 스토어 심사 통과율, OTA SLA, 강제 업데이트 정책?
- **접근성 NFR** — VoiceOver / TalkBack, Dynamic Type?

**web 추가**:
- **인증·인가 NFR** — 세션 만료, 토큰 갱신, MFA?
- **성능 NFR** — TTFB, P95 응답시간, Core Web Vitals?
- **보안 NFR** — OWASP Top 10 대응, CSP / CORS 정책?
- **가용성 NFR** — SLA, DR, RPO/RTO?
- **확장성 NFR** — 동시 사용자 수, DB 쿼리 한계?
- **접근성 NFR** — WCAG 2.1 AA?

## project_type별 필수 NFR 카테고리 체크리스트

`.claude/docs-file.json`의 `project_type` 값에 따라 NFR이 다음 영역을 모두 커버하는지 점검:

**`desktop`** — 7영역:
1. OS 권한
2. OS 통합 응답성
3. 오프라인 / 네트워크
4. 로컬 데이터 (마이그레이션 / 백업)
5. 성능
6. 배포·서명·공증
7. 접근성 / 단축키 / IME

**`mobile`** — 7영역:
1. 권한 (트리거·UX·거부 폴백)
2. 푸시 / 딥링크
3. 오프라인 / 동기화
4. 로컬 데이터 (마이그레이션 / 백업)
5. 성능 (콜드 스타트 / 배터리 / 네트워크)
6. 배포 (스토어 / OTA / 강제 업데이트)
7. 접근성

**`web`** — 7영역:
1. 인증·인가
2. OWASP Top 10 / 시크릿 관리
3. 성능 (TTFB / Core Web Vitals)
4. 가용성 (SLA / DR)
5. 확장성 (수평 / 캐싱)
6. 인프라 / 배포 (CI / IaC)
7. 접근성 (WCAG)

미충족 영역이 있으면 종료하지 않고 추가 질문.

## 작성 규칙

**FR 작성**:
1. 사용자 가치 / 업무 흐름 단위로 쪼개 `FR-001`부터 순차.
2. 한 카드에 하나의 행동 + 하나의 기대 결과.
3. `detail`에 최소 하나의 수용 기준(검증 방법) — "빠르게" 같은 모호한 표현 금지.
4. `group`은 대시보드의 `1.N` 섹션과 매칭.

**NFR 작성**:
1. 위 7개 영역으로 분류해 `NFR-001`부터 순차.
2. 가능하면 `detail`에 수치 목표 (예: "P95 ≤ 200ms").
3. 수치가 없으면 임시 기준 + 추후 측정 계획을 함께 기록.
4. `group`은 대시보드의 `2.N` 섹션과 매칭.

## 문서 반영 절차

1. 정의서의 확정 항목을 FR / NFR 카드로 변환.
2. `requirements/` 폴더에 개별 파일 생성 (기존 번호 이후 순차).
3. 중복 / 충돌 제거.
4. 새 group이나 섹션이 필요하면 대시보드 `.md`도 함께 갱신 (Dataview 쿼리 블록 복제).
5. 사용자에게 보고.

## 보고 형식

- 반영 완료 구간: FR 또는 NFR
- 신규 / 수정된 카드 ID 목록
- 추적 근거: 정의서의 어떤 항목에서 변환했는지 (US-N / [3] 핵심 기능 / [5] 제품 운영 / etc.)
- 사실(코드/문서 근거) vs 추정(인터뷰 필요) 표시
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- 모든 카드의 `id`, `description`, `detail`, `requirement_priority`가 비어 있지 않음
- FR / NFR 사이에 중복 / 상충 없음
- 각 요구사항이 테스트 또는 리뷰로 검증 가능
- `🚨 P0` 항목만으로 MVP 흐름이 성립
- 모든 카드 `tags`에 `requirement` 포함
- `group` 값이 대시보드 섹션과 매핑됨

## 종료 조건

- `requirements/` 폴더의 모든 카드가 YAML 스키마 준수
- 각 카드에 우선순위(`🚨 P0` / `⭐️ P1` / `🧩 P2` / `🛠️ P3`)가 들어감
- 정의서의 핵심 목표 / 범위 / 제약 / 성공 기준이 최소 1회 이상 FR 또는 NFR에 반영
- project_type별 NFR 7영역을 모두 커버 (위 체크리스트)
- 사용자와 미확정 항목 목록 합의

## 다음 액션 (완료 시 제안 — project_type 무관)

1. **`2-design-system`** 호출 — 시스템 설계서 (아키텍처 / 컴포넌트 / 흐름 / 추적성)
2. **`2-design-ui`** 호출 — UI 명세서 (화면 / 와이어프레임 / 접근성)
3. **`3-build-data`** 호출 — 데이터 명세서 (스키마 / 마이그레이션)
4. **`4-deploy-permission`** 호출 — 보안·권한 명세서
5. **`4-deploy-os`** 호출 — 플랫폼 통합 명세서

또는 **`ralph-docs`** 호출로 [3]~[10]까지 자동 캐스케이드.
