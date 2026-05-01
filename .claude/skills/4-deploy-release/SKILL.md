---
name: 4-deploy-release
description: 프로젝트의 배포 명세서(4. 배포 / 7. 배포 명세서)를 채우거나 갱신한다. docs-file.json의 project_type(desktop / mobile / web)에 따라 빌드·서명·공증·패키징·자동 업데이트·릴리스 체크리스트·롤백 절차를 단일 출처로 관리한다. desktop은 Code Signing·Notarization·DMG·Sparkle/MAS, mobile은 TestFlight·Play Store·OTA·강제 업데이트, web은 CI·컨테이너·canary·blue-green을 다룬다.
---

요구사항·시스템 설계·보안 권한 명세서를 입력으로 받아 배포 파이프라인을 명세하고, 릴리스가 깨지지 않도록 절차·키 관리·자동화 스크립트 위치를 단일 출처로 보관한다.

## 경로 해석 및 project_type 판정

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `project_type`: `desktop` / `mobile` / `web`
- `sections_meta.7_release`: 이 섹션의 메타
  - `path`: 명세서가 들어갈 위치 (예: `4. 배포/7. 배포 명세서/`)
  - `template_path`: 템플릿 원본 위치 (예: `0. 템플릿/배포/`)
  - `filenames`: 복사할 템플릿 파일들

**파일 합성 규칙**:
- 기본: `docs_root + template_path + filename.replace("{project_type}", project_type)`
- 변형 파일명:
  - desktop: `배포·서명·공증 명세서 v1.0-template-desktop.md`
  - mobile: `배포 명세서 v1.0-template-mobile.md`
  - web: `배포 명세서 v1.0-template-web.md`
- 파일이 없으면 가장 가까운 변형(desktop 우선)으로 시작하고 사용자에게 알린다.

## 입력 / 출력

**입력**:
- `{1_project_definition}/` — 배포 채널 결정 (Direct DMG / MAS / TestFlight / Play Store / Web 호스팅)
- `{2_requirements}/` — 배포 NFR (Notarization 통과율, 업데이트 SLA, 롤백 시간, 가용성)
- `{8_permission_sandbox}/` — 서명·entitlements (desktop) 또는 권한 / 보안 정책 (직접 영향)
- `{9_platform_integration}/` — 자동 업데이트 / 푸시 / Webhook 등 통합 표면
- (브라운필드) 코드 / 인프라:
  - **desktop**: `scripts/build_dmg.*`, `scripts/notarize.*`, `.github/workflows/release*.yml`, `project.yml`(XcodeGen) / `Info.plist`
  - **mobile**: `fastlane/`, `scripts/`, App Store Connect / Play Console 설정, OTA 도구(CodePush / EAS)
  - **web**: `Dockerfile`, `docker-compose.yml`, IaC (Terraform / Pulumi), CI(`.github/workflows/`), 배포 도구(K8s manifests / Vercel / Cloudflare)

**출력 (반드시 갱신)**:
1. `{7_release}/배포 명세서 v{버전}.md` — 본 명세서
2. (선택) `{7_release}/release-checklist.md` — 매 릴리스마다 체크할 항목
3. (선택) `{7_release}/runbook-rollback.md` — 롤백 런북

## 운영 모드

### A. 그린필드
정의서 + 요구사항으로 배포 채널 결정 → 흐름·키·체크리스트·롤백 절차 채움.

### B. 브라운필드
실제 빌드·릴리스 흐름 추출 → 명세서로 정리.

## 공통 구조 (모든 project_type)

명세서는 다음 영역을 다룬다.

- **[1] 빌드 환경 / 구성 표** — Debug / Release / 채널별 / 환경별 (project_type별 컬럼 다름)
- **[2] 서명·인증 키 관리** — 키 종류 / 보관 위치 / 만료 / 갱신·폐기 절차
- **[3] 패키징 / 아티팩트** — 결과물 형식과 도구
- **[4] 배포 파이프라인** — git push → CI → 빌드 → 검증 → 배포 흐름 (코드블록 또는 다이어그램)
- **[5] 자동 업데이트 / 강제 업데이트** — 채널 / 정책 / 강제 업데이트 트리거
- **[6] 릴리스 체크리스트** — 버전 bump / 릴리스 노트 / 태그 / 검증 / 알림
- **[7] 롤백 절차** — 단계별 명령 / 의사결정 트리 / 인시던트 기록
- **[8] 텔레메트리 / 크래시 리포트** — 수집 도구 / 항목 / 사용자 동의 흐름
- **[9] 모니터링 / 알람** — 배포 후 지표 (성공률 / 충돌률 / 응답시간 / SLA)

## project_type 별 분기

### Desktop (`project_type === "desktop"`)

- **[1] 빌드 채널**: Debug / Release Direct(DMG) / Release MAS / TestFlight (iOS 확장 시) — Bundle ID·서명·자동 업데이트·entitlements 차이
- **[2] 서명 ID**: Developer ID Application / Mac App Store / Mac Developer / Apple Distribution. Team ID + 키체인·CI 시크릿 보관
- **[3] 패키징**: DMG (create-dmg) / PKG (pkgbuild) / ZIP, Applications 심볼릭 링크 / 배경 이미지 / 아이콘
- **[4] 파이프라인**: `archive` → `exportArchive` → `notarytool submit --wait` → `stapler staple` → `spctl` 검증 → 채널 업로드
- **[5] 자동 업데이트**: Sparkle (Direct) appcast.xml + EdDSA 서명 키 / MAS 자동 / 채널 분리(stable·beta)
- **모든 릴리스는 Notarization 통과 필수** (실패 시 자동 차단)

