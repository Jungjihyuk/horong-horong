---
name: ralph-docs
description: 프로젝트 정의서 → 개발 진행 관리(10번 섹션)까지 자동 채우는 오케스트레이터. 그린필드(코드 없음)는 `1-plan-project-def`에서 ralph 루프(verification 통과까지 반복)로 기획을 구체화한 뒤 캐스케이드, 브라운필드(코드 있음)는 `code_mappings` 기반으로 코드를 읽어 캐스케이드. project_type(desktop / mobile / web) 무관. Phase A 통과 후 사용자 응답 없이 끝까지 진행.
---

`docs-file.json`을 단일 출처로 11개 빌더 스킬(`1-plan-*` ~ `5-operate-schedule`)을 순차 호출해 1~10번 섹션 문서를 자동으로 채운다. 이름은 ouroboros:ralph 패턴(*"the boulder never stops"*)에서 유래 — `1-plan-project-def`에서만 verification 통과까지 자기참조 루프, 이후 캐스케이드는 단방향 직선.

## 사전 조건

- `.claude/docs-file.json` 존재. **없으면 `docs-config-sync` (init 모드) 호출을 권장하고 중단**한다.
- 다음 키가 모두 유효해야 함:
  - `docs_root`
  - `sections` + `sections_meta` (13개씩 — 키는 동일, `sections`는 path 매핑 / `sections_meta`는 풀 메타)
  - `project_type` (`desktop` / `mobile` / `web`)
- 13개 섹션 폴더가 `{docs_root}/{sections_meta.<key>.path}` 위치에 존재해야 함. 부재 시 자동 생성하되 사용자에게 1회 보고.
- 빌더 스킬 11개(`1-plan-*` ~ `5-operate-schedule`)가 모두 설치되어 있어야 함.

## 모드 자동 판정 — Greenfield vs Brownfield

다음 신호로 모드 결정:

**Greenfield 신호**:
- 코드 디렉토리(예: `src/`, `app/`, `<App>/`)가 비었거나 부트스트랩 수준
- `code_mappings`의 매핑된 path들이 거의 다 비어있거나 채워진 비율 < 30%
- `{1_project_definition}/프로젝트 정의서 v*.md`가 placeholder 상태이거나 부재

**Brownfield 신호**:
- `code_mappings` path 70%+가 실제 파일/폴더로 존재
- 정의서가 이미 어느 정도 채워져 있음 (placeholder 잔존 < 30%)

**모호 시 사용자에게 1회만 확인** (greenfield / brownfield / cancel 3택). 이후 동작은 응답 없이 진행.

## 캐스케이드 순서 (Phase B 공통)

```
1-plan-requirements
  → 2-design-ui
  → 2-design-system
  → 3-build-data
  → 3-build-integration  *(조건부)*
  → 4-deploy-permission
  → 4-deploy-os
  → 4-deploy-release
  → 5-operate-schedule  (10_dev_schedule 갱신)
```

**근거**: 정립된 upstream/downstream 흐름. UI 명세서는 시스템 설계의 입력이 될 수 있으므로 system 앞에 둠. 권한·OS 통합이 배포 명세서에 영향을 주므로 release 앞에 둠. dev_schedule은 마지막에 1~9번을 모두 묶어 일정화.

**조건부 처리**:
- `3-build-integration`은 `sections_meta.6_integration_interface.conditional === true` + activation_condition 충족 시에만 호출. 아니면 자동 skip하고 `[skip]` 한 줄만 보고.

## Greenfield 흐름

### Phase A — Ralph 루프 (`1-plan-project-def` 대상)

```
iteration = 1
max_iterations = 10

while iteration <= max_iterations:
    invoke 1-plan-project-def (mode: greenfield)
    read {1_project_definition}/프로젝트 정의서 v*.md
    unmet = verification_check(정의서, project_type)
    if unmet is empty:
        emit "[Ralph Iteration {iteration}/{max_iterations}] PASS"
        break
    emit "[Ralph Iteration {iteration}/{max_iterations}] REVISE — unmet: {unmet}"
    iteration += 1

if iteration > max_iterations:
    emit "Max iterations reached. 사용자 개입이 필요합니다."
    exit
```

**Verification check — 3-축 가중 점수 (총 100점, 통과 임계 ≥ 85)**

정의서의 모호함을 정량화. 매 반복 같은 입력에 같은 점수가 나오도록 모두 결정적(deterministic).

