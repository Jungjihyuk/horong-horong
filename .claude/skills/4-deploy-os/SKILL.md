---
name: 4-deploy-os
description: 프로젝트의 플랫폼 통합 명세서(4. 배포 / 9. 플랫폼 통합 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web)에 따라 OS·기기·플랫폼 접점 표면이 다르다. desktop은 메뉴바·Dock·핫키·IME·알림·Spotlight·Login Item·URL Scheme, mobile은 푸시·딥링크·위젯·Live Activity·생체인증·공유, web은 인증 콜백·Webhook·결제·SSO를 빠짐없이 모은 단일 출처로 관리한다.
---

요구사항·UI·보안 권한 명세서를 입력으로 받아 플랫폼 접점 표면을 명세하고, 누락된 통합 지점이 없도록 종합 표를 1차 점검 기준으로 유지한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web`
- `sections_meta.9_platform_integration`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `4. 배포/9. 플랫폼 통합 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/배포/`)
  - `filenames`: 복사할 템플릿 파일들

**파일 합성 규칙**:
- 변형 파일명:
  - desktop: `OS 통합 명세서 v1.0-template-desktop.md`
  - mobile: `OS 통합 명세서 v1.0-template-mobile.md`
  - web: (변형 없음 — 직접 새 명세서로 시작 또는 desktop 변형을 참고)

## 입력 / 출력

**입력**:
- `{1_project_definition}/` — OS / 플랫폼 통합 표면 요약
- `{2_requirements}/` — 통합 NFR (응답 시간 / 충돌 정책 / 푸시 SLA 등)
- `{4_ui_spec}/` — 화면별 통합 표면 (메뉴바 / 푸시 카드 / 딥링크 진입점)
- `{8_permission_sandbox}/` — 권한 의존 (Accessibility / 알림 권한 / 위치 / OAuth)
- (브라운필드) 코드:
  - **desktop**: `*/MenuBar/`, `*App.swift`의 `MenuBarExtra`, `Info.plist`(LSUIElement, CFBundleURLTypes), HotKey 라이브러리, `UNUserNotificationCenter`, `SMAppService`, `NSPasteboard`
  - **mobile**: 푸시 토큰 등록, 딥링크 핸들러, 위젯 익스텐션, Live Activity, 생체인증 코드(Touch ID / Face ID / BiometricPrompt), 공유 / Action Extension
  - **web**: 인증 provider 콜백 라우트, Webhook 핸들러, OAuth state, 결제 callback, SSO 어설션

**출력 (반드시 갱신)**:
1. `{9_platform_integration}/플랫폼 통합 명세서 v{버전}.md` — 본 명세서
2. (선택) `{9_platform_integration}/global-hotkeys.md` — 전역 핫키 충돌 분석 (desktop)
3. (선택) `{9_platform_integration}/url-schemes.md` — 딥링크 / URL Scheme 핸들링 상세 (desktop / mobile)

## 운영 모드

### A. 그린필드
요구사항·UI에서 통합 표면 도출 → 종합 표 + 항목별 명세 채움.

### B. 브라운필드
실제 코드에서 통합 지점 추출 → 1:1 매핑.

## 공통 원칙 (모든 project_type)

- **종합 표가 1차 점검 기준** — 모든 통합 표면을 한 표에 모아 사용 / 미사용 / 상세 링크.
- **권한 의존을 명시** — 표면별 어떤 권한이 필요한지 (8_permission_sandbox와 정합).
- **충돌 / 우선순위 정책** — 전역 핫키 vs OS / 다른 앱 / 푸시 vs 인앱 알림 / 라우트 vs SSO 콜백.
- **사용자 변경 가능 여부 명시** — 단축키 / 알림 / 푸시 카테고리 등.

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

**필수 섹션**:
1. 메뉴바 (NSStatusItem) — 좌/우클릭 / 드롭 수신 / LSUIElement
2. Dock — 표시 정책 / 클릭 동작 / 배지
3. 단축키 — 전역 핫키 (매핑 / 사용자 변경 / 충돌 / Accessibility 권한)
4. 단축키 — 앱 내 (메뉴 매핑 / **한국어 IME 조합 중 가로채기 회피**)
5. 알림센터 (UNUserNotification) — 카테고리 / 액션 버튼 / Focus 모드
6. Spotlight / Core Spotlight — 인덱싱 대상 / 비활성 옵션
7. Login Item / SMAppService — 자동 시작 토글 / 등록·해제
8. URL Scheme / Universal Link — 스킴 / 호스트 / 경로 표 / 보안 검증
9. 드래그앤드롭 / 클립보드 (NSPasteboard) — 드롭 영역 / 데이터 유형
10. Services 메뉴 / Share Extension — 노출 항목 / Bundle ID 분리
11. AppleEvent / AppleScript — 자동화 인터페이스 (있으면)
12. **종합 표** — 모든 표면 1줄씩

### Mobile (`project_type === "mobile"`)

**필수 섹션**:
1. 푸시 알림 — APNs / FCM 토큰 등록 / 페이로드 / 카테고리·액션 / 권한 흐름
2. 딥링크 / Universal Link / App Link — 스킴 / 호스트 / 핸들러 / 미설치 폴백
3. 위젯 / Live Activity (iOS) / App Widget (Android) — 종류 / 데이터 갱신 / 인터랙션
4. 잠금화면 통합 — Live Activity / 위젯 표시 정책
5. 생체인증 — Touch ID / Face ID / BiometricPrompt — 트리거·대체 흐름
6. 단축어 / Siri Shortcuts / App Actions — 등록 인터페이스
7. 공유 / Action Extension — 진입 가능 데이터 / 호스트 앱
8. 외부 앱 호출 (URL Scheme / Intent) — 지도 / 결제 / 공유
9. 백그라운드 작업 / Wake — Background Tasks / WorkManager / 푸시 background
10. 광고 식별자 / 추적 — ATT / GAID
11. **종합 표** — 모든 표면 1줄씩

### Web (`project_type === "web"`)

**필수 섹션**:
1. 인증 콜백 라우트 — OAuth (Google / GitHub / Apple) / SAML / OIDC — provider별 redirect URI / state·PKCE
2. SSO / Federated — 어설션 검증 / 그룹 매핑 / Just-In-Time Provisioning
3. Webhook 수신 — provider별 서명 검증 / 멱등성 / 큐 / 재시도
4. 결제 — Stripe / Toss / 토스페이먼츠 / 인앱결제 — 콜백 / 영수증 / 환불 / 분쟁
5. 메일 / 알림 — SES / Sendgrid / Push API — 이벤트 수신·발송
6. 공유 / SEO — Open Graph / Twitter Card / structured data
7. CDN / 객체 스토리지 직접 호출 — Pre-signed URL / CORS / 보안 헤더
8. **종합 표** — 모든 통합 1줄씩

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.9_platform_integration`의 `path`, `template_path`, `filenames` 해석.
3. 요구사항·UI·보안 권한 명세서 읽기.
4. `{9_platform_integration}/플랫폼 통합 명세서 v{버전}.md`가 없으면 적합한 변형을 복사.
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**desktop**:
- 메뉴바 / Dock 사용 정책?
- 전역 핫키 매핑 / 충돌 정책?
- 한국어 IME 조합 중 단축키 가로채기 회피?
- 알림센터 / Login Item / URL Scheme 사용?

