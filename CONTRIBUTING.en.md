# Contributing to HorongHorong

> Thank you for putting your hand on this small flame. 🪔

This is a short guide for anyone who wants to contribute to **HorongHorong (호롱호롱)**.
It shares both *the path that gets your PR merged faster* and *the direction this project is heading*.

<sub><a href="CONTRIBUTING.md">한국어</a> · English</sub>

---

## 🪔 What this project pursues

HorongHorong is a small lantern. It keeps to the following principles.

1. **Lives on the menu bar, the lightest possible surface**
   — Full-screen windows and complex multi-window management are not the texture of HorongHorong.
2. **Local-first**
   — User data stays on the user's device (SwiftData). Cloud sync and account systems are intentionally absent.
3. **A UX that doesn't break flow**
   — Tools appear and disappear with one shortcut, one click.
4. **Vendor-neutral AI calls**
   — LLMs are invoked through user-installed CLIs (`claude` / `codex` / `gemini` / `opencode`). Direct SDK or server calls are avoided.
5. **Connecting scattered tools ≠ doing everything**
   — HorongHorong is not a *productivity super-app*. It is closer to a *bridge for focus*.

## 🚫 Current Non-goals

In the current phase (v1.x), the following areas are *intentionally out of scope*. None of these doors are permanently closed — see *"Possibly Later"* below.

- **Cloud sync / account systems** (at least through v1.x)
- **Direct integration with external SaaS APIs** — LLMs go through local CLIs only
- **Full-screen / heavy window management** — stays true to the menu-bar form factor
- **Heavy dependencies** — new libraries are added only when their value is clear

> PRs that move against these directions are welcome to spark discussion, but may not be merged at this stage.

## 🌱 Possibly Later

Areas we don't pursue today, but that could legitimately join the project as it grows. If interested, please **open an issue for discussion first** — agreeing on timing and design comes before code.

- **Mobile (iOS / iPadOS) extension** — moving the macOS concept to mobile needs its own design pass.
- **Windows / Linux support** — the meaning of "menu bar" changes per OS, so this is not a port. It needs a *reinterpretation*.
- **Optional sync** — *local-first + opt-in sync* (separate from any account system) that the user can turn on.
- **Direct external API integrations** — only when the value is clearly large beyond what the LLM CLI route covers.
- **Plugin / extension system** — once the contributor ecosystem reaches a meaningful size.

> For these areas, **start small.** A *discussion → small prototype → incremental expansion* path is far closer to a merge than a single large PR.

---

## 🔧 Development environment

### Requirements