#### 축 1: Coverage (40점) — 구조 완전성

종료 조건 9개 항목, 각 ~4.4점. 충족 여부 binary로 판정.

| 항목 | 충족 조건 | 배점 |
| --- | --- | --- |
| US-N 시나리오 | `[2]` 표에 최소 2행 (placeholder 행 제외) | 5 |
| 핵심 기능 | `[3]` 표에 최소 1행 | 4 |
| In Scope | `[4]` In Scope 항목 ≥ 2 | 4 |
| Out of Scope | `[4]` Out of Scope 항목 ≥ 2 | 4 |
| 제품 운영 [5] | project_type별 필수 항목 (desktop 7 / mobile 6 / web 6) 모두 결정 | 8 |
| KPI [6] | 표에 `As-Is` / `To-Be` / 측정 방법 모두 채워진 행 ≥ 1 | 5 |
| 성공 기준 [7] | 수용 기준 + 종료 조건 둘 다 작성 | 4 |
| ROI [8] | 비용 / 기대 가치 / 가정값 모두 명시 | 4 |
| 프론트매터 status | `project_status` ∈ {`📄 초안`, `🧐 검토중`, `✅ 확정`} | 2 |

**Coverage 점수 = 충족된 배점 합** (max 40)

#### 축 2: Specificity (35점) — 측정 가능성

정량 마커 vs 모호어 비율.

**정량 마커** (등장마다 +1) — regex 예시:
- 숫자 + 단위: `\d+\s*(ms|초|s|MB|GB|%|건|명|회|일|주|개월|년|kHz|fps)`
- 비교 연산: `≥`, `≤`, `<`, `>`, `이하`, `이상`, `미만`, `초과`, `P\d+`
- 날짜 / 버전: `\d{4}-\d{2}-\d{2}`, `v\d+\.\d+`
- 통계: `평균`, `중앙값`, `상위 \d+%`, `Crash-free`

**모호어** (등장마다 −1) — 다음 키워드 카운트:
- `빠르게`, `느리게`, `안정적으로`, `안정성`(단독), `사용자 친화적`, `편리하게`, `직관적으로`, `자연스럽게`, `깔끔하게`, `잘`, `최대한`, `적절히`, `적절한`, `필요 시`, `필요할 때`, `가능하면`, `등등`, `많이`, `자주`, `대체로`, `일반적으로`

**Specificity 점수 = 35 × (정량 마커 / (정량 마커 + 모호어 + 1))**
- 정량만 있으면 → 35점, 모호어만 있으면 → 0에 수렴
- `+1`은 0-division 방지 + 둘 다 0인 빈 문서를 0으로 처리

#### 축 3: Concreteness (25점) — 잔존 placeholder 페널티

가이드 문구가 실제 내용으로 교체됐는지.

**잔존 마커** (각각 카운트):
- 직접 placeholder: `(placeholder)`, `xxx`, `(...)`, `<TODO`, `XXX`, `_____`
- 표 가이드 문구: `(기능명)`, `(설명)`, `(어떻게 측정하는지)`, `(현재 수치/상태)`, `(목표 수치/상태)`, `(영역)`, `(측정 기준)`, `(구체적 수치/조건)`, `(비용 항목)`, `(가치 항목)` 등 템플릿에 박혀 있던 가이드 텍스트

**필수 필드 수**: 위 Coverage 표의 9개 항목 + 그 안의 세부 셀 (대략 25개 필드 기준)

**Concreteness 점수 = 25 × max(0, 1 − 잔존 마커 수 / 25)**
- 잔존 0개 → 25점, 25개 이상 → 0점

#### 총점

```
total = Coverage + Specificity + Concreteness   (max 100)
pass  = total >= 85
```

#### 미통과 시 보고 형식

```
[Ralph Iteration 3/10] REVISE — total: 72/100
  Coverage     : 36/40  (✓ US-N, ✓ 핵심 기능, ✗ Out of Scope 1건만, ✓ ...)
  Specificity  : 22/35  (정량 마커 12, 모호어 9 — "빠르게" 3건 / "안정적으로" 2건 / ...)
  Concreteness : 14/25  (잔존 11건 — `(어떻게 측정하는지)` ×3, `(목표 수치/상태)` ×2, ...)
  
  부족 축: Specificity, Concreteness
  다음 반복 입력: KPI 측정 방법을 수치화 / 모호어 9건 교체 / 가이드 문구 11건 실제 값으로
```

