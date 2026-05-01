---
name: 5-operate-schedule
description: 프로젝트 문서 1~9번의 버전을 정렬하고 개인 / 팀 가능 시간을 반영해 개발 진행 일정을 버전별로 계획한다. docs-file.json의 sections를 동적으로 읽어 현재 문서 상태에 맞는 현실적인 일정으로 갱신하거나, 문서 버전 업에 따라 신규 일정(리플랜)을 자동으로 만들 때 사용한다. project_type(desktop / mobile / web) 무관하게 동작 — 입력 문서 목록은 docs-file.json에서 동적으로 구성한다.
---

문서 버전과 개인/팀 일정 제약을 동시에 반영해 실행 가능한 개발 일정을 만든다.

## 경로 해석

이 스킬은 프로젝트의 `.claude/docs-file.json`을 단일 출처로 참조한다.
- `docs_root`: 문서 루트
- `sections`: 섹션 키 → path 매핑 (1~9를 동적으로 읽어 입력 문서 목록 구성)
- `sections_meta`: 모든 섹션 풀 메타 (`title`, `path`, `template_path`, `deliverables`, `primary_skill` 등)
- `sections_meta.10_dev_schedule`: 이 섹션의 메타
  - `path`: 산출물이 들어갈 위치 (예: `5. 운영/프로젝트 운영/10. 개발 진행 관리/`)
  - `template_path`: 원본 템플릿이 들어 있는 위치 (예: `0. 템플릿/운영/`)
  - `deliverables`: 인스턴스화할 템플릿 상대 경로 목록 (구버전 `filenames`와 호환)

## 템플릿 카탈로그

`{docs_root}/{template_path}` 아래 다음 템플릿이 존재한다. 새 산출물을 만들 때 이 파일들을 `{docs_root}/{path}`로 복사한 뒤 frontmatter / 본문 placeholder를 실제 값으로 채운다.

| 템플릿 상대 경로 | 용도 | 인스턴스화 규칙 |
| --- | --- | --- |
| `개발 진행 관리.md` | 월간 대시보드 (참여자 / 버전 / 스프린트 / 캘린더 / 리스크) | `{path}개발 진행 관리.md`로 복사. frontmatter `target_month`, `members`, `created`, `updated`를 갱신. Dataview 블록은 그대로 둔다. |
| `sprints/Sprint-Template1.md` | 스프린트 카드 (목표·일별 계획·회고) | `{path}sprints/Sprint-NNN.md`로 복사. `sprint`, `theme`, `start_date`, `end_date`, `sprint_status` 갱신. |
| `sprints/Sprint-Template2.md` | 스프린트 카드 변형 | 위와 동일 — 팀 / 1인 등 상황에 맞게 선택. |
| `tasks/TASK-Template1.md` | 태스크 카드 기본형 | `{path}tasks/TASK-NNN.md`로 복사. `task`, `assignee`, `date`, `sprint`, `hours`, `task_status`, `related` 갱신. `assignee`는 대시보드 `members`와 일치해야 한다. |
| `tasks/TASK-Template2.md` | 태스크 카드 변형 | 작업 성격에 따라 선택. |
| `tasks/TASK-Template3.md` | 태스크 카드 변형 | 작업 성격에 따라 선택. |
| `회의/n월/2026-xx-xx.md` | 회의록 원본 (날짜 placeholder) | `{path}회의/<YYYY-MM>월/<YYYY-MM-DD>.md`로 복사. 0)~ 섹션 placeholder를 회의 실제 값으로 채운다. |
| `회의/n월/2026-xx-xx-요약집.md` | 회의 요약집 | `{path}회의/<YYYY-MM>월/<YYYY-MM-DD>-요약집.md`로 복사. |

> **주의:** `{path}` 디렉터리는 산출물 전용이다. 템플릿 자체를 산출물 폴더에 두지 않는다. 모든 신규 파일은 템플릿을 복사·치환해 만든다.

## 출력 (반드시 갱신)

1. `{path}개발 진행 관리.md` — 현재 DOCSET ID + 문서별 버전 표 + Top 3 + 리스크 + 리플랜 조건 (대시보드 템플릿 인스턴스)
2. `{path}버전별 일정 계획.md` — 주 단위 스프린트 계획 (없으면 생성 — 템플릿 외 직접 작성)
3. `{path}sprints/Sprint-NNN.md` — Sprint-Template1 또는 2를 복사해 인스턴스화
4. `{path}tasks/TASK-NNN.md` — TASK-Template1~3 중 하나를 복사해 인스턴스화
5. (회의가 발생한 경우) `{path}회의/<YYYY-MM>월/<YYYY-MM-DD>.md` — 회의록 템플릿 인스턴스

