---
title: {프로젝트명} 요구사항 명세서
version: 🔖 v{VERSION}
author: {작성자}
created: {YYYY-MM-DD}
updated: {YYYY-MM-DD}
project_status: {✅ 확정 | 🔄 검토중 | 📝 초안}
related:
  - "[[프로젝트 정의서]]"
tags:
  - 요구사항명세서
  - {프로젝트 태그}
---

# 📋 {프로젝트명} 요구사항 명세서 — v{VERSION}

*프로젝트 정의서 v{VERSION}의 핵심 기능을 구체적인 요구사항으로 정의하는 문서*

> **범위**: v{VERSION} 요구사항만 다룬다.

> [!tip] Obsidian 사용 가이드
> - 테이블은 **Dataview**가 자동 렌더링합니다 (Reading 모드에서 확인)
> - `requirement_priority` 필드 클릭 시 **Metadata Menu 드롭다운**으로 우선순위 변경 가능
> - 각 요구사항은 개별 파일로 관리됩니다 (`requirements/` 폴더)
> - 새 항목 추가: `requirements/` 폴더에 파일 생성 후 `requirement` 태그 부여

---

## [1] 기능적 요구사항 (Functional Requirements)

<!-- 
  프로젝트의 핵심 기능 그룹별로 아래 블록을 반복한다.
  - 섹션 번호(1.1, 1.2, ...)는 requirements/ 파일의 group 필드와 매핑
  - 관련 시나리오는 프로젝트 정의서의 사용자 스토리 참조
-->

### 1.1 {기능 그룹명}
> 관련 시나리오: {사용자 스토리 또는 유즈케이스 요약}

```dataviewjs
const {fieldModifier: f} = this.app.plugins.plugins["metadata-menu"].api;

const pages = dv.pages('#requirement')
    .filter(p => p.group === "1.1")
    .sort(p => p.id, 'asc');

dv.table(
    ["ID", "카테고리", "요구사항", "상세설명", "우선순위", "담당자", "완료"],
    pages.map(p => [
        p.file.link,
        f(dv, p, "category"),
        f(dv, p, "description"),
        f(dv, p, "detail"),
        f(dv, p, "requirement_priority"),
        f(dv, p, "incharge"),
        f(dv, p, "completed")
    ])
);
```

### 1.2 {기능 그룹명}
> 관련 시나리오: {사용자 스토리 또는 유즈케이스 요약}

```dataviewjs
const {fieldModifier: f} = this.app.plugins.plugins["metadata-menu"].api;

const pages = dv.pages('#requirement')
    .filter(p => p.group === "1.2")
    .sort(p => p.id, 'asc');

dv.table(
    ["ID", "카테고리", "요구사항", "상세설명", "우선순위", "담당자", "완료"],
    pages.map(p => [
        p.file.link,
        f(dv, p, "category"),
        f(dv, p, "description"),
        f(dv, p, "detail"),
        f(dv, p, "requirement_priority"),
        f(dv, p, "incharge"),
        f(dv, p, "completed")
    ])
);
```

<!-- 기능 그룹이 더 있으면 1.3, 1.4, ... 로 위 블록을 복제하여 추가 -->

---

## [2] 비기능적 요구사항 (Non-functional Requirements)

<!--
  NFR 분류 기준 (프로젝트에 맞게 조정):
  - 성능, 안정성, 보안, 데이터 품질, 인프라 및 배포, 확장성 등
  - 섹션 번호(2.1, 2.2, ...)는 requirements/ 파일의 group 필드와 매핑
-->

### 2.1 {품질 속성명}

```dataviewjs
const {fieldModifier: f} = this.app.plugins.plugins["metadata-menu"].api;

const pages = dv.pages('#requirement')
    .filter(p => p.group === "2.1")
    .sort(p => p.id, 'asc');

dv.table(
    ["ID", "카테고리", "요구사항", "상세설명", "우선순위", "담당자", "완료"],
    pages.map(p => [
        p.file.link,
        f(dv, p, "category"),
        f(dv, p, "description"),
        f(dv, p, "detail"),
        f(dv, p, "requirement_priority"),
        f(dv, p, "incharge"),
        f(dv, p, "completed")
    ])
);
```

### 2.2 {품질 속성명}

```dataviewjs
const {fieldModifier: f} = this.app.plugins.plugins["metadata-menu"].api;

const pages = dv.pages('#requirement')
    .filter(p => p.group === "2.2")
    .sort(p => p.id, 'asc');

dv.table(
    ["ID", "카테고리", "요구사항", "상세설명", "우선순위", "담당자", "완료"],
    pages.map(p => [
        p.file.link,
        f(dv, p, "category"),
        f(dv, p, "description"),
        f(dv, p, "detail"),
        f(dv, p, "requirement_priority"),
        f(dv, p, "incharge"),
        f(dv, p, "completed")
    ])
);
```

<!-- 품질 속성이 더 있으면 2.3, 2.4, ... 로 위 블록을 복제하여 추가 -->

---

## [3] 요구사항 추적 매트릭스 (Traceability Matrix)

> 프로젝트 정의서 핵심 기능 → 요구사항 ID 매핑

| 핵심 기능 (정의서) | 관련 요구사항 ID |
|-------------------|-----------------|
| **{기능 A}** | FR-001 ~ FR-NNN |
| **{기능 B}** | FR-NNN ~ FR-NNN |

| 성공 기준 (정의서) | 관련 요구사항 ID |
|-------------------|-----------------|
| {성공 기준 1} | NFR-NNN |
| {성공 기준 2} | FR-NNN, NFR-NNN |

---

## [4] 전체 요구사항 요약

```dataviewjs
const pages = dv.pages('#requirement')
    .filter(p => p.id && (String(p.id).startsWith("FR") || String(p.id).startsWith("NFR")));
const p0 = pages.filter(p => String(p.requirement_priority ?? "").includes("P0")).length;
const p1 = pages.filter(p => String(p.requirement_priority ?? "").includes("P1")).length;
const p2 = pages.filter(p => String(p.requirement_priority ?? "").includes("P2")).length;
dv.paragraph(`총 **${pages.length}건** — 🔴 P0: ${p0}건 / 🟡 P1: ${p1}건 / 🟢 P2: ${p2}건`);
```

---

## [5] 용어 정의

| 용어 | 설명 |
|------|------|
| **{용어 1}** | {설명} |
| **{용어 2}** | {설명} |

---