미충족 항목·모호어·잔존 마커 목록을 다음 반복에서 `1-plan-project-def`의 인터뷰 입력으로 전달 (자기참조).

#### 임계 조정

- 데스크톱·모바일·웹 모두 동일하게 **85점**.
- v1.0 1차 출시 단계는 85, 베타·MVP 단계는 75로 낮춰 호출 가능 (ralph-docs 인자로 `--threshold 75` 받을 수 있게 향후 확장).

### Phase B — 캐스케이드

Phase A 통과 직후 즉시 시작. **사용자 응답 받지 않음**.

위 캐스케이드 순서를 그대로 따른다. 각 호출 후 해당 빌더 스킬의 "종료 조건"으로 verification check:
- 통과 → `[N/9] {skill-name} ✓` 한 줄 출력
- 미통과 → `[N/9] {skill-name} ⚠️ unmet: {summary}` 출력 후 **계속 진행** (그린필드는 정보가 부족할 수밖에 없으므로 hard fail 안 함)

## Brownfield 흐름

Phase A **없음**. 사용자 인터뷰 루프 불필요 — 코드가 진실의 원천.

### 절차

1. `code_mappings`를 따라 각 섹션의 입력 자료 인덱스 생성 (실제 존재하는 path만 추림).
2. 캐스케이드 순서대로 빌더 스킬 호출. 단 **모든 호출은 브라운필드 모드**로:
   - 인터뷰 최소화
   - 코드 / 리소스 / 빌드 설정 / entitlements / Info.plist / 환경변수 매니페스트 등에서 사실 추출
   - 추정 항목은 `<TODO: 근거>` 표시
3. 각 호출 후 verification check (greenfield와 동일 — 미통과는 경고만).

> **Brownfield의 `1-plan-project-def`**: 인터뷰 없이 README/CLAUDE.md/AGENTS.md/project.yml/entitlements 등에서 비전·범위·제약을 추출. ralph 루프는 돌리지 않음 (정의서가 어느 정도 채워지면 즉시 다음 섹션으로 진행).

## 호출 메커니즘 / 인자 전달

- 각 빌더 스킬은 `docs-file.json`을 자체적으로 로드하므로 별도 인자 없이 invoke.
- 모드 힌트(`greenfield` / `brownfield`)는 conversation context로만 전달.
- 빌더 스킬의 출력 산출물(`{path}/{title} v*.md`)을 ralph-docs가 직접 읽어 verification에 사용.

## Verification 기준 (섹션별)

각 빌더 스킬의 SKILL.md "종료 조건" 섹션을 그대로 인용한다. ralph-docs는 그 기준을 복제하지 않고 빌더 스킬에 위임한다 (단일 출처 유지).

- `1-plan-project-def`: hard gate (Phase A 루프 종료 조건) — 위 verification check 참조
- 나머지 8~9개 빌더 스킬: soft warning (미충족 시 경고만 기록, 캐스케이드 계속)

## 출력 보고 형식

### 시작
```
== ralph-docs 시작 ==
모드: {greenfield | brownfield}  (판정 근거: ...)
project_type: {desktop | mobile | web}
캐스케이드 순서: 1-plan-requirements → 2-design-ui → 2-design-system → 3-build-data → ...
조건부 섹션: 6_integration_interface = {활성 | 비활성}
```

### Phase A (greenfield 전용)
```
[Ralph Iteration 1/10] REVISE — total: 58/100
  Coverage 28/40 / Specificity 18/35 / Concreteness 12/25
  부족 축: Coverage(Out of Scope 미달, KPI 표 빈칸), Specificity(모호어 12), Concreteness(가이드 문구 9)

[Ralph Iteration 2/10] REVISE — total: 79/100
  Coverage 38/40 / Specificity 24/35 / Concreteness 17/25
  부족 축: Specificity(모호어 7건 잔존)

[Ralph Iteration 3/10] PASS — total: 92/100
  Coverage 40/40 / Specificity 31/35 / Concreteness 21/25
```

