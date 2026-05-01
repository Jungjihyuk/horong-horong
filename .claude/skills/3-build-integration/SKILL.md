---
name: 3-build-integration
description: 프로젝트의 연동·인터페이스 명세서(3. 구현 / 6. 연동·인터페이스 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web)에 따라 외부 인터페이스 종류와 명세 방식이 다르다. desktop은 HTTP API · OAuth · URL Scheme · AppleEvent · XPC · sidecar 프로세스 · 파일 포맷을, mobile은 푸시·딥링크·외부 SDK·OAuth·결제·웹뷰 브릿지를, web은 외부 HTTP API · Webhook · OAuth · 결제 · 메일 · 파일 스토리지 SDK를 단일 출처(JSON Schema 등)로 관리한다. 외부 연동이 전혀 없는 프로젝트는 비활성 처리한다.
---

요구사항 명세서·시스템 설계서·데이터 명세서를 입력으로 받아 외부 인터페이스 계약을 정의하고, 양쪽 코드(클라이언트·외부) 사용 지점과 동시에 검증한다.

## 활성화 조건 (conditional 섹션)

이 스킬은 프로젝트에 다음 중 하나 이상이 존재할 때만 사용한다.

**공통**:
- 외부 HTTP API 호출 (REST / GraphQL / RPC / RSS / Webhook)
- OAuth / OIDC / SSO / 토큰 흐름
- 파일 포맷 입출력 (JSON / OPML / CSV / 사진·영상 / 인증 자격증명 등)
- 외부 SDK (결제 / 분석 / 인증 / 메일 / 푸시 / 객체 스토리지)

**desktop 전용**:
- URL Scheme / Universal Link
- AppleEvent / XPC / 헬퍼 앱 IPC
- Sidecar 프로세스 (Python / Node / CLI 동봉)

**mobile 전용**:
- 푸시(APNs / FCM) / 딥링크 / 위젯 익스텐션 IPC
- 웹뷰 ↔ 네이티브 브릿지 (postMessage / JSBridge)
- 외부 앱 호출 (URL Scheme / Intent)

**web 전용**:
- Webhook 수신
- 메일 / SMS / 결제 / 인증 등 SaaS SDK
- CDN / 객체 스토리지 (S3 / GCS / R2) 직접 호출