### Mobile (`project_type === "mobile"`)

- **[1] 빌드 채널**: Internal / TestFlight (iOS) / Internal Testing / Closed Testing / Open Testing / Production (Android)
- **[2] 서명**: iOS Distribution Certificate + Provisioning Profile / Android Keystore (보관 위치 + CI 시크릿)
- **[3] 패키징**: IPA / AAB / APK
- **[4] 파이프라인**: fastlane 또는 CI 워크플로 → 스토어 업로드 → 심사 → 단계별 출시
- **[5] 자동 업데이트**: 스토어 자동 업데이트 + OTA(RN: CodePush / EAS Update — JS 번들만 갱신) + 강제 업데이트 (서버 minVersion 체크)
- **App Store / Google Play 심사 정책 정합성** (광고 식별자, 백그라운드 사용 등)

### Web (`project_type === "web"`)

- **[1] 환경**: local / dev / staging / prod (시크릿 격리)
- **[2] 인증·시크릿 관리**: 환경 변수 / KMS / Secret Manager — 키 회전 정책
- **[3] 패키징**: Docker 이미지 / Lambda 함수 / 정적 자산 (CDN 업로드)
- **[4] 파이프라인**: git push → CI(lint/test/build) → 컨테이너 빌드 → 레지스트리 → 배포(K8s / Serverless / Vercel) → 트래픽 점진 전환(canary / blue-green)
- **[5] 자동 업데이트**: 무중단 배포 / 트래픽 비율 점진 증가 / 자동 롤백 트리거
- **DB 마이그레이션은 5_data_spec과 정합** (배포 순서: 마이그레이션 먼저 → 앱 배포)

## 핵심 원칙

- **단일 출처 키 / 시크릿** — 분산 금지. 키체인 / Secret Manager / KMS 한 곳.
- **롤백 절차 출시 전 1회 이상 리허설**.
- **데이터·앱 배포 순서 정합** — DB 마이그레이션 / 자산 업로드 → 앱 배포.
- **모든 채널은 자동 검증** (signing / store 심사 / 헬스체크).
- **시크릿은 코드 / 문서에 절대 평문으로 두지 않음**.

## 시작 절차

1. `.claude/docs-file.json`을 로드하고 `project_type` 결정.
2. `sections_meta.7_release`의 `path`, `template_path`, `filenames` 해석.
3. 정의서·요구사항·보안 권한·플랫폼 통합 명세서 읽기.
4. `{7_release}/배포 명세서 v{버전}.md`가 없으면 적합한 변형을 복사.
5. 운영 모드(A/B) 판정 후 입력 수집.

## 인터뷰 질문 세트

**공통**:
- 배포 채널은? (단일 / 복수 — 예: Direct DMG + MAS / TestFlight + Production)
- 시크릿 / 키 보관 위치와 회전 정책?
- 릴리스 체크리스트의 필수 단계?
- 롤백 결정권자와 절차?
- 텔레메트리 / 크래시 리포트 도구?

**desktop 추가**:
- Notarization 자동화 스크립트 / CI?
- Sparkle EdDSA 키 보관 위치?
- stable / beta 채널 분리?
- MAS Receipt 검증?

**mobile 추가**:
- 단계별 출시 (10% → 50% → 100%) 사용?
- OTA 도구 사용? JS 번들만 vs 네이티브 코드 동시 업데이트?
- 강제 업데이트 정책 (서버 minVersion)?

**web 추가**:
- 무중단 배포 (canary / blue-green / rolling)?
- DB 마이그레이션은 무중단? 백워드 호환 정책?
- 자동 롤백 트리거 (에러율 / 응답시간 임계치)?

## 보고 형식

- 반영 완료 영역 ([1]~[9] 중)
- 새로 정의된 채널 / 키 / 자동화 항목 (사실 vs 추정)
- 누락된 항목 (체크리스트 빈 칸 / 롤백 미정 등)
- 미확정 항목과 다음 질문 (최대 3개)

## 품질 체크리스트

- [1] 빌드 채널 / 환경 표 채워짐
- [2] 모든 키 / 시크릿의 보관 위치 명시 (분산 0건)
- [4] 파이프라인이 자동화 가능한 단위로 분해됨
- [5] 자동 업데이트 / 강제 업데이트 정책 명시
- [6] 릴리스 체크리스트가 체크박스 단위로 검증 가능
- [7] 롤백 절차가 단계별로 명시 + 의사결정 트리 포함
- [8] 텔레메트리 / 크래시 리포트의 사용자 동의 흐름 명시
- (desktop) 모든 빌드가 Notarization 통과를 자동 검증
- (mobile) 스토어 심사 정책 정합 확인됨
- (web) DB 마이그레이션 순서가 데이터 명세서와 정합

## 종료 조건

- [1]~[9] 영역 채워짐 (해당 없음이면 명시)
- 서명 ID / 시크릿 표가 실제 보관 위치와 일치 (브라운필드)
- 자동화 스크립트 / CI 워크플로가 실행 가능 (1회 이상 검증)
- 롤백 절차가 리허설 가능한 형태로 작성됨
- 채널 / 환경별 차이 명시됨

## 다음 액션 (완료 시 제안)

1. **`4-deploy-permission`** 호출 — 권한 / entitlements / Privacy 키 / 인증·인가 정책 (서명과 직접 연결)
2. **`4-deploy-os`** 호출 — OS·플랫폼 통합 (자동 업데이트와 정합)
3. **`5-operate-schedule`** 호출 — 릴리스 일정 / 마일스톤 등록
4. **`5-operate-study`** — 인시던트 / 롤백 사례를 운영 런북에 누적
