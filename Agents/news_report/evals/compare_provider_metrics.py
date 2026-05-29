"""여러 provider의 research run metrics를 표와 JSON으로 비교한다."""

from __future__ import annotations

import argparse
import json
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast


JsonObject = dict[str, object]

TABLE_COLUMNS = [
    "provider",
    "candidates",
    "sourceInsights",
    "bundles",
    "trendInsights",
    "warnings",
    "providerFailures",
    "stageFailures",
    "avgLatencyMs",
    "providerCalls",
]


@dataclass(frozen=True)
class CliArgs:
    """compare_provider_metrics CLI 인자."""

    metrics: list[Path]
    output: Path | None
    format: str


def compare_provider_metrics(metrics_paths: Sequence[Path]) -> JsonObject:
    """여러 provider metrics JSON을 비교 가능한 행 목록으로 변환한다."""
    rows = [row_from_metrics(load_json_object(path), path) for path in metrics_paths]
    return {
        "providers": rows,
        "bestBy": best_by(rows),
    }


def row_from_metrics(metrics: Mapping[str, object], path: Path) -> JsonObject:
    """research_run_metrics 출력 JSON 하나를 비교표 row로 변환한다."""
    artifact_counts = mapping_value(metrics.get("artifactCounts"))
    provider = provider_name(metrics, path)
    provider_calls = int_value(metrics.get("providerCalls"))
    provider_failures = int_value(metrics.get("providerFailures"))
    stage_failures = int_value(metrics.get("stageFailures"))
    provider_completions = int_value(metrics.get("providerCompletions"))

    return {
        "provider": provider,
        "jobId": string_value(metrics.get("jobId")),
        "reportDate": string_value(metrics.get("reportDate")),
        "sourceCandidates": int_value(artifact_counts.get("sourceCandidates")),
        "sourceInsights": int_value(artifact_counts.get("sourceInsights")),
        "insightBundles": int_value(artifact_counts.get("insightBundles")),
        "trendInsights": int_value(artifact_counts.get("trendInsights")),
        "warningCount": int_value(metrics.get("warningCount")),
        "providerCalls": provider_calls,
        "providerCompletions": provider_completions,
        "providerFailures": provider_failures,
        "stageFailures": stage_failures,
        "avgProviderLatencyMs": metrics.get("avgProviderLatencyMs"),
        "successRate": success_rate(provider_calls, provider_failures),
        "metricsPath": str(path),
    }


def best_by(rows: Sequence[Mapping[str, object]]) -> JsonObject:
    """비교표에서 빠르게 볼 대표 우수 provider를 계산한다."""
    return {
        "mostSourceCandidates": provider_for_max(rows, "sourceCandidates"),
        "mostSourceInsights": provider_for_max(rows, "sourceInsights"),
        "mostTrendInsights": provider_for_max(rows, "trendInsights"),
        "fewestWarnings": provider_for_min(rows, "warningCount"),
        "fewestProviderFailures": provider_for_min(rows, "providerFailures"),
        "lowestAvgLatencyMs": provider_for_min(rows, "avgProviderLatencyMs"),
    }


def render_table(comparison: Mapping[str, object]) -> str:
    """provider 비교 결과를 사람이 읽는 Markdown table로 렌더링한다."""
    rows = list_value(comparison.get("providers"))
    table_rows = [table_row(cast(Mapping[str, object], row)) for row in rows]
    widths = column_widths(table_rows)
    header = format_row(dict(zip(TABLE_COLUMNS, TABLE_COLUMNS, strict=True)), widths)
    separator = format_row(
        {column: "-" * widths[column] for column in TABLE_COLUMNS},
        widths,
    )
    body = [format_row(row, widths) for row in table_rows]
    return "\n".join([header, separator, *body])


def table_row(row: Mapping[str, object]) -> dict[str, str]:
    """comparison row를 table column 이름에 맞춰 변환한다."""
    return {
        "provider": string_value(row.get("provider")),
        "candidates": str(int_value(row.get("sourceCandidates"))),
        "sourceInsights": str(int_value(row.get("sourceInsights"))),
        "bundles": str(int_value(row.get("insightBundles"))),
        "trendInsights": str(int_value(row.get("trendInsights"))),
        "warnings": str(int_value(row.get("warningCount"))),
        "providerFailures": str(int_value(row.get("providerFailures"))),
        "stageFailures": str(int_value(row.get("stageFailures"))),
        "avgLatencyMs": format_optional_int(row.get("avgProviderLatencyMs")),
        "providerCalls": str(int_value(row.get("providerCalls"))),
    }