### Phase B (캐스케이드)
```
[1/9] 1-plan-requirements ✓
[2/9] 2-design-ui ✓
[3/9] 2-design-system ✓
[4/9] 3-build-data ⚠️ unmet: [7] 백업 / 내보내기 정책 미작성
[5/9] 3-build-integration [skip] 외부 연동 없음
[6/9] 4-deploy-permission ✓
[7/9] 4-deploy-os ✓
[8/9] 4-deploy-release ✓
[9/9] 5-operate-schedule ✓
```

### 종료
```
== ralph-docs 완료 ==

13-섹션 status:
  0_idea_backlog                skip (primary_skill 없음)
  1_project_definition          ✓ v1.0
  2_requirements                ✓ v1.0
  3_system_design               ✓ v1.0
  4_ui_spec                     ✓ v1.0
  5_data_spec                   ⚠️ v1.0 (TODO 1건)
  6_integration_interface       skip (조건부 — 비활성)
  7_release                     ✓ v1.0
  8_permission_sandbox          ✓ v1.0
  9_platform_integration        ✓ v1.0
  10_dev_schedule               ✓ v1.0
  11_collaboration              skip (수동 작성)
  12_tech_docs                  skip (학습 노트는 5-operate-study)

잔존 TODO:
  - 5_data_spec: 백업 / 내보내기 정책 미작성
  - ...

다음 액션:
  - `docs-sync`로 코드 ↔ 문서 정합 점검
  - 잔존 TODO 인터뷰 재개 (수동)
  - `5-operate-study`로 운영 런북 / 학습 노트 누적
```

## 중단 / 재개

- 사용자가 *"중단"* / *"stop"* 등 신호하면 graceful exit (현재 섹션까지 결과 보존).
- 재호출 시 각 섹션 1차 산출물의 frontmatter `version` / `project_status`를 읽어 이미 통과한 섹션은 skip, 미통과부터 재개.

## 재실행 안전성

- 이미 채워진 문서가 있으면 v1.0 → v1.1로 변경 영역만 갱신 (브라운필드 원칙 그대로 유지).
- 변경 전 자동 백업은 하지 않음 — 빌더 스킬 자체가 frontmatter `version`을 올리도록 신뢰.
- ralph-docs 자체는 파일을 직접 쓰지 않음 — 빌더 스킬에 위임만 한다.

## 데스크톱 표준 분기 처리

`project_type === "desktop"`일 때만 추가 검증:
- Phase A 종료 조건에 `[5] 제품 운영 7개 하위 항목` 포함 (위 명시).
- 나머지 빌더 스킬의 데스크톱 전용 체크(예: 한국어 IME 호환 / Sandbox / Notarization)는 각 빌더 SKILL.md의 종료 조건이 처리.

`mobile` / `web`은 해당 빌더 스킬의 종료 조건만 적용. ralph-docs는 그 기준을 복제하지 않는다.

## 핵심 원칙

- **단일 출처**: ralph-docs는 라우팅만 한다. 모든 진실은 `docs-file.json` + 빌더 스킬의 SKILL.md "종료 조건".
- **하드코딩 금지**: 어떤 프로젝트 경로도 ralph-docs SKILL.md에 적지 않음. 모든 path는 `code_mappings`에서 동적 lookup.
- **사용자 응답 최소화**: Greenfield Phase A의 ralph 루프 안에서만 사용자와 대화 (그것도 `1-plan-project-def`가 알아서 진행). Phase B와 Brownfield는 0회.
- **Soft fail**: Phase A만 hard gate. 캐스케이드는 미통과 시 경고만 — 정보가 부족한 상태에서도 끝까지 진행해 사용자가 잔존 TODO를 한 번에 보게 함.

## 완료 조건

- 1~10번 섹션 문서가 v1.0+ 상태로 채워짐 (조건부 섹션은 활성일 때만)
- Phase A 루프가 통과되어 정의서가 verification 기준 충족 (greenfield)
- 잔존 `<TODO>` 항목이 종합 보고에 명시됨
- 13-섹션 status 표 출력 완료

## 관련 스킬

- 호출 대상 11개 빌더 스킬: `1-plan-project-def` / `1-plan-requirements` / `2-design-system` / `2-design-ui` / `3-build-data` / `3-build-integration` / `4-deploy-permission` / `4-deploy-os` / `4-deploy-release` / `5-operate-schedule` / `5-operate-study`(별도)
- 사전 설정: `docs-config-sync` (init / update 모드로 docs-file.json 생성 / 갱신)
- 사후 정합 점검: `docs-sync` (코드 ↔ 문서 drift 감지)
