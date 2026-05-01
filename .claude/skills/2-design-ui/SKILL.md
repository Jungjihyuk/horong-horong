---
name: 2-design-ui
description: 프로젝트의 UI 명세서(2. 설계 / 4. UI 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web) 또는 정의서·요구사항 명세서의 단서를 보고 적합한 템플릿(UI 명세서 v1.0-template-{project_type}.md)을 선택해 작성한다. 화면 단위 와이어프레임 + 컴포넌트/동작 테이블 + 디자인 시스템 + project_type별 핵심 관심사(desktop: 메뉴바·단축키·IME / mobile: 제스처·네비·푸시 / web: 반응형·접근성·SEO)를 한 자리에 명세한다.
---

요구사항 명세서를 기반으로 UI 명세서를 작성하고, 합의된 내용을 문서에 즉시 반영한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web` 중 하나
- `sections_meta.4_ui_spec`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `2. 설계/4. UI 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/설계/`)
  - `filenames`: 복사할 템플릿 파일들 (예: `UI 명세서 v1.0-template-{project_type}.md`)

**project_type 결정 절차**:
1. `docs-file.json`의 `project_type`이 명시되어 있으면 그 값을 사용.
2. 없거나 모호하면 `1-plan-project-def`/`1-plan-requirements`/`2-design-system`이 이미 결정한 값을 따른다.
3. 추가 단서:
   - 데스크톱: 메뉴바 / Dock / 글로벌 단축키 / 한국어 IME 조합 / 윈도우 사이즈 정책
   - 모바일: 제스처(스와이프 / 핀치) / 네비게이션(탭바 / 드로어 / 모달) / 푸시 카드 / 다이내믹 아일랜드 / 위젯
   - 웹: 반응형 브레이크포인트 / SSR 초기 페인트 / SEO 메타 / 접근성(WCAG) / 키보드 내비게이션

**파일 합성 규칙**:
- 템플릿 원본: `docs_root + template_path + filename.replace("{project_type}", project_type)` → 예: `./docs/0. 템플릿/설계/UI 명세서 v1.0-template-desktop.md`
- 배치 위치: `docs_root + sections_meta.4_ui_spec.path`

> **주의**: 현재 `0. 템플릿/설계/`에 desktop 변형만 존재. mobile / web 변형은 없으면 desktop 변형을 베이스로 시작하고 사용자에게 알린다.

## 입력 / 출력

**입력**:
- `{1_project_definition}/프로젝트 정의서 v{버전}.md` — 사용자 시나리오, 핵심 기능, 제품 운영
- `{2_requirements}/요구사항 명세서 v{버전}.md` + `{2_requirements}/requirements/FR-*.md` — 화면 단위로 매핑할 FR
- (있으면) `{2_requirements}/requirements/NFR-*.md` 중 접근성·성능 NFR
- (선택) `[[UX 인사이트]]` 같은 사전 리서치 문서

**출력 (반드시 갱신)**:
1. `{4_ui_spec}/UI 명세서 v{버전}.md` — 메인 명세서 (디자인 시스템 + 화면별 명세 + OS·플랫폼 통합)
2. `{4_ui_spec}/wireframe.excalidraw.md` (선택) — 와이어프레임 Excalidraw
3. `{4_ui_spec}/screens/SCR-*.md` (선택) — 화면이 많으면 개별 화면 카드로 분리

## 운영 모드

### A. 그린필드
요구사항·시나리오에서 화면 목록을 도출 → 와이어프레임 + 컴포넌트 테이블 + 상태 정의 채움.

### B. 브라운필드
실제 View 코드에서 화면 추출:
- **desktop (Swift)**: `*View.swift` / `*Window.swift` / `*Popover.swift` / `MenuBarExtra` 콘텐츠
- **mobile (Swift / Kotlin / RN / Flutter)**: 화면 컴포넌트 (Screen / Page / Fragment), 네비게이션 라우트
- **web**: `pages/` 또는 `app/` 라우트, 주요 컴포넌트, 모달

각 View → 화면 카드(SCR-N) → FR-NNN 추적성 매핑.

## 공통 구조 (모든 project_type)

UI 명세서는 다음 4개 영역을 다룬다 (project_type별 [3] 섹션 명칭이 다름).

- **[1] 디자인 시스템**
  - 1.1 디자인 스택 — UI 프레임워크 / 디자인 가이드 / 아이콘 / 타이포 / 컬러
  - 1.2 공유 컴포넌트 — Button / TextField / Toggle / Picker / Sheet / Popover / ... (project_type별 기반 명시)
  - 1.3 디자인 토큰 — Colors / Spacing / Typography 단일 출처
- **[2] 화면별 UI 명세** — 화면마다 *와이어프레임(ASCII 또는 Excalidraw) + 컴포넌트/동작 테이블 + 상태 관리(빈 / 로딩 / 에러 / 성공) + 관련 FR/US-N*
- **[3] 플랫폼 / OS 통합** — project_type별 분기 (아래)
- **[4] 윈도우 / 화면 사이즈 정책** — project_type별 분기 (아래)

각 화면 행에 `근거(FR-NNN / US-N)` 컬럼 필수.

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

- **[3] OS 통합** (macOS 우선)
  - 메뉴바(NSStatusItem) / Dock(LSUIElement) / 시스템 트레이 동작
  - 전역 핫키 vs 앱 내 단축키 (충돌 정책 + 한국어 IME 조합 중 동작)
  - 알림센터(UNUserNotification) / Spotlight / Login Item
  - 다크/라이트/액센트 컬러 자동 대응 (Asset Catalog)
  - 접근성: VoiceOver 라벨/힌트, Dynamic Type, 키보드 내비게이션 순서, 색대비 4.5:1
  - 한국어 IME 호환: 조합 중 confirm/cancel(Esc/Enter) UX
- **[4] 윈도우 사이즈 정책**
  - 윈도우 종류별 최소/기본/최대 사이즈
  - 풀스크린 / 멀티 디스플레이 / Retina 자산 규격

### Mobile (`project_type === "mobile"`)

- **[3] 플랫폼 통합** (iOS / Android)
  - 네비게이션 패턴: TabBar / NavigationStack / Drawer / 모달 시트
  - 제스처: 스와이프 백 / 풀투리프레시 / 핀치 줌 / 길게 누르기
  - 푸시 알림 카드 디자인, 인앱 / 로컬 알림
  - 다이내믹 아일랜드 / Live Activity (iOS) / 알림 스타일 (Android)
  - 위젯 / 잠금화면 / 시스템 셰어 시트
  - 다크모드, 시스템 폰트 사이즈, VoiceOver / TalkBack 라벨
- **[4] 화면 사이즈 정책**
  - Safe Area 처리 (노치 / 다이내믹 아일랜드)
  - 디바이스 사이즈 클래스 (compact / regular)
  - 화면 회전 정책

### Web (`project_type === "web"`)

- **[3] 반응형 / 접근성**
  - 브레이크포인트 (mobile / tablet / desktop / wide)
  - 키보드 내비게이션 (Tab / Shift+Tab / 단축키)
  - 접근성 WCAG 2.1 AA 준수 (alt 텍스트 / aria 레이블 / 색대비)
  - SEO 메타 (title / description / OG / structured data)
  - SSR 초기 페인트 / 스켈레톤 / 로딩 상태
  - 다크모드 (시스템 / 수동 토글)
- **[4] 페이지 / 레이아웃 정책**
  - 라우트 구조와 네스티드 레이아웃
  - 모달 / 다이얼로그 / 토스트 위치
  - 인쇄 / 공유 / OG 이미지 정책

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.4_ui_spec`의 `path`, `template_path`, `filenames`를 해석.
3. 정의서 + 요구사항 명세서(특히 `requirements/FR-*.md`) 읽기 — 화면이 필요한 기능 추림.
4. `{4_ui_spec}/UI 명세서 v{버전}.md`가 없으면 `template_path`의 `UI 명세서 v1.0-template-{project_type}.md`를 복사. (변형이 없으면 desktop 변형을 베이스로 시작 + 사용자에게 알림)
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**공통**:
- 핵심 화면 5~10개를 우선순위별로 나열하면?
- 각 화면의 진입 / 주요 액션 / 결과 / 빈·로딩·에러 상태?
- 디자인 시스템 — 컴포넌트 라이브러리 사용? 자체 제작? 디자인 토큰 보관 위치?
- 다크/라이트 모드, 접근성 범위(VoiceOver / 키보드 내비)?