def column_widths(rows: Sequence[Mapping[str, str]]) -> dict[str, int]:
    """Markdown table column 폭을 계산한다."""
    widths = {column: len(column) for column in TABLE_COLUMNS}
    for row in rows:
        for column in TABLE_COLUMNS:
            widths[column] = max(widths[column], len(row.get(column, "")))
    return widths


def format_row(row: Mapping[str, str], widths: Mapping[str, int]) -> str:
    """Markdown table row를 만든다."""
    cells = [row.get(column, "").ljust(widths[column]) for column in TABLE_COLUMNS]
    return "| " + " | ".join(cells) + " |"


def provider_name(metrics: Mapping[str, object], path: Path) -> str:
    """metrics JSON 또는 파일명에서 provider 이름을 추론한다."""
    provider = metrics.get("provider")
    if isinstance(provider, str) and provider:
        return provider

    job_id = string_value(metrics.get("jobId"))
    for name in ["ollama", "codex", "claude", "gemini", "antigravity"]:
        if name in job_id.lower() or name in path.stem.lower():
            return name
    return path.stem


def provider_for_max(rows: Sequence[Mapping[str, object]], key: str) -> str | None:
    """key 값이 가장 큰 provider를 반환한다."""
    if not rows:
        return None
    return string_value(max(rows, key=lambda row: numeric_sort_value(row.get(key))).get("provider"))


def provider_for_min(rows: Sequence[Mapping[str, object]], key: str) -> str | None:
    """key 값이 가장 작은 provider를 반환한다. None 값은 비교에서 뒤로 보낸다."""
    valid_rows = [row for row in rows if row.get(key) is not None]
    if not valid_rows:
        return None
    return string_value(min(valid_rows, key=lambda row: numeric_sort_value(row.get(key))).get("provider"))


def success_rate(provider_calls: int, provider_failures: int) -> float | None:
    """provider structured output 성공률을 계산한다."""
    if provider_calls <= 0:
        return None
    return (provider_calls - provider_failures) / provider_calls


def load_json_object(path: Path) -> JsonObject:
    """JSON 파일을 object로 읽는다."""
    parsed = cast(object, json.loads(path.read_text(encoding="utf-8")))
    if not isinstance(parsed, dict):
        raise ValueError(f"JSON object가 아닙니다: {path}")
    return cast(JsonObject, parsed)


def write_json(path: Path, payload: Mapping[str, object]) -> None:
    """JSON payload를 파일에 쓴다."""
    path.parent.mkdir(parents=True, exist_ok=True)
    _ = path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def mapping_value(value: object) -> Mapping[str, object]:
    """mapping 값이면 그대로 반환하고, 아니면 빈 mapping으로 취급한다."""
    if isinstance(value, Mapping):
        return cast(Mapping[str, object], value)
    return {}


def list_value(value: object) -> Sequence[object]:
    """list 값이면 그대로 반환하고, 아니면 빈 list로 취급한다."""
    if isinstance(value, list):
        return cast(list[object], value)
    return []


def string_value(value: object) -> str:
    """문자열 값을 안전하게 읽는다."""
    return value if isinstance(value, str) else ""


def int_value(value: object) -> int:
    """정수 값을 안전하게 읽는다."""
    return value if isinstance(value, int) else 0


def numeric_sort_value(value: object) -> float:
    """정렬에 쓸 숫자 값을 만든다."""
    if isinstance(value, int | float):
        return float(value)
    return 0.0


def format_optional_int(value: object) -> str:
    """table에 표시할 선택 정수 값을 만든다."""
    if isinstance(value, int):
        return str(value)
    return "-"


def parse_args(argv: Sequence[str] | None = None) -> CliArgs:
    """CLI 인자를 파싱한다."""
    parser = argparse.ArgumentParser(
        description="여러 research run metrics JSON을 provider별로 비교한다."
    )
    _ = parser.add_argument(
        "--metrics",
        action="append",
        required=True,
        type=Path,
        help="evals.research_run_metrics 출력 JSON 경로. 여러 번 지정 가능.",
    )
    _ = parser.add_argument("--output", type=Path, help="비교 결과 JSON 저장 경로.")
    _ = parser.add_argument(
        "--format",
        choices=["table", "json"],
        default="table",
        help="stdout 출력 형식.",
    )
    namespace = parser.parse_args(argv)
    return CliArgs(
        metrics=cast(list[Path], namespace.metrics),
        output=cast(Path | None, namespace.output),
        format=cast(str, namespace.format),
    )


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entrypoint."""
    args = parse_args(argv)
    comparison = compare_provider_metrics(args.metrics)
    if args.output:
        write_json(args.output, comparison)

    if args.format == "json":
        print(json.dumps(comparison, ensure_ascii=False, indent=2))
    else:
        print(render_table(comparison))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
