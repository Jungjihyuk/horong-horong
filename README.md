<div align="center">

# 호롱호롱 (HorongHorong)

**Horong** — *the little vessel that holds the flame in your menu bar.*

호롱은 작은 불빛을 담아 꺼지지 않게 지키는 그릇입니다. <br>
그 불빛은 희망이자 열망이며, $\color{#D97706}{\textbf{몰입}}$과 목표를 상징합니다. <br>
호롱이 그 빛을 모아 오래 머물게 하듯, 이 앱은 흩어진 $\color{#D97706}{\textbf{몰입}}$을 이어 붙잡고, $\color{#D97706}{\textbf{관심사}}$를 한곳에 $\color{#D97706}{\textbf{모으며}}$, 작은 실험이 시작될 수 있는 $\color{#D97706}{\textbf{환경}}$을 만듭니다.

<!-- TODO: 대표 이미지 / 히어로 배너 교체 (현재는 임시로 horonghorong.png 사용) -->
<img src="./assets/intro/yagyong_jeong4.png" alt="HorongHorong" width="450"/>

<br />

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)](#요구-사항)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Assets: All Rights Reserved](https://img.shields.io/badge/assets-All%20Rights%20Reserved-red)](assets/LICENSE)
[![Release](https://img.shields.io/github/v/release/Jungjihyuk/HorongHorong?style=flat)](https://github.com/Jungjihyuk/HorongHorong/releases)
[![Stars](https://img.shields.io/github/stars/Jungjihyuk/HorongHorong?style=flat&logo=github)](https://github.com/Jungjihyuk/HorongHorong)

<sub>한국어</sub> · <sub><a href="README.en.md">English</a></sub>

</div>

---


<div align="center">

> *작은 등불 하나로 — 몰입을 비추고, 관심사를 모으고, 작은 실험을 켭니다.*

<br />

<a href="https://github.com/Jungjihyuk/HorongHorong/releases/latest"><strong>📥 최신 릴리스 다운로드</strong></a>
 · 
<a href="#b-소스에서-빌드"><strong>소스에서 빌드하기</strong></a>

<sub>정식 릴리스 준비 중입니다. 지금은 소스 빌드를 기준으로 먼저 사용해볼 수 있습니다.</sub>

</div>

<br>

**호롱호롱**은 macOS 메뉴바에 상주하는 다목적 생산성 앱입니다. <br>
`포모도로 타이머`, `앱 사용 추적`, `퀵 메모`, `뉴스 큐레이션`, `AI Agent 실험`까지 <br>
흩어져 있던 도구들을 하나의 메뉴바 아이콘으로 모았습니다.

### 왜 만들었나

- **흩어진 $\color{#D97706}{\textbf{몰입}}$ 을 이어 붙이려고** — 타이머, 사용 시간 추적, 메모, 뉴스 리더를 다른 앱으로 옮겨다니다 보면 작업의 결이 자꾸 끊기곤 합니다. 메뉴바라는 가장 가벼운 표면 위에 도구들이 같은 자리에 머물도록 해, 흐름을 자르지 않고 곧바로 다시 집중으로 돌아갈 수 있게 했습니다.
- **$\color{#D97706}{\textbf{관심사}}$ 를 빠르게 모으려고** — 보고 싶은 영상 · 기사 · 트렌드는 쌓일수록 무거워집니다. 흩어진 소스를 자동으로 수집하고 LLM이 카테고리별로 분류 · 요약해, 관심사가 한 화면 안에 가만히 모이도록 했습니다.
- **작은 실험이 시작될 $\color{#D97706}{\textbf{환경}}$ 을 마련하려고** — 좋은 정보를 봐도 *직접 만들어보는* 단계로 넘어가는 장벽은 늘 큽니다. AI Agent CLI를 한 번의 호출로 계획 → 실행까지 이어지게 해, 소비에서 창작으로 가는 다리를 짧게 했습니다. 데이터는 모두 로컬(SwiftData)에 저장되고 AI 호출도 사용자가 설치한 CLI를 통해 이뤄지기에, 외부 의존 없이 가볍게 시작할 수 있습니다.

## 📌 특징

<table>
<tr>
<td width="45%" valign="middle">

### 🕐 포모도로 타이머
프리셋(50/5, 100/10, 커스텀)으로 집중·휴식 사이클을 관리합니다. 메뉴바 아이콘이 🔥/☕로 바뀌며 남은 시간을 표시하고, 완료 시 시스템 알림과 플로팅 토스트가 함께 뜹니다.

</td>
<td width="55%" align="center">
<img src="./assets/features/timer.png" alt="타이머" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📝 퀵 메모
글로벌 단축키로 어느 앱에서든 플로팅 입력 패널을 즉시 호출합니다. 저장된 메모는 메뉴바 메모 탭에서 영구 보관되고, 최신순으로 조회됩니다.

</td>
<td width="55%" align="center">
<img src="./assets/features/quick-memo.png" alt="퀵 메모" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📊 앱 사용 시간 통계
백그라운드에서 활성 앱을 실시간 추적해 카테고리별(업무 / 개발 / 공부 / 조사 / 기록 / 소통 / 엔터 / 기타)로 자동 집계합니다. 메뉴바 요약에서 오늘의 사용 시간을 빠르게 확인하고, 상세 보기에서는 일간·주간·월간 통계를 확인할 수 있습니다.

</td>
<td width="55%" align="center">
<table>
<tr>
<td align="center" width="50%">
<img src="./assets/features/stats-summary.png" alt="요약 통계" width="190" />
<sub>요약 통계</sub>
<br />
</td>
<td align="center" width="50%">
<img src="./assets/features/daily_statistic.png" alt="일간 통계" width="190" />
<br />
<sub>일간</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="./assets/features/weekly_statistic.png" alt="주간 통계" width="190" />
<br />
<sub>주간</sub>
</td>
<td align="center" width="50%">
<img src="./assets/features/monthly_statistic.png" alt="월간 통계" width="190" />
<br />
<sub>월간</sub>
</td>
</tr>
</table>
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📰 뉴스 큐레이션
YouTube 재생목록 · Google News · 요즘IT 등 자주 정보를 접하는 채널에서 데이터를 수집해 LLM이 카테고리별 분류 + 한 줄 요약을 생성합니다. 결과는 일일 마크다운 리포트로 저장됩니다.

</td>
<td width="55%" align="center">
<img src="./assets/features/news.png" alt="뉴스" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### ⚡ AI Agent 실험
Claude / Codex / Gemini CLI를 호출해 N일치 실험 계획을 생성하고, 매일 해당 일자 섹션을 골라 즉시 실행할 수 있습니다.

</td>
<td width="55%" align="center">
<img src="./assets/features/agent.png" alt="Agent" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### ⚙️ 설정 / 카테고리 매핑
앱→카테고리 매핑 규칙, 카테고리 추가·삭제·이름 변경, LLM Provider, 관심사 키워드, 데이터 경로 등을 설정 탭에서 커스터마이즈할 수 있습니다.

</td>
<td width="55%" align="center">
<img src="./assets/features/settings.png" alt="설정" width="420" />
</td>
</tr>
</table>

---

## 🚀 설치 방법

두 가지 방법이 있습니다 — 그냥 빠르게 써보고 싶다면 **A. 다운로드해서 바로 사용**, 코드를 직접 빌드하거나 기여하고 싶다면 **B. 소스에서 빌드**.

### A. 다운로드해서 바로 사용

정식 릴리스 준비 중입니다. 릴리스가 생성되면 아래 링크에서 `.dmg` 또는 `.zip` 파일을 받을 수 있습니다.

[**📥 최신 릴리스 다운로드 →**](https://github.com/Jungjihyuk/HorongHorong/releases/latest)

> ⚠️ **첫 실행 안내** — 호롱호롱은 아직 Apple Developer 코드 서명 / 공증(notarization)이 되어 있지 않습니다. 처음 실행하면 macOS가 *"확인되지 않은 개발자"* 또는 *"손상된 앱"* 경고를 띄울 수 있습니다. 그 경우:
> 1. **System Settings → Privacy & Security** 로 이동 → "그래도 열기" 클릭
> 2. 또는 터미널에서 한 번 실행:
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/호롱호롱.app
>    ```

<!-- TODO: 첫 .dmg 릴리스 후 위 링크 활성화 -->
<!-- TODO: Homebrew Cask 탭 등록 후 아래 한 줄 설치 추가 예정
```bash
brew install --cask USER/horong/horonghorong
```
-->

### B. 소스에서 빌드

직접 빌드하거나 코드에 기여하고 싶을 때.

#### 요구 사항
- macOS 14.0 이상
- Xcode 16.0 이상
- Swift 6.0
- UI 언어: 한국어
- 데이터 저장: SwiftData (로컬)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`uv`](https://github.com/astral-sh/uv) — *(뉴스 기능 사용 시)* `brew install uv`
- LLM CLI 중 하나 이상 — *(뉴스 / Agent 기능 사용 시)*
  - `claude`, `codex`, `gemini`, `opencode`

#### 빌드 절차

```bash
git clone https://github.com/Jungjihyuk/HorongHorong.git
cd HorongHorong
xcodegen generate
xcodebuild -scheme HorongHorong -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/HorongHorong-*/Build/Products/Debug/호롱호롱.app
```

#### 뉴스 파이프라인 환경 (선택)

```bash
cd Agents/news_report
uv sync
```

---

## 🪔 사용법

각 기능의 자세한 동작·옵션은 별도 문서로 정리되어 있습니다.

| 문서 | 내용 |
|------|------|
| [`USER_GUIDE.md`](USER_GUIDE.md) | 메뉴바 탭별 기본 사용 가이드 |

<!-- TODO: 핵심 동작 1~2개(타이머 시작 / 퀵메모 호출 등)를 GIF로 추가 -->

---

## 🤝 기여 방법

기여는 언제든 환영합니다. 🪔

1. **이슈로 먼저 의견을 남겨주세요** — 버그 / 기능 / 문서 무엇이든 좋습니다.
2. 논의가 정리되면 포크 → 브랜치(`feature/#이슈번호-짧은-설명`) → PR(base: `dev`) 순으로 작업해 주세요.
3. PR 본문은 [`CONTRIBUTING.md`](CONTRIBUTING.md)의 권장 형식을 따라 주세요.
4. 커밋, 이슈, PR 작성은 저장소의 `.claude` 스킬을 사용하면 프로젝트 컨벤션에 맞춰 생성할 수 있습니다.

> 자세한 기여 가이드 — *프로젝트가 추구하는 방향, 빠르게 머지되는 PR 체크리스트, 개발 환경 셋업, 커밋·PR 컨벤션* — 은 [`CONTRIBUTING.md`](CONTRIBUTING.md) ([English](CONTRIBUTING.en.md)) 를 참고해주세요.

### 행동 강령

프로젝트에 참여하기 전 행동 강령을 확인해 주세요.

- [한국어 행동 강령](CODE_OF_CONDUCT.md)
- [English Code of Conduct](CODE_OF_CONDUCT.en.md)

---

## 📄 라이센스

호롱호롱은 **소스 코드**와 **이미지·캐릭터 자산**을 분리해 라이센스를 적용합니다.

| 영역 | 라이센스 | 요약 |
|------|----------|------|
| 소스 코드 | [Apache License 2.0](LICENSE) | 자유로운 사용·수정·재배포 가능 (특허 그랜트 포함) |
| 이미지·캐릭터 (`assets/`) | [© All Rights Reserved](assets/LICENSE) | 호롱호롱 프로젝트 식별 용도로만 사용 가능 |
| "호롱호롱" 명칭·로고 | 정지혁의 비등록 상표 | [상표 정책](assets/LICENSE) 참고 |

### 핵심 요약

- ✅ **소스 코드** — 자유롭게 사용·수정·상업적 이용 가능 (Apache 2.0). 단, 라이센스·저작권·NOTICE 보존 필수.
- ✅ **자산** — 호롱호롱을 *소개·리뷰·보도·인용*하는 용도, 본인 환경 스크린샷 공유는 자유.
- ❌ **자산** — 본인 캐릭터·마스코트로 사칭, 무관한 제품의 식별자로 재사용, 변형 후 본인 작품으로 표시, 상업적 굿즈 제작은 금지.
- 📩 그 외 사용은 [wlgur278@gmail.com](mailto:wlgur278@gmail.com) 으로 문의.

### 제3자 컴포넌트

본 프로젝트는 [HotKey](https://github.com/soffes/HotKey) (MIT License, © Sam Soffes) 를 의존성으로 포함합니다. 자세한 내용은 [`NOTICE`](NOTICE) 참고.

---

## ✨ 기여자

<div align="center">
<a href="https://github.com/Jungjihyuk">
<img src="https://avatars.githubusercontent.com/u/33630505?v=4" width="100px;" alt=""/><br />
<sub><b>정지혁</b></sub></a><br />
<a href="https://github.com" title="Code">🛠️</a> 


🪔 *Made with a small flame.*

</div>
