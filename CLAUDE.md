# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## 5. Architecture (in-progress refactor)

The app is migrating to **MVVM + Repository** layers. Before writing Swift, read:

- `docs/5. 운영/프로젝트 운영/11. 협업 가이드/Swift 코드 컨벤션.md` — **hard rules + comment style.** Read this first.
- `docs/2. 설계/3. 시스템 설계서/기술 의사결정/ADR-002-MVVM-Repository-AgentGateway-채택.md` — why
- `docs/5. 운영/프로젝트 운영/12. 기술 문서/Architecture/app-folder-structure-decisions.md` — where files go
- `docs/5. 운영/프로젝트 운영/12. 기술 문서/Refactoring/2026-09-01-app-wide-mvvm-repository-migration.md` — what is done vs pending

Five rules that override convenience (details and rationale in the convention doc):

1. **No half-migration.** A view holds either `@Query` or a ViewModel — never both. Both costs otherwise.
2. **Never persist time-dependent derived values.** Test: "does this go stale at midnight?" `bucketRaw` ❌ / `deadline` ✅
3. **`@ViewBuilder` methods are not render boundaries.** Rows must be `struct` + `Equatable`.
4. **`@Model` never crosses a layer boundary.** It is not `Sendable`; return DTOs. The app target is in Swift 6 language mode (`SWIFT_VERSION: "6.0"`), so the compiler does enforce this — `SWIFT_STRICT_CONCURRENCY: minimal` in `project.yml` is dead config that Swift 6 mode ignores. The `HorongAI` package is the exception (`.swiftLanguageMode(.v5)`).
5. **`static let` for Formatters and NSRegularExpression.**

Two project-specific gotchas:

- `#Predicate` translation failures surface at **runtime**, not compile time. Verify on device after any predicate change.
- Build needs `-skipPackagePluginValidation -skipMacroValidation` or mlx-swift plugin validation fails.

Measure before optimizing: `let _ = Self._printChanges()` + 10k synthetic records. In 2026-08-31 two of three code-reading hypotheses were disproved by measurement, and the top cause was not on the list.
