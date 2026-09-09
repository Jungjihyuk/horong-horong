"""리포트에서 «타임라인으로 만들 수 있는 주제» 를 제안한다.

사용자가 없는 주제를 지어내 요청하면 빈 타임라인이 나온다. 그래서 앱은 **실제 리포트에
존재하는 주제만** 제시하고, 사용자는 그중에서 고른다.

LLM 을 쓰지 않는다. 리포트 헤딩을 훑어 별칭 클러스터로 묶고, 각 후보가 실제로 몇 건의
사건과 몇 개월치를 만들어낼지 세는 것이 전부다(117편 기준 0.05초).
"""

from __future__ import annotations

import os
from collections import Counter
from dataclasses import asdict, dataclass, field

from timeline.ingest import (
    ALIAS_CLUSTERS,
    CLUSTER_LABELS,
    SKIP_HEADINGS,
    collect_events,
    norm,
    parse_reports,
    query_terms,
)
from timeline.state import timeline_state_path

# 온톨로지가 분류하지 못한 것을 담는 버킷이라 주제가 아니다.
EXCLUDED_HEADINGS = {"기타", "미분류"}


@dataclass
class TimelineSuggestion:
    """타임라인으로 만들 수 있는 주제 후보 하나."""

    label: str  # 사용자에게 보이는 이름이자 `--category` 로 넘길 질의
    headings: list[str] = field(default_factory=list)  # 이 후보가 포함하는 리포트 헤딩
    event_count: int = 0  # 만들면 나올 시점 수
    month_count: int = 0
    date_from: str = ""
    date_to: str = ""
    already_exists: bool = False  # 이미 만들어 둔 타임라인인가
    estimated_calls: int = 0  # 처음 만들 때 드는 LLM 호출 수(개월 수 + 개요 1회)

    def to_dict(self) -> dict:
        return asdict(self)


def _cluster_index(heading: str) -> int | None:
    """헤딩이 속한 별칭 클러스터. 어디에도 안 맞으면 None."""
    normalized = norm(heading)
    for index, cluster in enumerate(ALIAS_CLUSTERS):
        for term in cluster:
            if term and (term in normalized or normalized in term):
                return index
    return None


def suggest_topics(
    output_dir: str,
    *,
    min_events: int = 3,
    min_months: int = 2,
) -> list[TimelineSuggestion]:
    """만들 수 있는 주제를 사건이 많은 순으로 돌려준다.

    `min_events`/`min_months` 미만인 후보는 뺀다 — 한두 건짜리 타임라인은 만들어도
    읽을 것이 없고, 만드는 데 LLM 비용만 든다.
    """
    reports_dir = os.path.join(output_dir, "data", "reports")
    parsed = parse_reports(reports_dir)
    if not parsed:
        return []

    # 어떤 헤딩이 얼마나 나왔는지, 그리고 클러스터에 안 잡히는 헤딩은 무엇인지.
    heading_counts: Counter[str] = Counter()
    unclustered: Counter[str] = Counter()
    for _date, sections in parsed:
        for section in sections:
            heading = section["heading"]
            if any(skip in heading for skip in SKIP_HEADINGS):
                continue
            heading_counts[heading] += 1
            if _cluster_index(heading) is None:
                unclustered[heading] += 1

    candidates: list[str] = list(CLUSTER_LABELS)
    # 클러스터에 안 잡히는 헤딩도 후보로 올린다 — 새 분야가 생겨도 놓치지 않는다.
    # 등장 횟수가 많은 것을 먼저 둬야, 겹치는 헤딩 묶음에서 대표 이름이 그쪽으로 잡힌다.
    candidates += [
        heading for heading, _count in unclustered.most_common()
        if heading not in EXCLUDED_HEADINGS
    ]

    suggestions: list[TimelineSuggestion] = []
    seen_labels: set[str] = set()
    # 같은 헤딩 묶음을 가리키는 후보는 하나만 남긴다. 부분일치 매칭 때문에
    # «정치/분쟁»·«정치/사법»·«지정학/정치 리스크» 가 전부 같은 3개 헤딩을 잡는다.
    seen_heading_sets: set[frozenset[str]] = set()
    for label in candidates:
        if label in seen_labels or label in EXCLUDED_HEADINGS:
            continue
        seen_labels.add(label)

        terms = query_terms(label)
        events = collect_events(reports_dir, "preview", terms, parsed=parsed)
        if not events:
            continue

        months = sorted({event.date[:7] for event in events})
        if len(events) < min_events or len(months) < min_months:
            continue

        matched = sorted(
            heading for heading in heading_counts
            if any(term and (term in norm(heading) or norm(heading) in term) for term in terms)
            and not any(skip in heading for skip in SKIP_HEADINGS)
        )
        fingerprint = frozenset(matched)
        if fingerprint in seen_heading_sets:
            continue
        seen_heading_sets.add(fingerprint)

        suggestions.append(
            TimelineSuggestion(
                label=label,
                headings=matched,
                event_count=len(events),
                month_count=len(months),
                date_from=events[0].date,
                date_to=events[-1].date,
                already_exists=os.path.exists(
                    timeline_state_path(output_dir, category_id_for(label))
                ),
                estimated_calls=len(months) + 1,
            )
        )

    suggestions.sort(key=lambda item: (-item.event_count, item.label))
    return suggestions


def category_id_for(label: str) -> str:
    """라벨 → 파일명으로 쓸 안정 식별자. `timeline_runner.py` 와 같은 규칙이어야 한다."""
    import re
    import unicodedata

    normalized = unicodedata.normalize("NFC", label).strip()
    return re.sub(r"[\s/]+", "-", normalized).strip("-") or "untitled"
