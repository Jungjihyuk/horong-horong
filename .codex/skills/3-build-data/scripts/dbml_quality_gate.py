#!/usr/bin/env python3
"""Generate a lightweight DB quality-gate report from a DBML file.

This script performs heuristic checks for:
- normalization hints
- ingestion workflow coverage
- scalability readiness
- query performance readiness
- integrity constraints

It can write a markdown report or upsert the report block into an existing
markdown file between markers.
"""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

START_MARKER = "<!-- DBML_QUALITY_GATE:START -->"
END_MARKER = "<!-- DBML_QUALITY_GATE:END -->"


@dataclass
class Column:
    name: str
    raw_type: str
    attrs: str

    @property
    def is_pk(self) -> bool:
        return "pk" in self.attrs.lower()

    @property
    def has_inline_ref(self) -> bool:
        return "ref:" in self.attrs.lower()


@dataclass
class Table:
    name: str
    columns: list[Column] = field(default_factory=list)
    indexes: list[str] = field(default_factory=list)


def strip_quotes(value: str) -> str:
    value = value.strip()
    if (value.startswith("\"") and value.endswith("\"")) or (
        value.startswith("'") and value.endswith("'")
    ):
        return value[1:-1]
    return value


def parse_dbml(text: str) -> tuple[dict[str, Table], list[str]]:
    table_re = re.compile(r"^\s*Table\s+([^\{]+)\{")
    col_re = re.compile(r"^\s*([a-zA-Z_][\w]*)\s+([^\[]+?)(?:\s*\[(.+)\])?\s*$")
    ref_re = re.compile(r"^\s*Ref(?:\s+\w+)?\s*:\s*(.+)$")

    tables: dict[str, Table] = {}
    refs: list[str] = []

    current: Table | None = None
    in_indexes = False

    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("//"):
            continue

        m_table = table_re.match(raw_line)
        if m_table:
            table_name = strip_quotes(m_table.group(1).strip())
            current = Table(name=table_name)
            tables[table_name] = current
            in_indexes = False
            continue

        if current is not None and line == "}":
            current = None
            in_indexes = False
            continue

        if current is None:
            m_ref = ref_re.match(raw_line)
            if m_ref:
                refs.append(m_ref.group(1).strip())
            continue

        if re.match(r"^\s*indexes\s*\{\s*$", raw_line):
            in_indexes = True
            continue

        if in_indexes:
            if line == "}":
                in_indexes = False
            else:
                current.indexes.append(line)
            continue

        m_col = col_re.match(raw_line)
        if not m_col:
            continue

        col_name = m_col.group(1).strip()
        col_type = m_col.group(2).strip()
        col_attrs = (m_col.group(3) or "").strip()
        current.columns.append(Column(name=col_name, raw_type=col_type, attrs=col_attrs))

    return tables, refs


def has_snake_case(name: str) -> bool:
    return bool(re.fullmatch(r"[a-z][a-z0-9_]*", name))


def status(ok: bool) -> str:
    return "PASS" if ok else "WARN"