해당 없으면 `.claude/docs-file.json`의 `sections_meta.6_integration_interface.conditional`이 활성이 아닐 가능성이 크다. 사용자에게 *"외부 연동이 없어 보입니다 — 명세서 작성을 건너뛸까요?"*로 확인.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web`
- `sections_meta.6_integration_interface`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `3. 구현/6. 연동·인터페이스 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/구현/`)
  - `filenames`: 복사할 템플릿 파일들

**파일 합성 규칙**:
- 템플릿 원본: `docs_root + template_path + filename.replace("{project_type}", project_type)`
- 배치 위치: `docs_root + sections_meta.6_integration_interface.path`

> **주의**: 현재 `0. 템플릿/구현/`에 desktop 변형(`연동 계약 명세서 v1.0-template-desktop.md`)만 존재. mobile / web 변형이 없으면 desktop 변형을 베이스로 시작하고 사용자에게 알린다.

## 입력 / 출력

**입력**:
- `{2_requirements}/` — 외부 의존성 NFR (응답 시간 / 가용성 / 인증 / 토큰 저장)
- `{3_system_design}/` — Sidecar / 외부 호출 아키텍처
- `{5_data_spec}/` — 페이로드와 스키마 정합 (외부에서 받은 데이터가 로컬 스토어에 어떻게 떨어지는가)
- (브라운필드) 코드:
  - **공통**: `URL` / `URLSession` / HTTP 클라이언트, JSON Schema 파일
  - **desktop**: `Process()` (sidecar), `Info.plist`의 `CFBundleURLTypes`(URL Scheme), `Shared/*/.schema.json`
  - **mobile**: 푸시 토큰 등록, 딥링크 핸들러, 웹뷰 브릿지 메시지
  - **web**: API 라우트의 외부 호출, Webhook 핸들러, SaaS SDK 초기화

**출력 (반드시 갱신)**:
1. `{6_integration_interface}/연동·인터페이스 명세서 v{버전}.md` — 카탈로그 + 운영 정책
2. `{6_integration_interface}/integrations/INT-XXX.md` — 개별 연동 카드
3. `{6_integration_interface}/schemas/INT-XXX.schema.json` — JSON Schema (또는 OpenAPI / Protobuf 등 등가 계약)

## 운영 모드

### A. 그린필드
요구사항 + 시스템 설계에서 외부 호출 항목 추출 → 각 항목에 INT-NNN 카드 생성.

### B. 브라운필드
코드 스캔으로 외부 호출 지점 추출:
- URL/도메인 grep
- HTTP 클라이언트 사용처
- Sidecar 시작 코드 (desktop)
- URL Scheme / Intent 핸들러 (desktop / mobile)
- 푸시 / 딥링크 핸들러 (mobile)
- Webhook 라우트 / SaaS SDK 호출 (web)
- JSON Schema / OpenAPI / Protobuf 파일 인덱스

추출 결과를 INT-NNN 카드와 1:1 매핑.

## 개별 연동 카드 형식 (YAML frontmatter)

```yaml
---
id: INT-001
name: (짧은 이름)
type: http | oauth | url-scheme | apple-event | xpc | sidecar | file | webhook | sdk | bridge
trigger: app-launch | user-action | schedule | os-event | webhook-receive
auth: none | api-key | oauth | mtls | jwt | session
schema: ./schemas/INT-001.schema.json
owner: (담당)
status: active | deprecated | proposed
project_type_scope: desktop | mobile | web | any
---
```

본문: 호출 경로/채널 → 요청·응답 스키마 → 인증·토큰 저장 → 에러 매핑 → 재시도/백오프 → 버전 관리.

## 공통 구조 (모든 project_type)

명세서는 다음 영역을 다룬다.

- **[1] 카탈로그** — 모든 INT-NNN 일람 표 (`ID | 이름 | type | trigger | 연동 대상 | 상태 | 근거(FR-NNN)`)
- **[2] 단일 출처 (JSON Schema 등)** — 계약 파일 위치 + 양쪽 코드 사용 지점 표
- **[3] 인증·토큰 저장 정책** — `auth` 종류별 보관 위치 (Keychain / 암호화 / KMS), 만료·갱신·폐기
- **[4] 에러 매핑** — 외부 에러 → 도메인 에러 → 사용자 노출 메시지 표
- **[5] 재시도 / 백오프 / 타임아웃** — 지수 백오프, 한계 시간, 회로 차단기
- **[6] 버전 관리 / 호환성** — 계약 변경 시 양쪽 코드 동시 갱신 절차, deprecated 항목 처리
- **[7] 모니터링·관측** — 호출 빈도·실패율·지연시간 메트릭 (project_type별 도구)
- **[8] project_type 별 추가 영역** (아래 분기)

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

- **[8.1] Sidecar 프로세스** — 실행 주체, IPC 채널, 종료 / 재시작 / 장애 시 사용자 영향, 헬스체크
- **[8.2] URL Scheme / Universal Link** — 등록 방식, 인커밍 핸들러, 충돌 정책
- **[8.3] AppleEvent / XPC** — 권한, 헬퍼 앱, 메시지 형식
- **단일 출처 강조**: Swift ↔ Python 등 양쪽이 같은 `.schema.json`을 참조 (예: `Shared/*/Contracts/`)

### Mobile (`project_type === "mobile"`)

- **[8.1] 푸시 알림** — APNs / FCM 토큰 등록·관리, 페이로드 스키마, 사용자 권한 흐름
- **[8.2] 딥링크 / Universal Link / App Link** — 핸들러 우선순위, 미설치 시 폴백
- **[8.3] 웹뷰 ↔ 네이티브 브릿지** — postMessage / JSBridge 메시지 종류와 스키마
- **[8.4] 외부 앱 호출** — URL Scheme / Intent로 다른 앱 호출 (지도·결제·공유)

### Web (`project_type === "web"`)

- **[8.1] Webhook 수신** — 서명 검증, 멱등성, 재시도 정책, 큐
- **[8.2] OAuth / SSO** — provider별(Google / GitHub / SAML) 콜백 라우트, state·PKCE
- **[8.3] SaaS SDK** — 결제(Stripe / Toss) / 메일(SES / Sendgrid) / 분석 / 푸시 / 인증 SaaS
- **[8.4] CDN / 객체 스토리지 직접 호출** — Pre-signed URL, CORS, 보안 헤더

## 핵심 원칙

- **단일 출처(JSON Schema 등 계약 파일)** — 양쪽 코드가 같은 파일 참조. 계약 변경은 양쪽 동시 갱신(단일 PR).
- **토큰 / 시크릿은 Keychain (desktop / mobile) 또는 환경변수 + KMS (web)** — 평문 저장 금지.
- **에러 매핑은 사용자 노출 메시지까지** — 외부 에러를 그대로 노출하지 않음.
- **타임아웃과 회로 차단기**를 항상 정의 — 외부 의존이 죽었을 때 사용자가 멈추지 않게.
- **Sidecar / Webhook는 헬스체크·재시작·장애 영향**을 반드시 명세.

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.6_integration_interface.conditional`이 활성인지 확인. 비활성이면 사용자에게 확인.
3. `sections_meta.6_integration_interface`의 `path`, `template_path`, `filenames` 해석.
4. 요구사항·시스템 설계·데이터 명세서 읽기 — 외부 호출 지점 인덱싱.
5. `{6_integration_interface}/연동·인터페이스 명세서 v{버전}.md`가 없으면 `template_path`의 `연동 계약 명세서 v1.0-template-{project_type}.md`(없으면 desktop)를 복사.
6. 운영 모드(A/B) 판정 후 입력 수집.

