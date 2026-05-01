# 호롱호롱에 기여하기

> 작은 등불 하나에 손을 얹어주셔서 감사합니다. 🪔

이 문서는 호롱호롱(HorongHorong)에 기여하려는 분을 위한 짧은 안내서입니다.
*PR이 빠르게 머지되는 길*과 *프로젝트가 향하는 방향*을 미리 공유합니다.

<sub>한국어 · <a href="CONTRIBUTING.en.md">English</a></sub>

---

## 🪔 이 프로젝트가 추구하는 것

호롱호롱은 *작은 등불 하나*가 컨셉인 만큼, 다음 원칙을 지킵니다.

1. **메뉴바라는 가장 가벼운 표면 위에서 작동한다**
   — 풀스크린 윈도우, 복잡한 멀티윈도우 관리는 호롱호롱의 결이 아닙니다.
2. **로컬 우선(local-first)**
   — 사용자 데이터는 사용자의 기기(SwiftData) 안에 머뭅니다. 클라우드 동기화나 계정 시스템은 의도적으로 두지 않습니다.
3. **흐름을 끊지 않는 UX**
   — 한 번의 단축키, 한 번의 클릭으로 도구가 뜨고 사라집니다.
4. **벤더 종속 없는 AI 호출**
   — LLM은 사용자가 설치한 CLI(`claude` / `codex` / `gemini` / `opencode`)를 경유합니다. SDK 직결·서버 호출은 지양합니다.
5. **흩어진 도구를 잇는 것 ≠ 모든 것을 다 하는 것**
   — 호롱호롱은 *생산성 슈퍼앱*을 지향하지 않습니다. *몰입의 다리* 정도입니다.

## 🚫 지금 단계에서 추구하지 않는 것 (Current Non-goals)

현재 버전(v1.x 기준)에서는 다음 영역을 *의도적으로 다루지 않습니다.* 다만 영구히 닫혀 있는 문은 아닙니다 — 아래 *"미래에 열어둔 문"* 섹션을 참고해주세요.

- **클라우드 동기화 / 계정 시스템** (최소 v1.x 동안)
- **외부 SaaS API 직결** — LLM은 로컬 CLI 경유로 통일
- **풀스크린·복잡한 윈도우 관리** — 메뉴바 앱의 본분에 충실
- **무거운 의존성 추가** — 새 라이브러리는 *그 가치가 분명할 때만*

> 위 방향과 어긋나는 PR은 즐거운 토론은 가능하지만, 현재 단계에서는 머지되지 않을 수 있습니다.

## 🌱 미래에 열어둔 문 (Possibly Later)

지금은 다루지 않지만, 프로젝트가 성장하면 충분히 합류할 수 있다고 생각하는 영역입니다. 관심 있으신 분은 이슈로 *디스커션*을 먼저 열어주세요 — 시기와 설계 방향을 함께 정하는 게 우선입니다.

- **모바일(iOS / iPadOS) 확장** — macOS 컨셉을 모바일에 어떻게 옮길지 별도 설계가 필요합니다.
- **Windows / Linux 지원** — 메뉴바라는 표면이 OS마다 의미가 달라, 단순 포팅이 아닌 *재해석* 단계가 선행되어야 합니다.
- **선택적 동기화** — 사용자가 켤 수 있는 방식의 *로컬 우선 + 옵션 동기화* (계정 시스템과는 별개로)
- **외부 API 직접 연동** — LLM CLI 외에 명확히 가치가 큰 통합이 있을 때
- **플러그인 / 확장 시스템** — 기여자 생태계가 일정 규모 이상일 때

> 이 영역의 PR은 *작은 변경부터* 시작해주세요. 큰 일괄 PR보다 *디스커션 → 작은 프로토타입 → 점진적 확장*이 머지에 훨씬 가깝습니다.

---

## 🔧 개발 환경

### 요구 사항

