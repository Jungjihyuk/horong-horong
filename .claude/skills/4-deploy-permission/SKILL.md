---
name: 4-deploy-permission
description: 프로젝트의 보안·권한 명세서(4. 배포 / 8. 보안·권한 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web)에 따라 권한 모델이 다르다. desktop은 App Sandbox·Hardened Runtime·entitlements·Privacy 키, mobile은 런타임 권한·privacy manifest, web은 인증·인가·CSRF·XSS·CORS·시크릿 관리를 단일 출처로 관리한다. 잘못된 권한 한 줄이 출시 자체를 막을 수 있으므로 1차 검증 항목이다.
---

요구사항·UI 명세서를 입력으로 받아 권한 / 보안 모델을 정의하고, 빌드 산출물(entitlements / Info.plist / privacy manifest / 환경 변수)과 명세서가 항상 일치하도록 단일 출처를 유지한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web`
- `sections_meta.8_permission_sandbox`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `4. 배포/8. 보안·권한 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/배포/`)
  - `filenames`: 복사할 템플릿 파일들

**파일 합성 규칙**:
- 변형 파일명:
  - desktop: `권한·샌드박스 명세서 v1.0-template-desktop.md`
  - mobile: `권한 명세서 v1.0-template-mobile.md`
  - web: `보안 명세서 v1.0-template-web.md`
- 파일이 없으면 가장 가까운 변형으로 시작하고 사용자에게 알린다.

## 입력 / 출력

**입력**:
- `{2_requirements}/` — 권한 / 보안 NFR (트리거·UX·거부 폴백·인증·인가)
- `{4_ui_spec}/` — 권한 요청 화면 / 거부 안내 / 인증 화면 흐름
- (있으면) `{9_platform_integration}/` — Login Items / 푸시 권한 / OAuth 콜백 등
- (브라운필드) 코드 / 빌드:
  - **desktop**: `*.entitlements`, `Info.plist`, `project.yml`(Hardened Runtime), 권한 사용 코드(`AVCaptureDevice`, `SCStream`, `AXIsProcessTrusted` 등)
  - **mobile**: iOS `Info.plist`(NS*UsageDescription) + privacy manifest, Android `AndroidManifest.xml` permissions, 런타임 권한 요청 코드
  - **web**: 인증 미들웨어, CORS / CSP 설정, 시크릿 매니페스트, OWASP 검토 결과

**출력 (반드시 갱신)**:
1. `{8_permission_sandbox}/보안·권한 명세서 v{버전}.md` — 본 명세서
2. (선택) `{8_permission_sandbox}/permission-flow.excalidraw.md` — 권한 요청 / 거부 / 인증 흐름

## 운영 모드

### A. 그린필드
요구사항·UI에서 권한 / 보안 항목 도출 → 표 / 정책 채움.

### B. 브라운필드
실제 빌드·코드에서 권한 추출:
- desktop: `*.entitlements` / `Info.plist` / `project.yml` 1:1 미러
- mobile: iOS `Info.plist` + privacy manifest, Android `AndroidManifest.xml`
- web: 미들웨어 / 헤더 / 환경 변수 / OAuth provider 설정

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

**필수 섹션**:
- **[1] App Sandbox** — 활성 / 비활성 결정 + 이유 + Notarization 영향
- **[2] Hardened Runtime** — 옵션별 채택 여부 + 이유 (allow-jit / disable-library-validation 등)
- **[3] Entitlements 표** — 채택 / 트리거 / 사용 코드 위치 / 비고 — `*.entitlements`와 1:1 정합
- **[4] 프라이버시 사용 설명** — `NS*UsageDescription` 한국어 문구와 트리거 — `Info.plist`와 1:1 정합
- **[5] 권한 요청 흐름·거부 폴백** — 요청 시점 / 거부 시 사용자 화면 / 기능 폴백
- **[6] Login Items / Background** — `SMAppService` 등록·해제, 사용자 동의
- **[7] Helper App / XPC** — 헬퍼 Bundle ID, 권한 분리 이유, 설치 / 갱신 / 제거 (있으면)
- **[8] Direct vs MAS 빌드 차이** — Sandbox 필수 여부, Login Items 방법, entitlements 차이

### Mobile (`project_type === "mobile"`)

**필수 섹션**:
- **[1] iOS Info.plist 프라이버시 키** — `NSCameraUsageDescription` / `NSLocationWhenInUseUsageDescription` 등 + 한국어 문구 + 트리거
- **[2] iOS Privacy Manifest** — `PrivacyInfo.xcprivacy` 의 reason API 사용 / 추적 / 데이터 수집 분류
- **[3] Android Permissions** — `AndroidManifest.xml` permissions + `<uses-feature>` + 보호 레벨(normal / dangerous / signature)
- **[4] 런타임 권한 요청 흐름** — 요청 시점 / 거부 시 UX / 영구 거부(Don't ask again) 폴백
- **[5] 백그라운드 / 위치 / 알림 권한** — 사용자 동의 흐름과 정상 동작
- **[6] 광고 식별자 / 추적** — App Tracking Transparency / Google Advertising ID
- **[7] 보안 저장** — Keychain / EncryptedSharedPreferences / Keystore
- **[8] 빌드 구성별 차이** — Debug / Release / Internal Testing 권한 차이

### Web (`project_type === "web"`)

**필수 섹션**:
- **[1] 인증 (AuthN)** — 세션 / JWT / OAuth / SSO / Passwordless / MFA 정책 + 토큰 만료·갱신·폐기
- **[2] 인가 (AuthZ)** — 역할 / 권한 매트릭스 (RBAC / ABAC), 라우트별 접근 제어
- **[3] OWASP Top 10 대응** — XSS / CSRF / SQLi / SSRF / IDOR 등 항목별 대응
- **[4] 헤더 / CORS / CSP** — `Content-Security-Policy` / `X-Frame-Options` / CORS 화이트리스트 / Cookie 속성(Secure / HttpOnly / SameSite)
- **[5] 시크릿 / 키 관리** — 환경별 격리(local / dev / staging / prod), KMS / Secret Manager, 회전 정책
- **[6] 데이터 분류 / 개인정보** — 민감 데이터 식별, 암호화(in transit / at rest), 보존 / 삭제 / GDPR·개인정보보호법
- **[7] 감사 / 로깅** — 인증 이벤트 / 권한 변경 / 데이터 접근 로깅, 보존 기간
- **[8] 의존성 / 취약점** — SBOM / 취약점 스캔 / 패치 정책

## 핵심 원칙

- **단일 출처는 빌드 산출물(entitlements / Info.plist / AndroidManifest / 미들웨어 설정 / 환경변수 매니페스트)** — 명세서는 그 미러.
- **권한 거부 시 폴백 UX를 항상 정의** — "권한 없으면 동작 안 함"으로 끝내지 않음.
- **민감 정보는 Keychain (desktop / mobile) 또는 KMS / Secret Manager (web)** — 평문 저장 금지.
- **App Sandbox 비활성 결정 / Hardened Runtime 옵션 약화는 항상 사유 기록** (감사 대비).
- **(web) 모든 인증 / 인가 결정은 서버에서** — 클라이언트 검증만으로는 부족.

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.8_permission_sandbox`의 `path`, `template_path`, `filenames` 해석.
3. 요구사항·UI·플랫폼 통합 명세서 읽기.
4. `{8_permission_sandbox}/보안·권한 명세서 v{버전}.md`가 없으면 적합한 변형을 복사.
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**desktop**:
- App Sandbox 활성? 비활성이라면 사유?
- Hardened Runtime 옵션 채택? 어떤 옵션과 사유?
- 필요 entitlements와 트리거 시점?
- 권한 거부 시 폴백 UX?
- Login Items / Helper App / XPC 사용?
- MAS vs Direct 차이?

