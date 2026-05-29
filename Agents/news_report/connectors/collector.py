"""여러 뉴스 source를 순회하며 수집 결과와 통계를 만든다."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from time import perf_counter

from connectors.protocols import NewsConnector
from connectors.registry import create_connector, is_supported_source
from tracing.trace_writer import TraceWriter


LogFn = Callable[[str], None]
ConnectorFactoryFn = Callable[[dict, int], NewsConnector]


@dataclass
class CollectResult:
    """뉴스 source 수집 stage의 결과."""

    items: list[dict]
    source_stats: dict[str, dict]
    warnings: list[str]


def collect_sources(
    sources: list[dict],
    max_items: int,
    log_fn: LogFn,
    trace: TraceWriter | None = None,
    connector_factory: ConnectorFactoryFn = create_connector,
) -> CollectResult:
    """활성화된 source들을 수집하고 runner가 쓰는 통계 형식으로 반환한다.

    비활성 source와 등록되지 않은 source type은 수집 대상에서 건너뛴다.
    개별 source 수집 실패는 전체 run을 중단하지 않고 warning/source_stats에 남긴다.
    """
    all_items: list[dict] = []
    source_stats: dict[str, dict] = {}
    warnings: list[str] = []

    for source in sources:
        source_type = source.get("type")
        if not source.get("enabled", True) or not is_supported_source(source_type):
            continue

        connector = connector_factory(source, max_items)
        log_fn(f"Collecting from {source_type}...")
        started_at = perf_counter()
        if trace:
            trace.write(
                "connector_started",
                stage="collect",
                source_type=source_type,
                max_items=max_items,
            )
        try:
            items = connector.collect()
            duration_ms = int((perf_counter() - started_at) * 1000)
            source_stats[source_type] = {
                "fetched": len(items),
                "used": len(items),
                "failed": 0,
            }
            all_items.extend(items)
            log_fn(f"  {source_type}: {len(items)} items")
            if trace:
                trace.write(
                    "connector_completed",
                    stage="collect",
                    duration_ms=duration_ms,
                    source_type=source_type,
                    fetched=len(items),
                    used=len(items),
                    failed=0,
                    max_items=max_items,
                )
        except Exception as error:
            duration_ms = int((perf_counter() - started_at) * 1000)
            warning = f"{source_type} 수집 실패: {error}"
            warnings.append(warning)
            source_stats[source_type] = {"fetched": 0, "used": 0, "failed": 1}
            log_fn(f"  {source_type} ERROR: {error}")
            if trace:
                trace.write(
                    "connector_failed",
                    stage="collect",
                    duration_ms=duration_ms,
                    source_type=source_type,
                    fetched=0,
                    used=0,
                    failed=1,
                    max_items=max_items,
                    error_type=type(error).__name__,
                    error_message=str(error),
                )

    return CollectResult(
        items=all_items,
        source_stats=source_stats,
        warnings=warnings,
    )