- macOS 15.0 이상
- Xcode 16.0 이상
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`uv`](https://github.com/astral-sh/uv) — *(뉴스 기능 개발 시)* `brew install uv`
- LLM CLI 중 하나 이상 — *(뉴스 / Agent 기능 개발 시)*
  - `claude`, `codex`, `gemini`, `opencode`

### 셋업

```bash
git clone https://github.com/Jungjihyuk/horong-horong.git
cd horong-horong
xcodegen generate
open HorongHorong.xcodeproj
```

### 뉴스 파이프라인 (선택)

```bash
cd Agents/news_report
uv sync
```

---

## 🗂 폴더 구조 (요약)

```
HorongHorong/
├── HorongHorong/
│   ├── Features/        ← 새 기능은 여기 하위에 폴더 단위로 추가
│   ├── Models/          ← SwiftData 모델
│   ├── Services/        ← 백그라운드 작업, 외부 호출 추상화
│   ├── Resources/       ← 에셋, 로컬라이제이션
│   ├── Utilities/       ← 공용 유틸리티
│   ├── AppState.swift   ← 전역 상태
│   └── HorongHorongApp.swift
├── HorongHorongTests/   ← 단위 테스트
├── Agents/              ← Python 기반 뉴스 / Agent 파이프라인
├── Shared/              ← 코드 외 공유 자산
├── assets/              ← README·홍보용 이미지 (별도 라이센스 — assets/LICENSE 참고)
└── docs/                ← 기획·설계·운영 문서
```

---

## 🐛 좋은 이슈 작성법

이슈는 **버그 / 기능 / 질문** 으로 분리해주세요.

### 버그 리포트
- 재현 절차 (1, 2, 3, ...)
- 기대한 결과 vs 실제 결과
- 환경: macOS 버전 / Xcode 버전 / 호롱호롱 버전
- 로그 또는 스크린샷 (가능하다면)

### 기능 제안
- *어떤 문제*를 풀고 싶은지 (해결책이 아니라 문제부터)
- 메뉴바 컨셉과 어떻게 어울리는지
- 대안으로 고려한 것

### 질문
- 사용법 질문은 [`USER_GUIDE.md`](USER_GUIDE.md) 먼저 확인 부탁드립니다.

### 이슈 제목 / 본문 형식

이슈 제목은 아래 형식을 사용합니다.

```md
[TYPE] 한글 제목
```

본문은 실제 작업 단위를 Todo 체크리스트로 작성합니다.

```md
## Todo
- [ ] 구현 항목 1
- [ ] 구현 항목 2
- [ ] 구현 항목 3
```

---

## 🎨 코드 스타일

- **Swift 6.0**, `SWIFT_STRICT_CONCURRENCY: minimal`
- 새 의존성 추가는 이슈에서 먼저 합의
- 주석은 *왜*만 — *무엇을*은 코드가 말하게
- 한국어 UI 문자열은 한국어로, 코드 식별자는 영어로

---

## ✍️ 커밋·PR 컨벤션

### 작업 타입

이슈, 커밋, PR에서 사용하는 타입은 다음 기준을 따릅니다.

| 타입 | 기준 |
|------|------|
| `FEAT` / `feat` | 새로운 기능 추가 |
| `FIX` / `fix` | 버그 수정 |
| `DOCS` / `docs` | 문서 작업 |
| `REFACTOR` / `refactor` | 로직 변경 없는 코드 구조 개선 |
| `REMOVE` / `remove` | 파일 또는 코드 제거 |
| `CHORE` / `chore` | 빌드 설정, 패키지, 환경 설정 |
| `TEST` / `test` | 테스트 코드 추가 또는 수정 |
| `ENHANCE` / `enhance` | 기존 기능 성능 개선 |

### 브랜치

- 작업 브랜치는 `feature/#이슈번호-짧은-설명` 형식을 권장합니다.
- 예: `feature/#12-timer-preset`
- base 브랜치는 **`dev`** 입니다.

### 커밋 메시지

커밋 메시지는 아래 형식을 사용합니다.

```md
type: English header message

#이슈번호
```

- `type`은 소문자로 작성합니다. 예: `feat`, `fix`, `docs`
- 헤더는 영어로 작성하고, 대문자로 시작하며, 마침표를 붙이지 않습니다.
- 이슈 번호는 브랜치명에서 확인할 수 있을 때만 footer에 포함합니다.

예시:

```md
docs: Update contribution workflow

#12
```

### PR 제목

PR 제목은 아래 형식을 사용합니다.

```md
[TYPE] 한글 제목
```

- `TYPE`은 대문자로 작성합니다. 예: `FEAT`, `FIX`, `DOCS`
- 제목은 한글로, 70자 이내로, 마침표 없이 작성합니다.

### PR 본문 권장 형식

```md
## Overview
변경사항에 대한 전반적인 설명

## Change Log
- 추가/변경된 주요 사항

## To Reviewer
- 리뷰어가 특별히 확인해야 할 사항
- 설계 결정, 트레이드오프, 주의할 로직 등

## Issue Tag
Closes #이슈번호
```

### Claude 스킬 사용 (선택)

이 저장소에는 반복 작업을 줄이기 위한 Claude 스킬이 `.claude/skills/`에 포함되어 있습니다.
Claude를 사용하는 경우 다음 스킬로 이슈, 커밋, PR 문안을 프로젝트 컨벤션에 맞춰 생성할 수 있습니다.

- `issue`: 이슈 제목과 Todo 체크리스트 본문 생성
- `commit`: staged 변경사항을 바탕으로 커밋 메시지 생성 및 커밋
- `pr`: 커밋 히스토리와 변경사항을 바탕으로 PR 제목과 본문 생성

수동 작성도 가능하며, 제출 전 최종 내용은 직접 검토해 주세요.

---

## 💡 PR 보내기 전 체크리스트

- [ ] **이슈로 먼저 합의했는가** — 이슈 없는 PR은 닫힐 수 있습니다.
- [ ] **한 PR = 한 변경** — 리팩토링과 기능 추가는 분리합니다.
- [ ] **브랜치가 `feature/#이슈번호-짧은-설명` 형식인가**
- [ ] **빌드가 통과하는가** — `xcodegen generate && xcodebuild -scheme HorongHorong build`
- [ ] **새 기능은 `HorongHorong/Features/<Feature>` 하위에 격리되어 있는가**
- [ ] **SwiftData 모델을 변경했다면 마이그레이션을 포함했는가**
- [ ] **UI 변경 시 스크린샷 1장 첨부했는가**
- [ ] **한국어 UI 문자열이 자연스러운가**

---

## 📝 행동 강령

프로젝트에 참여하기 전 행동 강령을 확인해 주세요.

- [한국어 행동 강령](CODE_OF_CONDUCT.md)
- [English Code of Conduct](CODE_OF_CONDUCT.en.md)

---

## 📄 라이센스

- 코드 기여는 [Apache License 2.0](LICENSE) 하에 배포되는 것에 동의하는 것으로 간주됩니다.
- 이미지·캐릭터 자산은 별도 라이센스([`assets/LICENSE`](assets/LICENSE))를 따릅니다 — *기여 시 권리 이전이 필요할 수 있으므로 사전에 이슈로 논의해주세요.*

---

## 📩 연락

- 일반 문의 / 버그 / 기능: GitHub Issues
- 라이센스 / 자산 / 상업적 협업: <wlgur278@gmail.com>

🪔 *Made with a small flame — and welcomed by many hands.*