## 입력 소스 (project_type 무관 — 동적 구성)

`docs-file.json`의 `sections`에서 다음 키들을 순회해 존재하는 문서를 입력으로 사용한다:

```
1_project_definition
2_requirements
3_system_design
4_ui_spec
5_data_spec
6_integration_interface  (conditional — activation_condition 미충족 시 생략)
7_release
8_permission_sandbox
9_platform_integration
```

**버전 추출 우선순위**:
1. frontmatter의 `version` 필드
2. 본문의 `버전: vX.Y.Z` 또는 `vX.Y.Z` 패턴
3. 없으면 `v0.0.0` + 파일 수정일 기반 임시 버전

> 섹션 키가 다른 프로젝트(예: 옛 `5_local_data_spec`)에서는 docs-file.json의 현재 키를 그대로 따른다.

## 운영 모드

### A. 신규 일정 (그린필드)
- 모든 문서를 처음 스캔해 DOCSET 스냅샷 생성.
- 대시보드 템플릿(`개발 진행 관리.md`)을 `{path}`로 복사 → frontmatter / 버전 표 채움.
- 첫 스프린트 카드(`sprints/Sprint-001.md`)와 첫 태스크 카드(`tasks/TASK-001.md`)를 템플릿에서 복사해 인스턴스화.

### B. 리플랜 (브라운필드 / 진행 중)
- 이전 DOCSET와 비교해 변경된 문서만 식별 → 영향도에 따라 재계획.
- 기존 대시보드의 버전 표 / Top 3 / 리스크 섹션만 갱신.
- 새 스프린트가 필요하면 Sprint-Template을 복사해 다음 번호로 추가.

## 개인 / 팀 일정 확인 절차

일정 생성 전에 반드시 사용자에게 아래를 확인한다.

1. **주당 실제 가능 시간** (평균) — 개인 또는 팀 인원별
2. **고정 불가 시간대** — 업무 / 학업 / 휴가 / 정기 회의
3. **선호 작업 시간대** — 평일 저녁 / 주말 / 오전 등
4. **목표 마감일** — 있으면 (외부 약속 / 발표 / 베타 출시 등)
5. **블로커 / 외부 의존성** — 디자인 / 외부 API 키 발급 등

답이 없으면 보수적 기본값을 사용하고 `[가정]` 표시:
- 1인 사이드프로젝트: 주 6~8시간
- 풀타임 1인: 주 30~35시간
- 팀: 인원 × 30시간 × 0.6 (오버헤드)

## DOCSET 스냅샷 규칙

**스냅샷 ID**: `DOCSET-<YYYYMMDD>-<hash8>`
- hash 입력: 모든 활성 섹션의 `(섹션 키, 파일 경로, 버전, 수정시각)`
- 조건부 섹션은 `conditional && activation_condition` 충족 시에만 포함

**비교 알고리즘**:
- 이전 DOCSET와 비교 → 변경 문서 목록 + 변경 종류(version-up / content-update / new / removed)
- 영향도 분류:
  - **낮음**: 1개 문서의 minor 변경 → 일정 유지 + 태스크 미세 조정
  - **중간**: 1~2개 문서의 major 변경 → 해당 영역 마일스톤 재배치
  - **높음**: 정의서 / 요구사항 major 변경 또는 3개 이상 문서 변경 → 전체 마일스톤 재계획

## 일정 작성 규칙

- **주 단위 스프린트** (Sprint-001부터)
- 각 스프린트 카드는 `sprints/Sprint-Template1.md` 또는 `Sprint-Template2.md`의 구조를 따른다:
  - 목표 & 완료 기준 (Top 3)
  - 일별 계획 (날짜 / 담당 / 작업 / 예상 시간)
  - 회고 (스프린트 종료 후)
- 각 태스크 카드는 `tasks/TASK-Template1~3.md` 구조를 따른다:
  - frontmatter: `task / assignee / date / sprint / hours / task_status / related`
  - 상세 내용 / 완료 기준 / 메모
- **스프린트 capacity**는 사용자 가능 시간 기준 (전체 시간의 70%만 계획 — 30%는 버퍼)
- **마일스톤은 문서 버전 변경 시점**과 정렬 (예: v1.0 정의서 확정 → 마일스톤 1, v1.0 요구사항 확정 → 마일스톤 2 ...)