**desktop 추가**:
- 메뉴바 / Dock 동작? LSUIElement 여부?
- 전역 핫키 등록? 앱 내 단축키 매핑?
- 한국어 IME 조합 중 Enter/Esc 처리?
- 윈도우 사이즈 정책 (최소/기본/최대, 멀티 디스플레이)?

**mobile 추가**:
- 네비 패턴 (TabBar / Drawer / Stack)?
- 푸시 알림 디자인? 다이내믹 아일랜드 / Live Activity?
- 제스처 정책 (스와이프 백 등)?
- Safe Area / 노치 / 화면 회전?

**web 추가**:
- 브레이크포인트 (모바일 / 태블릿 / 데스크톱)?
- SSR / SPA / 하이브리드?
- 인증 / 로그인 페이지 흐름?
- SEO 메타 / OG 이미지 / 구조화 데이터?

## 작성 규칙

- **러프 우선**. 픽셀 디자인이 아니라 화면 구조 / 주요 컴포넌트 / 핵심 흐름을 먼저.
- **추적성 유지**. 화면마다 관련 `FR-NNN` / `US-N` 명시.
- **공유 컴포넌트는 [1]에서 한 번만 정의**. 각 화면은 컴포넌트 명만 참조.
- **상태 정의 필수**. 빈 / 로딩 / 에러 / 권한 거부 / 오프라인 등 엣지 케이스 UI를 누락하지 않는다.
- **시스템 설계서와 정합**. 화면 컴포넌트의 `동작` 컬럼에 호출하는 Manager/Service 메서드를 적어 `2-design-system`과 일치시킴.

