"""deep research 단일 실행의 artifact/trace 정량 지표를 계산한다.

- meta JSON: runner.py를 실행했을 때 생성되는 분석용 메타 데이터 파일
    - source 후보가 몇 개였는지
    - source insight가 몇 개 만들어졌는지
    - trend insight가 몇 개 만들어졌는지
    - warning이 몇 개인지
- trace JSONL: runner.py를 실행했을 때 생성되는 추적 데이터
    - provider 호출이 몇 번 있었는지
    - 실패가 몇 번 있었는지
    - 평균 latency가 얼마였는지
    - 어떤 schema를 많이 호출했는지
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import cast


JsonObject = dict[str, object]


@dataclass(frozen=True)
class CliArgs:
    """research_run_metrics CLI 인자."""

    meta: Path
    trace: Path | None
    output: Path | None


ARTIFACT_COUNT_KEYS = {
    "sourceItems": "sourceItems",
    "extractedArticles": "extractedArticles",
    "keywordMatches": "keywordMatches",
    "relevanceJudgments": "relevanceJudgments",
    "sourceCandidates": "sourceCandidates",
    "categoryAssignments": "categoryAssignments",
    "sourceInsights": "sourceInsights",
    "insightBundles": "insightBundles",
    "keywordInsights": "keywordInsights",
    "trendInsights": "trendInsights",
}


def research_run_metrics(meta_path: Path, trace_path: Path | None = None) -> JsonObject:
    """report meta와 trace를 읽어 provider 비교용 정량 지표를 반환한다."""
    meta = load_json_object(meta_path)
    trace_events = load_trace_events(trace_path) if trace_path else []

    return {
        "jobId": string_value(meta.get("jobId")),
        "reportDate": string_value(meta.get("reportDate")),
        "reportPath": string_value(meta.get("reportPath")),
        "itemCount": int_value(meta.get("itemCount")),
        "artifactCounts": artifact_counts(meta),
        "warningCount": len(list_value(meta.get("warnings"))),
        "sourceStats": meta.get("sourceStats") if isinstance(meta.get("sourceStats"), dict) else {},
        "providerCalls": count_events(trace_events, "provider_started"),
        "providerCompletions": count_events(trace_events, "provider_completed"),
        "providerFailures": count_events(trace_events, "provider_failed"),
        "stageFailures": count_events(trace_events, "stage_failed"),
        "avgProviderLatencyMs": average_provider_latency(trace_events),
        "schemaCounts": schema_counts(trace_events),
        "repairRate": repair_rate(trace_events),
        "structuredOutputReliability": structured_output_reliability(trace_events),
    }


def artifact_counts(meta: Mapping[str, object]) -> JsonObject:
    """researchArtifacts 안의 주요 artifact 개수를 계산한다."""
    research_artifacts = meta.get("researchArtifacts")
    if not isinstance(research_artifacts, Mapping):
        return {output_key: 0 for output_key in ARTIFACT_COUNT_KEYS.values()}
    artifact_map = cast(Mapping[str, object], research_artifacts)

    counts: JsonObject = {}
    for artifact_key, output_key in ARTIFACT_COUNT_KEYS.items():
        counts[output_key] = len(list_value(artifact_map.get(artifact_key)))
    counts["reportContent"] = 1 if artifact_map.get("reportContent") else 0
    counts["categoryTaxonomy"] = 1 if artifact_map.get("categoryTaxonomy") else 0
    return counts


def load_json_object(path: Path) -> JsonObject:
    """JSON 파일을 object로 읽는다."""
    parsed = cast(object, json.loads(path.read_text(encoding="utf-8")))
    if not isinstance(parsed, dict):
        raise ValueError(f"JSON object가 아닙니다: {path}")
    return cast(JsonObject, parsed)


def load_trace_events(path: Path) -> list[JsonObject]:
    """Trace JSONL 파일을 event object 목록으로 읽는다."""
    events: list[JsonObject] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        stripped = line.strip()
        if not stripped:
            continue
        parsed = cast(object, json.loads(stripped))
        if not isinstance(parsed, dict):
            raise ValueError(f"Trace event가 JSON object가 아닙니다: {path}:{line_number}")
        events.append(cast(JsonObject, parsed))
    return events


def count_events(events: Iterable[Mapping[str, object]], event_name: str) -> int:
    """특정 trace event 이름의 개수를 센다."""
    return sum(1 for event in events if event.get("event") == event_name)


def schema_counts(events: Iterable[Mapping[str, object]]) -> JsonObject:
    """provider structured output schema 호출 개수를 계산한다."""
    counter: Counter[str] = Counter()
    for event in events:
        if event.get("event") != "provider_started":
            continue
        payload = payload_object(event)
        if payload.get("operation") != "structured_output":
            continue
        schema = payload.get("schema")
        if isinstance(schema, str) and schema:
            counter[schema] += 1
    return dict(counter)


def average_provider_latency(events: Iterable[Mapping[str, object]]) -> int | None:
    """provider completed/failed 이벤트의 평균 duration_ms를 계산한다."""
    durations: list[int] = []
    for event in events:
        if event.get("event") not in {"provider_completed", "provider_failed"}:
            continue
        duration = event.get("duration_ms")
        if isinstance(duration, int):
            durations.append(duration)

    if not durations:
        return None
    return round(sum(durations) / len(durations))


def repair_rate(events: Iterable[Mapping[str, object]]) -> float | None:
    """repair_attempted payload가 있을 때 repair 비율을 계산한다."""
    known_attempts = 0
    repairs = 0
    for event in events:
        if event.get("event") != "provider_completed":
            continue
        payload = payload_object(event)
        repair_attempted = payload.get("repair_attempted")
        if not isinstance(repair_attempted, bool):
            continue
        known_attempts += 1
        if repair_attempted:
            repairs += 1

    if known_attempts == 0:
        return None
    return repairs / known_attempts


def structured_output_reliability(events: Iterable[Mapping[str, object]]) -> JsonObject:
    """provider 구조화 출력의 1차 성공 / repair 복구 / 최종 실패 분해 지표를 계산한다.

    - provider_completed payload의 repair_attempted(bool)로 1차 성공(False)과
      repair 복구(True)를 구분한다.
    - provider_failed는 repair까지 실패한 최종 실패로 본다.
    - repair_attempted 데이터가 하나도 없으면(producer 미배선) repair 의존 비율은
      None으로 둔다. 최종 실패율은 repair 필드와 무관하므로 호출이 있으면 계산한다.
    """
    completed_total = 0
    first_pass = 0
    repaired = 0
    failures = 0
    for event in events:
        name = event.get("event")
        if name == "provider_completed":
            completed_total += 1
            repair_attempted = payload_object(event).get("repair_attempted")
            if repair_attempted is True:
                repaired += 1
            elif repair_attempted is False:
                first_pass += 1
        elif name == "provider_failed":
            failures += 1

    total = completed_total + failures
    repair_data_available = (first_pass + repaired) > 0
    repair_hits = repaired + failures

    return {
        "totalCalls": total,
        "firstPassSuccesses": first_pass,
        "repairedSuccesses": repaired,
        "failures": failures,
        "firstPassRate": (first_pass / total) if (total and repair_data_available) else None,
        "repairRecoveryRate": (repaired / repair_hits)
        if (repair_data_available and repair_hits)
        else None,
        "finalFailureRate": (failures / total) if total else None,
    }


def payload_object(event: Mapping[str, object]) -> Mapping[str, object]:
    """trace event payload를 object mapping으로 읽는다."""
    payload = event.get("payload")
    if isinstance(payload, Mapping):
        return cast(Mapping[str, object], payload)
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


def parse_args(argv: Sequence[str] | None = None) -> CliArgs:
    """CLI 인자를 파싱한다."""
    parser = argparse.ArgumentParser(
        description="report meta JSON과 trace JSONL에서 research run metrics eval을 계산한다."
    )
    _ = parser.add_argument("--meta", required=True, type=Path)
    _ = parser.add_argument("--trace", type=Path)
    _ = parser.add_argument("--output", type=Path)
    namespace = parser.parse_args(argv)
    return CliArgs(
        meta=cast(Path, namespace.meta),
        trace=cast(Path | None, namespace.trace),
        output=cast(Path | None, namespace.output),
    )


def main(argv: Sequence[str] | None = None) -> int:
    """CLI entrypoint."""
    args = parse_args(argv)
    metrics = research_run_metrics(args.meta, args.trace)
    output_text = json.dumps(metrics, ensure_ascii=False, indent=2)
    if args.output:
        _ = args.output.write_text(output_text + "\n", encoding="utf-8")
    else:
        print(output_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