## 대시보드 (`개발 진행 관리.md`) 구조

템플릿(`{template_path}개발 진행 관리.md`)을 복사한 뒤 다음 항목을 갱신한다:

- frontmatter: `target_month`, `members`, `created`, `updated`, `project_status`
- DOCSET 스냅샷 정보 (DOCSET ID + 마지막 갱신일)
- 문서별 버전 표 (1~9 섹션)
- 이번 스프린트 Top 3
- 리스크 / 블로커
- 다음 리플랜 트리거 (정의서·요구사항 major 변경 / 외부 API 발급 지연 등)

> 템플릿의 Dataview / dataviewjs 블록은 수정하지 않는다 (Obsidian에서 자동 렌더링).

## 자동화 스크립트

버전 스냅샷 생성:
```
python .claude/skills/5-operate-schedule/scripts/docset_version_snapshot.py \
  --docs-root "$(jq -r .docs_root .claude/docs-file.json)" \
  --out /tmp/docset-version.md
```

스크립트 역할:
- `docs-file.json`의 `sections`를 동적으로 읽어 활성 섹션 목록 구성
- 각 섹션의 1차 문서(예: `<섹션 path>/<섹션 title> v*.md`) 버전·수정시각 추출
- DOCSET ID 계산
- markdown 표 출력

## 시작 절차

1. `.claude/docs-file.json`을 로드.
2. `sections`에서 1~9 키 순회 — 활성 섹션 목록 구성.
3. `sections_meta.10_dev_schedule.template_path`와 `filenames`로 템플릿 카탈로그를 확인.
4. 각 섹션의 1차 문서 버전 추출 → DOCSET 스냅샷 생성.
5. (리플랜) 이전 스냅샷과 비교 → 변경 문서 식별.
6. 사용자에게 개인 / 팀 일정 확인 (위 5개 질문).
7. 대시보드가 `{path}`에 없으면 템플릿(`{template_path}개발 진행 관리.md`)을 복사해 생성.
8. 신규 스프린트가 필요하면 `sprints/Sprint-TemplateN.md`를 복사해 `Sprint-NNN.md`로 인스턴스화.
9. 신규 태스크가 필요하면 `tasks/TASK-TemplateN.md`를 복사해 `TASK-NNN.md`로 인스턴스화.
10. 사용자에게 보고.

## 보고 형식

- 새 / 변경된 DOCSET ID
- 변경된 문서 목록과 영향도 분류
- 새로 생성 / 갱신된 스프린트 (어떤 템플릿에서 인스턴스화했는지 명시)
- 일정 변경 사항 (마일스톤 재배치 / capacity 조정)
- 리플랜 트리거 조건

## 품질 체크리스트

- 대시보드에 최신 DOCSET ID와 버전 표가 반영됨
- 일정 계획에 현재 버전 기준 스프린트가 작성됨
- 개인 / 팀 가능 시간을 반영한 주당 capacity가 계산됨 (70% 계획 / 30% 버퍼)
- 버전 변경 시 재계획 규칙이 문서에 명시됨
- 모든 활성 섹션이 입력으로 반영됨 (조건부 섹션의 비활성도 명시)
- 산출물은 모두 `{template_path}` 템플릿에서 복사·치환되어 생성됨 (직접 손으로 새 파일 형식을 발명하지 않는다)
- 템플릿 자체는 `{path}`에 복사하지 않는다 (산출물 폴더는 인스턴스만 보관)

## 종료 조건

- DOCSET 스냅샷이 모든 활성 섹션을 커버
- 스프린트 capacity가 사용자 합의 시간으로 채워짐
- 리플랜 트리거가 명시됨
- 대시보드 + 일정 계획 + (필요 시) 신규 Sprint / TASK 카드가 템플릿 기반으로 생성·갱신됨

## 다음 액션 (완료 시 제안)

1. 사용자가 첫 스프린트 시작 — 추가 태스크 카드(`tasks/TASK-NNN.md`)를 `TASK-TemplateN`에서 인스턴스화
2. 회의가 발생하면 `회의/n월/2026-xx-xx.md` 템플릿을 복사해 `회의/<YYYY-MM>월/<YYYY-MM-DD>.md` 회의록 생성
3. 문서 버전 업 시 자동 리플랜 트리거 (사용자에게 알림)
4. **`5-operate-study`** 호출 — 학습 / 의사결정 / 인시던트가 발생하면 기술 문서로 누적