def build_report(tables: dict[str, Table], refs: list[str]) -> str:
    table_count = len(tables)
    pk_missing = [t.name for t in tables.values() if not any(c.is_pk for c in t.columns)]
    non_snake_tables = [t.name for t in tables.values() if not has_snake_case(t.name)]

    total_columns = sum(len(t.columns) for t in tables.values())
    wide_tables = [t.name for t in tables.values() if len(t.columns) > 25]

    inline_fk_count = sum(1 for t in tables.values() for c in t.columns if c.has_inline_ref)
    total_fk = inline_fk_count + len(refs)

    idx_count = sum(len(t.indexes) for t in tables.values())
    composite_idx_count = sum(
        1
        for t in tables.values()
        for idx in t.indexes
        if idx.count(",") >= 1
    )

    timestamp_cols = {
        "created_at",
        "updated_at",
        "posted_at",
        "ingested_at",
        "occurred_at",
    }
    has_time_dimension = any(
        c.name in timestamp_cols for t in tables.values() for c in t.columns
    )

    repeating_col_pat = re.compile(r"^.+_\d+$")
    repeating_cols = [
        f"{t.name}.{c.name}"
        for t in tables.values()
        for c in t.columns
        if repeating_col_pat.match(c.name)
    ]

    ingestion_keywords = ("raw", "scrap", "ingest", "batch", "log", "queue")
    ingestion_tables = [
        t.name for t in tables.values() if any(k in t.name for k in ingestion_keywords)
    ]
    has_ingestion_status = any(
        c.name in {"status", "retry_count", "error_message"}
        for t in tables.values()
        for c in t.columns
    )

    normalization_ok = not pk_missing and not repeating_cols and not wide_tables
    ingestion_ok = bool(ingestion_tables) and has_ingestion_status
    scalability_ok = has_time_dimension and idx_count > 0
    query_perf_ok = idx_count > 0 and composite_idx_count > 0
    integrity_ok = not pk_missing and total_fk > 0

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")

    summary_rows = [
        ("정규화 점검", status(normalization_ok), "PK 누락/반복 컬럼/과대 테이블 점검"),
        ("데이터 수집 절차", status(ingestion_ok), "raw/ingestion 테이블, status/retry/error 컬럼 점검"),
        ("확장성", status(scalability_ok), "시간 축 컬럼, 기본 인덱스 존재 여부"),
        ("조회 성능", status(query_perf_ok), "인덱스/복합 인덱스 존재 여부"),
        ("무결성", status(integrity_ok), "PK/FK 기반 참조 무결성 점검"),
    ]

    details: list[str] = []
    details.append(f"- 테이블 수: **{table_count}**")
    details.append(f"- 전체 컬럼 수: **{total_columns}**")
    details.append(f"- FK 수(Inline + Ref): **{total_fk}**")
    details.append(f"- 인덱스 수: **{idx_count}** (복합 인덱스: {composite_idx_count})")

    if pk_missing:
        details.append("- WARN: PK 누락 테이블 -> " + ", ".join(pk_missing))
    if non_snake_tables:
        details.append("- WARN: snake_case 위반 테이블 -> " + ", ".join(non_snake_tables))
    if wide_tables:
        details.append("- WARN: 컬럼 25개 초과 테이블 -> " + ", ".join(wide_tables))
    if repeating_cols:
        details.append("- WARN: 반복 컬럼 패턴(_1,_2,...) -> " + ", ".join(repeating_cols))
    if not ingestion_tables:
        details.append("- WARN: ingestion 흐름을 나타내는 테이블(raw/scrap/ingest/batch/log) 미검출")
    if not has_ingestion_status:
        details.append("- WARN: status/retry_count/error_message 컬럼 미검출")
    if idx_count == 0:
        details.append("- WARN: 인덱스 정의 미검출")
    if composite_idx_count == 0:
        details.append("- WARN: 복합 인덱스 정의 미검출")
    if not has_time_dimension:
        details.append("- WARN: 시간 축 컬럼(created_at/updated_at/posted_at 등) 미검출")

    rows_md = "\n".join(f"| {a} | {b} | {c} |" for a, b, c in summary_rows)
    details_md = "\n".join(details)

    return (
        f"### DBML 자동 품질 게이트\n"
        f"- 생성 시각: {now}\n\n"
        f"| 항목 | 결과 | 근거 |\n"
        f"|---|---|---|\n"
        f"{rows_md}\n\n"
        f"#### 상세\n"
        f"{details_md}\n"
    )


def upsert_report(target_path: Path, report_md: str) -> None:
    block = f"{START_MARKER}\n{report_md}\n{END_MARKER}"
    if not target_path.exists():
        target_path.write_text(block + "\n", encoding="utf-8")
        return

    content = target_path.read_text(encoding="utf-8")
    if START_MARKER in content and END_MARKER in content:
        pattern = re.compile(
            rf"{re.escape(START_MARKER)}.*?{re.escape(END_MARKER)}",
            flags=re.DOTALL,
        )
        updated = pattern.sub(block, content)
    else:
        suffix = "\n\n" if not content.endswith("\n") else "\n"
        updated = content + suffix + block + "\n"

    target_path.write_text(updated, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run heuristic DBML quality checks.")
    parser.add_argument("--dbml", required=True, help="Path to source DBML file")
    parser.add_argument(
        "--out",
        help=(
            "Optional markdown file path to upsert quality-gate block. "
            "If omitted, print report to stdout."
        ),
    )

    args = parser.parse_args()

    dbml_path = Path(args.dbml)
    if not dbml_path.exists():
        raise SystemExit(f"DBML not found: {dbml_path}")

    dbml_text = dbml_path.read_text(encoding="utf-8")
    tables, refs = parse_dbml(dbml_text)
    report = build_report(tables, refs)

    if args.out:
        out_path = Path(args.out)
        upsert_report(out_path, report)
        print(f"Updated quality gate report in: {out_path}")
    else:
        print(report)


if __name__ == "__main__":
    main()
