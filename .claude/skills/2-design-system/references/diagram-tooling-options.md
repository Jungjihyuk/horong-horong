> 경로 해석: 이 문서의 경로는 `.claude/docs-file.json`의 `docs_root` + `sections` 값으로 해석한다.

# Diagram Tooling Options

## Recommended Default

Use Excalidraw markdown inside `{3_system_design}` as the primary architecture diagram format.

Why:
- This repository already uses Obsidian + Excalidraw markdown files.
- Diagram files are versioned as plain markdown in Git.
- The team can keep docs and diagrams in the same workspace without external dependencies.

## Decision Matrix

- Excalidraw (default):
  - Best for: local-first docs, hand-drawn readability, quick edits in Obsidian.
  - Tradeoff: large diagrams can be harder to auto-layout.
- Mermaid (secondary):
  - Best for: compact text-based overview diagrams in markdown.
  - Tradeoff: complex architecture can become visually dense.
- Eraser (optional external):
  - Best for: polished layout, fast diagram-as-code, collaborative review.
  - Tradeoff: external SaaS dependency and account workflow.
- Structurizr (optional external):
  - Best for: C4 model consistency and model-driven multi-view diagrams.
  - Tradeoff: steeper setup and DSL-first workflow.

## Operational Policy

1. Keep a lightweight Mermaid summary in `시스템 설계서.md`.
2. Keep detailed architecture in Excalidraw markdown.
3. Use external tools only when collaboration/presentation quality requirements exceed local workflow.
4. Always persist outputs back into `{3_system_design}` as markdown link or exported image.

## Official References

- Mermaid syntax reference: https://mermaid.js.org/intro/syntax-reference.html
- Mermaid flowchart syntax: https://mermaid.js.org/syntax/flowchart.html
- Obsidian Excalidraw plugin: https://github.com/zsviczian/obsidian-excalidraw-plugin
- Eraser diagram-as-code: https://docs.eraser.io/docs/diagram-as-code
- Structurizr DSL: https://docs.structurizr.com/dsl