## 보고 형식

- 반영 완료 영역 ([1]~[4] 중)
- 새로 정의된 화면 / 컴포넌트 (사실 vs 추정 표시)
- 미반영 FR-NNN 목록 (어떤 요구가 아직 화면으로 안 닿았는지)
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- [1] 디자인 토큰(Colors / Spacing / Typography)이 단일 출처로 정의됨
- [1] 공유 컴포넌트가 정의되고 화면 명세에서 재사용됨
- [2] 모든 화면에 와이어프레임 + 컴포넌트 테이블 + 상태 정의 + `근거(FR-NNN)` 있음
- [2] 빈 / 로딩 / 에러 / 권한 거부 / 오프라인 상태 UI 정의됨
- [3] project_type별 통합 영역 모두 작성 (desktop: 메뉴바·핫키·IME / mobile: 네비·푸시·제스처 / web: 반응형·SEO·접근성)
- [4] 사이즈 정책 명시
- 모든 FR이 [2] 화면 목록 어딘가에 닿음 (빈 FR 없음)

## 종료 조건

- [1] 디자인 시스템, [2] 화면별 명세, [3] 플랫폼 통합, [4] 사이즈 정책 모두 채워짐
- 화면 ↔ FR / US-N 추적성 매트릭스에 빈칸 없음
- 시스템 설계서 [2.1] View 계층과 화면 목록이 일치
- (desktop) 한국어 IME 조합 중 Enter/Esc 처리 정책이 모든 입력 컴포넌트별로 명시됨
- (desktop) 단축키 충돌 정책이 표로 정리됨
- (mobile) Safe Area 처리 / 화면 회전 정책 명시
- (web) 브레이크포인트별 레이아웃 차이 명시 + WCAG 2.1 AA 체크

## 다음 액션 (완료 시 제안)

1. **`2-design-system`** 갱신 — 새 화면이 추가됐다면 [2.1] View 계층 표 동기화
2. **`3-build-data`** 호출 — 화면이 사용하는 데이터 스키마 확정
3. **`3-build-integration`** 호출 — 외부 연동이 필요한 화면 / 컴포넌트가 있다면 (조건부)
4. **`4-deploy-permission`** 호출 — 권한 요청 UI(Privacy 키 한국어 문구 등) 명세
5. **`4-deploy-os`** 호출 — (desktop / mobile) OS 통합 표면 상세 명세
