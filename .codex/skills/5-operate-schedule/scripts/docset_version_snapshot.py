#!/usr/bin/env python3
"""Build a version snapshot table for docs 1..6 and compute DOCSET ID."""

from __future__ import annotations

import argparse
import hashlib
import re
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

DOC_PATHS = [
    "1. 프로젝트 정의서/프로젝트 정의서.md",
    "2. 요구사항 명세서/요구사항 명세서.md",
    "3. UI 명세서/main.md",
    "4. 시스템 설계서/시스템 설계서.md",
    "5. DB 명세서/DB 명세서 대시보드.md",
    "6. API 명세서/v0.1.0/API 명세서 대시보드.md",
]

VERSION_PATTERNS = [
    re.compile(r"^version\s*:\s*([\w\.-]+)\s*$", re.IGNORECASE),
    re.compile(r"버전\s*[:：]\s*(v?\d+(?:\.\d+){0,2})", re.IGNORECASE),
    re.compile(r"\b(v\d+\.\d+\.\d+)\b", re.IGNORECASE),
]


@dataclass
class DocInfo:
    idx: int
    rel_path: str
    exists: bool
    version: str
    mtime: str


def extract_version(text: str) -> str:
    lines = text.splitlines()[:120]
    for line in lines:
        for pat in VERSION_PATTERNS:
            m = pat.search(line.strip())
            if m:
                return m.group(1)
    return "v0.0.0"


def compute_docset_id(items: list[DocInfo]) -> str:
    basis = "\n".join(f"{i.rel_path}|{i.version}|{i.mtime}" for i in items)
    h = hashlib.sha256(basis.encode("utf-8")).hexdigest()[:8]
    d = datetime.now().strftime("%Y%m%d")
    return f"DOCSET-{d}-{h}"


def build_markdown(items: list[DocInfo], docset_id: str) -> str:
    lines = [
        "# DOCSET Version Snapshot",
        "",
        f"- DOCSET ID: `{docset_id}`",
        f"- Generated At: `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`",
        "",
        "| 문서 | 경로 | 버전 | 마지막 수정일 | 존재 여부 |",
        "|---|---|---|---|---|",
    ]
    for i in items:
        lines.append(
            f"| {i.idx} | `{i.rel_path}` | `{i.version}` | `{i.mtime}` | {'Y' if i.exists else 'N'} |"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate docs 1-6 version snapshot")
    parser.add_argument("--docs-root", default="docs", help="Docs root path")
    parser.add_argument("--out", help="Optional output markdown path")
    args = parser.parse_args()

    root = Path(args.docs_root)

    items: list[DocInfo] = []
    for idx, rel in enumerate(DOC_PATHS, start=1):
        path = root / rel
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="ignore")
            version = extract_version(text)
            mtime = datetime.fromtimestamp(path.stat().st_mtime).strftime("%Y-%m-%d")
            items.append(DocInfo(idx=idx, rel_path=f"{args.docs_root}/{rel}", exists=True, version=version, mtime=mtime))
        else:
            items.append(DocInfo(idx=idx, rel_path=f"{args.docs_root}/{rel}", exists=False, version="v0.0.0", mtime="-"))

    docset_id = compute_docset_id(items)
    md = build_markdown(items, docset_id)

    if args.out:
        out = Path(args.out)
        out.write_text(md, encoding="utf-8")
        print(f"Wrote snapshot: {out}")
    else:
        print(md)


if __name__ == "__main__":
    main()