**mobile**:
- iOS / Android에서 필요한 권한 (카메라 / 위치 / 마이크 / 알림 등)?
- 런타임 권한 요청 시점과 거부 시 폴백?
- iOS Privacy Manifest 작성 (reason API / tracking)?
- 광고 식별자 / 사용자 추적 사용?
- Keychain / Keystore 사용 항목?

**web**:
- 인증 방식 (세션 / JWT / OAuth / SSO)? MFA?
- 인가 매트릭스 (역할별 권한)?
- CORS / CSP / Cookie 속성 정책?
- 시크릿 보관 위치와 회전 정책?
- 민감 정보 분류와 보존 / 삭제 정책?
- 감사 로깅 범위?

## 보고 형식

- 반영 완료 영역 ([1]~[8] 중)
- 새로 정의된 권한 / 정책 (사실 vs 추정)
- 빌드 산출물(entitlements / Info.plist / 미들웨어)과의 정합 점검 결과
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- (desktop) entitlements / 프라이버시 키 표가 빌드 산출물과 1:1 일치
- (desktop) 모든 권한에 트리거 / 사용 코드 위치 / 거부 폴백 정의됨
- (desktop) App Sandbox / Hardened Runtime 결정에 사유 기록
- (mobile) iOS Privacy Manifest 작성, Android `AndroidManifest.xml`과 1:1 일치
- (mobile) 모든 런타임 권한에 거부 / 영구 거부 폴백 UX 정의
- (web) 인증·인가 매트릭스가 라우트와 1:1 매핑
- (web) OWASP Top 10 항목별 대응 명시
- (web) 시크릿 / 키의 환경별 격리 / 회전 정책 명시
- 민감 정보 보관 위치가 명시됨

## 종료 조건

- 영역 모두 채워짐 (해당 없음이면 명시)
- 빌드 산출물과 1:1 정합 (브라운필드)
- 권한 거부 / 인증 실패 / 토큰 만료 시 사용자 흐름이 모두 정의됨
- 감사 / 회전 / 변경 절차 명시

## 다음 액션 (완료 시 제안)

1. **`4-deploy-release`** 호출 — 서명·배포 채널과 정합 (entitlements ↔ Code Signing)
2. **`4-deploy-os`** 호출 — Login Items / 푸시 권한 등 OS·플랫폼 통합 표면
3. **`5-operate-schedule`** 호출 — 권한 / 보안 작업 일정 등록
