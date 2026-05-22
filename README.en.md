<div align="center">

# HorongHorong

**Horong** — *the little vessel that holds the flame in your menu bar.*

A horong is a small vessel that protects a quiet flame from going out. <br>
That flame represents hope, aspiration, $\color{#D97706}{\textbf{focus}}$, and personal goals. <br>
Like a horong gathers and shelters its light, this app helps hold scattered $\color{#D97706}{\textbf{focus}}$, collect $\color{#D97706}{\textbf{interests}}$ in one place, and create an $\color{#D97706}{\textbf{environment}}$ where small experiments can begin.

<img src="./assets/intro/yagyong_jeong4.png" alt="HorongHorong" width="450"/>

<br />

[![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift)](https://swift.org)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue)](LICENSE)
[![Assets: All Rights Reserved](https://img.shields.io/badge/assets-All%20Rights%20Reserved-red)](assets/LICENSE)
[![Release](https://img.shields.io/github/v/release/Jungjihyuk/horong-horong?style=flat)](https://github.com/Jungjihyuk/horong-horong/releases)
[![Stars](https://img.shields.io/github/stars/Jungjihyuk/horong-horong?style=flat&logo=github)](https://github.com/Jungjihyuk/horong-horong)

<sub><a href="README.md">한국어</a></sub> · <sub>English</sub>

</div>

---

<div align="center">

> *With one small lamp — illuminate focus, gather interests, and light up small experiments.*

<br />

<a href="https://github.com/Jungjihyuk/horong-horong/releases/latest"><strong>📥 Download Latest Release</strong></a>
 · 
<a href="#b-build-from-source"><strong>Build from Source</strong></a>

<sub>Official releases are still being prepared. For now, you can try the app by building it from source.</sub>

</div>

<br>

**HorongHorong** is a multi-purpose productivity app that lives in the macOS menu bar. <br>
It brings together a `Pomodoro timer`, `app usage tracking`, `quick memos`, `news curation`, and `AI Agent experiments` under one menu bar icon.

The app is currently developed with a Korean UI. Memos, usage records, statistics caches, and settings are stored locally with SwiftData. News and Agent features call CLI tools installed by the user.

### Why This Exists

- **To reconnect scattered $\color{#D97706}{\textbf{focus}}$** — Jumping between a timer, usage tracker, memo app, and news reader can keep breaking the shape of your work. HorongHorong keeps those tools in one lightweight menu bar surface, so you can return to focus without leaving your flow.
- **To gather $\color{#D97706}{\textbf{interests}}$ quickly** — Videos, articles, and trends become heavier as they pile up. HorongHorong collects sources, lets an LLM classify and summarize them, and keeps your interests gathered in one place.
- **To create an $\color{#D97706}{\textbf{environment}}$ for small experiments** — Seeing good information is easy; turning it into something you build is harder. HorongHorong connects AI Agent CLI tools from planning to execution, shortening the path from consumption to creation. Data is stored locally with SwiftData, and AI calls run through CLI tools installed by the user.

## At a Glance

<table>
<tr>
<td align="center" width="60%">
<img src="./assets/features/timer.png" alt="HorongHorong popover from the menu bar" width="380" />
<br />
<sub>Click the menu bar icon to open timer, memo, statistics, news, Agent, and settings in one place.</sub>
</td>
<td align="center" width="40%">
<img src="./assets/logos/horonghorong.png" alt="HorongHorong app icon" width="150" />
<br />
<sub>HorongHorong app icon</sub>
</td>
</tr>
</table>

## 📌 Features

<table>
<tr>
<td width="45%" valign="middle">

### 🕐 Pomodoro Timer
Manage focus and break cycles with presets: 50/5, 100/10, and custom. Choose a focus category so completed sessions are recorded in statistics, and configure how the remaining time appears in the menu bar. When a session ends, HorongHorong shows both a system notification and a floating toast.

</td>
<td width="55%" align="center">
<img src="./assets/features/timer.png" alt="Timer" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📝 Quick Memo
Open a floating input panel from anywhere with a global shortcut. The shortcut is configurable in Settings, and saved memos are stored locally and shown in the menu bar memo tab, sorted by newest first.

</td>
<td width="55%" align="center">
<img src="./assets/features/quick-memo.png" alt="Quick memo" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📊 App Usage Statistics
Track the active app in the background and automatically aggregate time by category: Work / Development / Study / Research / Log / Communication / Entertainment / Other. Check today's or this week's usage from the menu bar summary, or open the detail view for daily, weekly, and monthly charts, Pomodoro summaries, timeline buckets, and per-category app breakdowns. Daily records can be added, edited, or deleted manually, and vacation periods are shown separately in statistics.

</td>
<td width="55%" align="center">
<table>
<tr>
<td align="center" width="50%">
<img src="./assets/features/stats-summary.png" alt="Summary statistics" width="190" />
<sub>Summary</sub>
<br />
</td>
<td align="center" width="50%">
<img src="./assets/features/daily_statistic.png" alt="Daily statistics" width="190" />
<br />
<sub>Daily</sub>
</td>
</tr>
<tr>
<td align="center" width="50%">
<img src="./assets/features/weekly_statistic.png" alt="Weekly statistics" width="190" />
<br />
<sub>Weekly</sub>
</td>
<td align="center" width="50%">
<img src="./assets/features/monthly_statistic.png" alt="Monthly statistics" width="190" />
<br />
<sub>Monthly</sub>
</td>
</tr>
</table>
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### 📰 News Curation
Collect data from channels you frequently use, such as YouTube channels/playlists, Google News, and yozmIT. An LLM builds dynamic categories, filters by relevance, ranks items, summarizes them, and produces category-level trend summaries. News providers support Codex, Claude, Antigravity, Opencode, and Gemini. While running, the app shows pipeline progress from collection through rendering, and results are saved as Markdown reports with metadata.

</td>
<td width="55%" align="center">
<img src="./assets/features/news.png" alt="News" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### ⚡ AI Agent Experiments
Call Codex / Claude / Antigravity / Opencode / Gemini CLI to generate an N-day experiment plan, then run only today's section from the most recent plan. The Agent tab shows three quick-select agents chosen in settings, while the default agent can be selected from all five providers. The experiment root is split automatically into `ideas` and `outputs`.

</td>
<td width="55%" align="center">
<img src="./assets/features/agent.png" alt="Agent" width="420" />
</td>
</tr>

<tr>
<td width="45%" valign="middle">

### ⚙️ Settings Window / Category Mapping
Manage General, Appearance, Timer, Hotkey, Category Mapping, Statistics, News, AI Agent, Memo, Data, and About pages in a separate Settings window. It includes settings search, per-page reset to defaults, light/dark appearance modes, the warm lantern theme, app-to-category rules, idle thresholds, category pairs that are ignored for context-switch counts, news sources and interest keywords, and data paths.

</td>
<td width="55%" align="center">
<img src="./assets/features/settings.png" alt="Settings" width="420" />
</td>
</tr>
</table>

---

## 🚀 Installation

There are two ways to use HorongHorong — choose **A. Download and Run** if you want the quickest path, or **B. Build from Source** if you want to build the app yourself or contribute.

### A. Download and Run

Official releases are still being prepared. Once a release is available, you will be able to download a `.dmg` or `.zip` file from the link below.

[**📥 Download Latest Release →**](https://github.com/Jungjihyuk/horong-horong/releases/latest)

> ⚠️ **First launch notice** — HorongHorong is not yet signed with an Apple Developer certificate or notarized. On first launch, macOS may show an "unidentified developer" or "damaged app" warning. In that case:
> 1. Go to **System Settings → Privacy & Security** and click "Open Anyway".
> 2. Or run this once in Terminal:
>    ```bash
>    xattr -dr com.apple.quarantine /Applications/호롱호롱.app
>    ```

### B. Build from Source

Use this path when you want to build the app directly or contribute to the codebase.

#### Requirements
- macOS 14.0 or later
- Xcode 16.0 or later
- Swift 6.0
- UI language: Korean
- Data storage: SwiftData (local)
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`uv`](https://github.com/astral-sh/uv) — *(required for the news feature)* `brew install uv`
- Python 3 — *(required for the news feature)*
- At least one LLM CLI
  - News: `codex`, `claude`, Antigravity (`agy`), `opencode`, `gemini`
  - Agent experiments: `codex`, `claude`, Antigravity (`agy`), `opencode`, `gemini`

<sub><font color="#6B7280">Note: The Gemini provider is scheduled for service shutdown on June 18, 2026, so it may be removed later.</font></sub>

#### Build Steps

```bash
git clone https://github.com/Jungjihyuk/horong-horong.git
cd horong-horong
xcodegen generate
xcodebuild -scheme HorongHorong -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/HorongHorong-*/Build/Products/Debug/호롱호롱.app
```

#### News Pipeline Environment (Optional)

```bash
cd Agents/news_report
uv sync
```

#### Tests

```bash
xcodebuild -scheme HorongHorong -configuration Debug test
```

---

## 🪔 Usage

Detailed behavior and options for each feature are documented separately.

| Document | Description |
|------|------|
| [`USER_GUIDE.md`](USER_GUIDE.md) | Basic guide for each menu bar tab |

### Data Locations

- Timer sessions, memos, app usage records, statistics caches, and category rules: local SwiftData store
- News reports, logs, and metadata: `data/reports`, `data/logs`, and `data/meta` under the news report path
- Agent experiment plans and outputs: `outputs` under the Agent experiment root
- Agent idea files: `ideas` under the Agent experiment root

---

## 🤝 Contributing

Contributions are welcome.

1. **Open an issue first** — bugs, features, documentation, and questions are all welcome.
2. Once the discussion is clear, fork the repository, create a branch (`feature/#issue-number-short-description`), and open a PR against `dev`.
3. Follow the recommended PR body format in [`CONTRIBUTING.md`](CONTRIBUTING.md).
4. You can use the repository's `.claude` skills to generate commits, issues, and PRs that follow the project conventions.

> For the full contribution guide — including project direction, the fast-merge PR checklist, development setup, and commit/PR conventions — see [`CONTRIBUTING.en.md`](CONTRIBUTING.en.md) ([한국어](CONTRIBUTING.md)).

### Code of Conduct

Please review the Code of Conduct before participating in the project.

- [English Code of Conduct](CODE_OF_CONDUCT.en.md)
- [한국어 행동 강령](CODE_OF_CONDUCT.md)

---

## 📄 License

HorongHorong applies separate licenses to **source code** and **image/character assets**.

| Area | License | Summary |
|------|----------|------|
| Source code | [Apache License 2.0](LICENSE) | Free to use, modify, and redistribute, including patent grant |
| Image/character assets (`assets/`) | [© All Rights Reserved](assets/LICENSE) | May only be used to identify or refer to the HorongHorong project |
| "HorongHorong" name and logo | Unregistered trademark of Jihyeok Jung | See the [trademark policy](assets/LICENSE) |

### Quick Summary

- ✅ **Source code** — Free to use, modify, redistribute, and use commercially under Apache 2.0. You must preserve license, copyright, and NOTICE information.
- ✅ **Assets** — You may use them to introduce, review, report on, or cite HorongHorong, and you may share screenshots from your own environment.
- ❌ **Assets** — Do not impersonate the project character/mascot, reuse it as an identifier for unrelated products, modify it and present it as your own work, or make commercial goods with it.
- 📩 For other uses, contact [wlgur278@gmail.com](mailto:wlgur278@gmail.com).

### Third-Party Components

This project depends on [HotKey](https://github.com/soffes/HotKey) (MIT License, © Sam Soffes). See [`NOTICE`](NOTICE) for details.

---

## ✨ Contributors

<div align="center">
<a href="https://github.com/Jungjihyuk">
<img src="https://avatars.githubusercontent.com/u/33630505?v=4" width="100px;" alt=""/><br />
<sub><b>Jihyeok Jung</b></sub></a><br />
<a href="https://github.com" title="Code">🛠️</a>


🪔 *Made with a small flame.*

</div>