## 보고 형식

- 반영 완료 영역 ([1]~[8] 중)
- 새로 추가/갱신된 INT-NNN 카드 목록
- JSON Schema 갱신 시 양쪽 코드 사용 지점 목록 (Swift / Python / Web 등)
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- 모든 외부 연동에 INT-NNN 카드가 있고 카탈로그에 등록됨
- 각 카드에 JSON Schema (또는 등가 계약) 첨부
- 인증 토큰 저장 위치 명시 (Keychain / KMS / 시크릿 매니저)
- 에러 매핑 표 채워짐 (외부 에러 → 사용자 메시지)
- 재시도 / 백오프 / 타임아웃 정책 명시
- (desktop) Sidecar 항목은 종료 / 재시작 / 장애 영향 명시
- (mobile) 푸시 권한 흐름 + 딥링크 미설치 폴백 명시
- (web) Webhook 서명 검증 / 멱등성 정책 명시
- 카탈로그가 코드 스캔 결과와 일치 (누락 0건)

## 종료 조건

- [1]~[8] 영역 채워짐 (해당 없음이면 명시)
- 모든 외부 호출 지점이 카탈로그에 등록됨 (브라운필드)
- 단일 출처 JSON Schema와 양쪽 코드가 정합
- 인증·재시도·에러 매핑이 모든 카드에 작성됨

## 다음 액션 (완료 시 제안)

1. **`2-design-system`** 갱신 — [2.4] OS 통합/Sidecar 또는 외부 연동 표 동기화
2. **`4-deploy-permission`** 호출 — 외부 호출에 필요한 권한 / 시크릿 정책
3. **`5-operate-schedule`** 호출 — 연동 작업 일정 + 외부 의존성 모니터링 일정