**mobile**:
- 푸시 / 딥링크 / 위젯 사용?
- 생체인증 사용? 대체 흐름?
- 외부 앱 호출 (지도 / 결제 / 공유)?
- 백그라운드 작업 / 위치?

**web**:
- OAuth provider 목록과 콜백 라우트?
- Webhook 수신 항목? 서명 검증?
- 결제 / SSO / SaaS 통합 항목?

## 보고 형식

- 반영 완료 영역 (각 통합 표면별)
- 새로 정의된 통합 / 충돌 정책 (사실 vs 추정)
- 권한 의존 (8_permission_sandbox와의 정합)
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- 종합 표가 모든 통합 표면을 1줄씩 다룸 (해당 없음 포함)
- 각 표면이 코드 위치 또는 "미사용" 명시
- 권한 의존이 8_permission_sandbox와 정합
- (desktop) 단축키 매핑에 한국어 IME 호환·충돌 정책 포함
- (mobile) 푸시 / 딥링크 권한 흐름과 미설치 폴백 정의됨
- (web) Webhook 서명 검증 / 멱등성 명시
- (desktop / mobile) URL Scheme / Deep Link 보안 검증(출처 / 파라미터)

## 종료 조건

- 종합 표 빈 행 없음
- 코드 스캔과 1:1 정합 (브라운필드)
- 8_permission_sandbox / 4_ui_spec과 정합

## 다음 액션 (완료 시 제안)

1. **`4-deploy-release`** 호출 — 자동 업데이트 / 푸시 인프라가 배포 채널과 정합
2. **`4-deploy-permission`** 갱신 — 통합 표면이 요구하는 권한 동기화
3. **`5-operate-schedule`** 호출 — 통합 작업 일정 등록