- macOS 15.0 or later
- Xcode 16.0 or later
- [`xcodegen`](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- [`uv`](https://github.com/astral-sh/uv) — *(when working on the news pipeline)* `brew install uv`
- At least one LLM CLI — *(when working on news / agent features)*
  - `claude`, `codex`, `gemini`, `opencode`

### Setup

```bash
git clone https://github.com/Jungjihyuk/HorongHorong.git
cd HorongHorong
xcodegen generate
open HorongHorong.xcodeproj
```

### News pipeline (optional)

```bash
cd Agents/news_report
uv sync
```

---

## 🗂 Folder structure (overview)

```
HorongHorong/
├── HorongHorong/
│   ├── Features/        ← new features go here as per-feature folders
│   ├── Models/          ← SwiftData models
│   ├── Services/        ← background work, external-call abstractions
│   ├── Resources/       ← assets, localization
│   ├── Utilities/       ← shared utilities
│   ├── AppState.swift   ← global state
│   └── HorongHorongApp.swift
├── HorongHorongTests/   ← unit tests
├── Agents/              ← Python-based news / agent pipelines
├── Shared/              ← non-code shared assets
├── assets/              ← README / promo images (separately licensed — see assets/LICENSE)
└── docs/                ← planning, design, and operations docs
```

---

## 🐛 How to file a good issue

Please separate issues into **bug / feature / question**.

### Bug report
- Steps to reproduce (1, 2, 3, ...)
- Expected vs actual behavior
- Environment: macOS version / Xcode version / HorongHorong version
- Logs or screenshots (if possible)

### Feature proposal
- *What problem* you want to solve (start with the problem, not the solution)
- How it fits the menu-bar concept
- What alternatives you considered

### Question
- For usage questions, please check [`USER_GUIDE.md`](USER_GUIDE.md) first.

### Issue title / body format

Issue titles use the following format.

```md
[TYPE] Korean title
```

The body should describe real units of work as a Todo checklist.

```md
## Todo
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
```

---

## 🎨 Code style

- **Swift 6.0**, `SWIFT_STRICT_CONCURRENCY: minimal`
- Adding new dependencies requires prior agreement in an issue
- Comments explain *why* — let the code show *what*
- Korean UI strings stay in Korean; code identifiers are in English

---

## ✍️ Commit & PR conventions

### Work types

Issues, commits, and PRs use the following types.

| Type | Criteria |
|------|----------|
| `FEAT` / `feat` | New feature |
| `FIX` / `fix` | Bug fix |
| `DOCS` / `docs` | Documentation change |
| `REFACTOR` / `refactor` | Code structure change without logic changes |
| `REMOVE` / `remove` | File or code removal |
| `CHORE` / `chore` | Build setup, packages, environment configuration |
| `TEST` / `test` | Test code addition or update |
| `ENHANCE` / `enhance` | Performance improvement or enhancement to an existing feature |

### Branches

- Work branches should use the `feature/#issue-number-short-description` format.
- Example: `feature/#12-timer-preset`
- The base branch is **`dev`**.

### Commit messages

Commit messages use the following format.

```md
type: English header message

#issue-number
```

- `type` is lowercase. For example: `feat`, `fix`, `docs`
- The header is written in English, starts with a capital letter, and has no trailing period.
- Include the issue number footer only when it can be inferred from the branch name.

Example:

```md
docs: Update contribution workflow

#12
```

### PR titles

PR titles use the following format.

```md
[TYPE] Korean title
```

- `TYPE` is uppercase. For example: `FEAT`, `FIX`, `DOCS`
- The title is written in Korean, stays under 70 characters, and has no trailing period.

### Recommended PR body

```md
## Overview
High-level summary of the changes

## Change Log
- Main additions or changes

## To Reviewer
- Specific points reviewers should check
- Design decisions, tradeoffs, or logic that needs attention

## Issue Tag
Closes #issue-number
```

### Claude skills (optional)

This repository includes Claude skills under `.claude/skills/` to reduce repetitive work.
If you use Claude, these skills can generate issue, commit, and PR text that follows the project conventions.

- `issue`: Generates an issue title and Todo checklist body
- `commit`: Generates and creates a commit message from staged changes
- `pr`: Generates a PR title and body from commit history and changes

Manual writing is also fine. Please review the final content yourself before submitting.

---

## 💡 Checklist before sending a PR

- [ ] **Did an issue agreement come first?** — PRs without a corresponding issue may be closed.
- [ ] **One PR = one change** — separate refactors from feature work.
- [ ] **Does the branch use the `feature/#issue-number-short-description` format?**
- [ ] **Does the build pass?** — `xcodegen generate && xcodebuild -scheme HorongHorong build`
- [ ] **Are new features isolated under `HorongHorong/Features/<Feature>`?**
- [ ] **If you changed SwiftData models, did you include a migration?**
- [ ] **For UI changes, did you attach at least one screenshot?**
- [ ] **Are Korean UI strings natural?**

---

## 📝 Code of Conduct

Please read the Code of Conduct before participating in this project.

- [한국어 행동 강령](CODE_OF_CONDUCT.md)
- [English Code of Conduct](CODE_OF_CONDUCT.en.md)

---

## 📄 License

- Code contributions are deemed to be licensed under the [Apache License 2.0](LICENSE).
- Image and character assets are governed by a separate license ([`assets/LICENSE`](assets/LICENSE)) — *contributing such assets may require a rights transfer, so please discuss in an issue first.*

---

## 📩 Contact

- General inquiries / bugs / features: GitHub Issues
- License / assets / commercial collaboration: <wlgur278@gmail.com>

🪔 *Made with a small flame — and welcomed by many hands.*
